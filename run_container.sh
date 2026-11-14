#!/bin/bash
# Single source of truth for how the spellbinder container is created.
# Used by rebuild.sh, and by watchdog.sh when a wedged container must be
# recreated. Extra args are passed to SpellServer (e.g. --debug=...); the
# watchdog recreates with none.
#
# Server data lives in the spellbinder-data volume, so removing and
# recreating the container loses nothing.
set -e

cd "$(dirname "$0")"
mkdir -p Logs

# --restart=always + podman-restart.service brings the container back after a
# host reboot (rootless podman has no daemon; also needs `loginctl enable-linger`).
systemctl --user enable podman-restart.service >/dev/null 2>&1 || true
podman run -d --name spellbinder --network host --restart=always \
  -v ./Content:/app/Content -v spellbinder-data:/var/lib/mysql \
  -v ./Logs:/app/Logs spellbinder "$@"
