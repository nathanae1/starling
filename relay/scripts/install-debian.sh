#!/usr/bin/env bash
# Install the Starling relay on a Debian/Ubuntu host: create the user,
# drop the binary + config + systemd unit, and start the service.
# Idempotent — safe to re-run for upgrades.
#
# Usage (as root):
#   ./install-debian.sh [path-to-starling-relay-binary]
# If no binary path is given, expects ./starling-relay next to this script.
set -euo pipefail

BINARY="${1:-$(dirname "$0")/starling-relay}"
PREFIX=/usr/local/bin
CONFIG_DIR=/etc/starling-relay
UNIT=/etc/systemd/system/starling-relay.service
USER=starling

if [[ $EUID -ne 0 ]]; then
  echo "must run as root" >&2
  exit 1
fi
if [[ ! -f "$BINARY" ]]; then
  echo "binary not found: $BINARY" >&2
  exit 1
fi

echo "==> creating user '$USER'"
if ! id "$USER" &>/dev/null; then
  useradd --system --home /var/lib/starling-relay --shell /usr/sbin/nologin "$USER"
fi

echo "==> installing binary to $PREFIX/starling-relay"
install -m 0755 "$BINARY" "$PREFIX/starling-relay"

echo "==> writing config (if absent)"
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_DIR/config.toml" ]]; then
  install -m 0644 "$(dirname "$0")/../config.example.toml" "$CONFIG_DIR/config.toml"
fi

echo "==> installing systemd unit"
install -m 0644 "$(dirname "$0")/../systemd/starling-relay.service" "$UNIT"
systemctl daemon-reload
systemctl enable starling-relay
# restart (not `enable --now`): starts a stopped unit on fresh install AND
# swaps a running one onto the just-installed binary on upgrade.
systemctl restart starling-relay

echo
echo "Relay installed and started. Tor bootstrap takes ~30s."
echo "Admin UI is on 127.0.0.1:8088 — tunnel in with:"
echo "    ssh -L 8088:127.0.0.1:8088 <user>@<this-host>"
echo "Then open http://127.0.0.1:8088, or pair from the CLI:"
echo "    sudo -u $USER starling-relay pair --config $CONFIG_DIR/config.toml --label my-phone"
