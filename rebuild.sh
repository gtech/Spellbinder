#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Pausing watchdog..."
if [ -f /tmp/spellbinder-watchdog.pid ]; then
    kill "$(cat /tmp/spellbinder-watchdog.pid)" 2>/dev/null || true
    rm -f /tmp/spellbinder-watchdog.pid
fi

echo "Stopping spellbinder..."
podman stop spellbinder 2>/dev/null || true
podman rm spellbinder 2>/dev/null || true

echo "Pruning old images..."
podman image prune -f >/dev/null 2>&1 || true

echo "Building..."
podman build -t spellbinder .

echo "Starting..."
./run_container.sh "$@"

echo "Up. Waiting for server..."
sleep 3
podman logs --tail 5 spellbinder
