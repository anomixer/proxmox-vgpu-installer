#!/usr/bin/env bash
set -Eeuo pipefail

CTID="${CTID:-9000}"
LXC_HOSTNAME="${LXC_HOSTNAME:-browser-api}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"
MEMORY="${MEMORY:-1024}"
SWAP="${SWAP:-512}"
CORES="${CORES:-1}"
ROOTFS_SIZE="${ROOTFS_SIZE:-4}"
PASSWORD="${PASSWORD:-123456}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
TEMPLATE_FILE="${TEMPLATE_FILE:-}"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run as root" >&2
    exit 1
fi

if ! command -v pct >/dev/null 2>&1; then
    echo "ERROR: pct command not found; run this on a Proxmox VE host" >&2
    exit 1
fi

if pct status "$CTID" >/dev/null 2>&1; then
    echo "ERROR: CTID ${CTID} already exists" >&2
    exit 1
fi

if [ -z "$TEMPLATE_FILE" ]; then
    TEMPLATE_FILE="$(
        pveam available --section system 2>/dev/null |
        awk '/alpine/ && /amd64/ {print $2; exit}'
    )"
fi

if [ -z "$TEMPLATE_FILE" ]; then
    echo "ERROR: Alpine amd64 template not found" >&2
    exit 1
fi

TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_FILE}"

if ! pvesm status --storage "$TEMPLATE_STORAGE" >/dev/null 2>&1; then
    echo "ERROR: template storage not found: ${TEMPLATE_STORAGE}" >&2
    exit 1
fi

if ! pvesm status --storage "$STORAGE" >/dev/null 2>&1; then
    echo "ERROR: rootfs storage not found: ${STORAGE}" >&2
    exit 1
fi

if ! pveam list "$TEMPLATE_STORAGE" |
    awk '{print $1}' |
    grep -Fxq "$TEMPLATE_PATH"; then
    echo "Downloading template: ${TEMPLATE_FILE}"
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_FILE"
fi

echo "Creating LXC"
echo " CTID: ${CTID}"
echo " Hostname: ${LXC_HOSTNAME}"
echo " Template: ${TEMPLATE_PATH}"
echo " Storage: ${STORAGE}"
echo " Bridge: ${BRIDGE}"
echo " Memory: ${MEMORY} MB"
echo " Swap: ${SWAP} MB"
echo " Cores: ${CORES}"
echo " Rootfs: ${ROOTFS_SIZE} GB"

pct create "$CTID" "$TEMPLATE_PATH" \
    --hostname "$LXC_HOSTNAME" \
    --password "$PASSWORD" \
    --rootfs "${STORAGE}:${ROOTFS_SIZE}" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --swap "$SWAP" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp,type=veth" \
    --unprivileged 0 \
    --features nesting=1 \
    --onboot 0 \
    --start 0

cat <<EOF

LXC created successfully.

CTID: ${CTID}
Hostname: ${LXC_HOSTNAME}
Username: root
Password: ${PASSWORD}

Next steps:
  pct start ${CTID}
  cd /root/api
  ./setup-lxc.sh
EOF
