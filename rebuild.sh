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

mkdir -p Logs

echo "Pruning old images..."
podman image prune -f >/dev/null 2>&1 || true

echo "Building..."
podman build -t spellbinder .

echo "Starting..."
# --restart=always + podman-restart.service brings the container back after a
# host reboot (rootless podman has no daemon; also needs `loginctl enable-linger`).
systemctl --user enable podman-restart.service >/dev/null 2>&1 || true
podman run -d --name spellbinder --network host --restart=always \
  -v ./Content:/app/Content -v spellbinder-data:/var/lib/mysql \
  -v ./Logs:/app/Logs spellbinder "$@"

echo "Up. Waiting for server..."
sleep 3
podman logs --tail 5 spellbinder
