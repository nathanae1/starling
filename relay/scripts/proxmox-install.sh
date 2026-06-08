#!/usr/bin/env bash
# Create a minimal Debian-12 LXC on a Proxmox host and install the Starling
# relay inside it. Run on the Proxmox node.
#
# Usage:
#   ./proxmox-install.sh <ctid> <binary-url-or-path>
# Example:
#   ./proxmox-install.sh 200 https://example/starling-relay-amd64
set -euo pipefail

CTID="${1:?usage: proxmox-install.sh <ctid> <binary-url-or-path>}"
BINARY_SRC="${2:?usage: proxmox-install.sh <ctid> <binary-url-or-path>}"
TEMPLATE="${TEMPLATE:-local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst}"
STORAGE="${STORAGE:-local-lvm}"
HOSTNAME="${HOSTNAME:-starling-relay}"

if ! command -v pct >/dev/null; then
  echo "pct not found — run this on a Proxmox node" >&2
  exit 1
fi

echo "==> creating LXC $CTID ($HOSTNAME)"
pct create "$CTID" "$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --cores 1 --memory 256 --swap 256 \
  --rootfs "$STORAGE:8" \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 \
  --features nesting=1 \
  --onboot 1

pct start "$CTID"
echo "==> waiting for container network…"
sleep 8

echo "==> staging binary"
if [[ "$BINARY_SRC" =~ ^https?:// ]]; then
  pct exec "$CTID" -- bash -lc "apt-get update && apt-get install -y curl ca-certificates && curl -sSL '$BINARY_SRC' -o /root/starling-relay"
else
  pct push "$CTID" "$BINARY_SRC" /root/starling-relay
fi

echo "==> running installer"
pct push "$CTID" "$(dirname "$0")/install-debian.sh" /root/install-debian.sh
pct push "$CTID" "$(dirname "$0")/../config.example.toml" /root/config.example.toml
pct push "$CTID" "$(dirname "$0")/../systemd/starling-relay.service" /root/starling-relay.service
# install-debian.sh expects ../config.example.toml and ../systemd/ relative
# to itself; lay them out accordingly.
pct exec "$CTID" -- bash -lc "mkdir -p /root/pkg/systemd && mv /root/config.example.toml /root/pkg/ && mv /root/starling-relay.service /root/pkg/systemd/ && mv /root/install-debian.sh /root/pkg/ && chmod +x /root/pkg/install-debian.sh && /root/pkg/install-debian.sh /root/starling-relay"

echo
echo "Done. Container $CTID is running the relay."
echo "Pair a phone:  pct exec $CTID -- starling-relay pair --config /etc/starling-relay/config.toml --label my-phone"
