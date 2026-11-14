#!/bin/bash
# Watchdog — polls /api/health every 10 seconds.
# Health endpoint checks arena tick recency, not just API liveness.
# If 3 consecutive failures (tick stale >5s or API down), dumps thread stacks and restarts.
#
# Usage: ./watchdog.sh &
# Safe to call from cron — exits if already running.

# Cron starts us in $HOME; dumps, Logs/ and run_container.sh are relative to here.
cd "$(dirname "$0")"

PIDFILE="/tmp/spellbinder-watchdog.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"
trap "rm -f $PIDFILE" EXIT

CONTAINER="spellbinder"
HEALTH_URL="http://localhost:10603/api/health"
FAIL_THRESHOLD=3
POLL_INTERVAL=10
# Loading arenas takes ~70s on boot. Failures while the container is younger
# than this are startup, not a hang — don't count them, or we kill it mid-load.
STARTUP_GRACE=180

fails=0

# Seconds since the container last started; huge if it doesn't exist.
container_age() {
    local started
    started=$(podman inspect "$CONTAINER" --format '{{.State.StartedAt.Unix}}' 2>/dev/null) || { echo 999999; return; }
    echo $(( $(date +%s) - started ))
}

recover_container() {
    podman restart "$CONTAINER" && return 0

    # Stale rootless podman state (e.g. after a host reboot) makes every
    # restart fail with "invalid internal status" until migrated.
    echo "[watchdog] $(date '+%H:%M:%S') RESTART FAILED — running podman system migrate"
    podman system migrate
    podman start "$CONTAINER" && return 0

    # A container caught mid-shutdown by a reboot can be left "Stopping" in
    # podman's DB while runc has no record of it. stop/kill/cleanup are all
    # no-ops on it; only rm clears it. Data is in a named volume, so recreate.
    echo "[watchdog] $(date '+%H:%M:%S') START FAILED — recreating container"
    podman rm -f --ignore "$CONTAINER" && ./run_container.sh && return 0

    echo "[watchdog] $(date '+%H:%M:%S') RECREATE FAILED — needs manual attention"
    return 1
}

echo "[watchdog] Started. Polling $HEALTH_URL every ${POLL_INTERVAL}s (threshold: ${FAIL_THRESHOLD} failures)"

while true; do
    response=$(curl -s --max-time 5 "$HEALTH_URL" 2>/dev/null)
    http_ok=$?

    if [ $http_ok -eq 0 ] && echo "$response" | grep -q '"healthy":true'; then
        if [ $fails -gt 0 ]; then
            echo "[watchdog] $(date '+%H:%M:%S') Recovered after $fails failures"
        fi
        fails=0
    elif age=$(container_age) && [ "$age" -lt "$STARTUP_GRACE" ]; then
        echo "[watchdog] $(date '+%H:%M:%S') Not healthy yet, container started ${age}s ago — in startup grace"
        fails=0
    else
        fails=$((fails + 1))
        if [ $http_ok -ne 0 ]; then
            echo "[watchdog] $(date '+%H:%M:%S') API unreachable ($fails/$FAIL_THRESHOLD)"
        else
            echo "[watchdog] $(date '+%H:%M:%S') Tick stale: $response ($fails/$FAIL_THRESHOLD)"
        fi

        if [ $fails -ge $FAIL_THRESHOLD ]; then
            echo "[watchdog] $(date '+%H:%M:%S') Server hung — dumping thread stacks"

            echo "=== THREAD DUMP ===" >> watchdog_dumps.log
            echo "$(date)" >> watchdog_dumps.log

            # SIGQUIT makes Mono dump all thread stacks to container logs
            podman exec "$CONTAINER" kill -QUIT 1 2>/dev/null
            sleep 3

            # Capture the thread dump BEFORE restarting
            podman logs --since 8s "$CONTAINER" >> watchdog_dumps.log 2>&1

            # Also grab recent game logs for context
            echo "--- GAME LOG CONTEXT ---" >> watchdog_dumps.log
            cat Logs/Main/$(date '+%b.%d.%Y').txt 2>/dev/null | tail -50 >> watchdog_dumps.log
            echo "===================" >> watchdog_dumps.log

            echo "[watchdog] $(date '+%H:%M:%S') Restarting container"
            if recover_container; then
                echo "[watchdog] $(date '+%H:%M:%S') Restarted"
            fi
            fails=0
        fi
    fi

    sleep $POLL_INTERVAL
done
