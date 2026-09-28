#!/usr/bin/env bash
set -Eeuo pipefail

# Start the browser LXC and wait for the API using the current DHCP IP.
# Run on the PVE host.
#
# Usage:
#   cd /root/api
#   ./start-browser-lxc.sh
#
# Optional:
#   CTID=9000 ./start-browser-lxc.sh

CTID="${CTID:-9000}"
API_PORT="${API_PORT:-6081}"
API_TIMEOUT="${API_TIMEOUT:-2}"
WAIT_SECONDS="${WAIT_SECONDS:-60}"

get_lxc_ip() {
    pct exec "$CTID" -- sh -c '
        ip -4 -o addr show dev eth0 2>/dev/null |
        awk "{print \$4}" |
        cut -d/ -f1 |
        grep -v "^127\." |
        head -n 1
    ' 2>/dev/null || true
}

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run this script as root on the PVE host" >&2
    exit 1
fi

command -v pct >/dev/null 2>&1 || {
    echo "ERROR: pct command not found" >&2
    exit 1
}

if ! pct status "$CTID" >/dev/null 2>&1; then
    echo "ERROR: LXC ${CTID} does not exist" >&2
    exit 1
fi

echo "[1/5] Starting LXC"
pct start "$CTID" 2>/dev/null || true

IP=""
for _ in $(seq 1 "$WAIT_SECONDS"); do
    IP="$(get_lxc_ip)"
    if [ -n "$IP" ]; then
        break
    fi
    sleep 1
done

if [ -z "$IP" ]; then
    echo "ERROR: unable to obtain current DHCP IP for CT ${CTID}" >&2
    pct exec "$CTID" -- ip -4 addr >&2 || true
    exit 1
fi

echo "Current LXC IP: ${IP}"

echo "[2/5] Starting desktop/API in LXC"
pct exec "$CTID" -- rc-service browser-supervisor start

echo "supervisor started"

echo "[3/5] Waiting for API at ${IP}:${API_PORT}"

API_READY=0
for _ in $(seq 1 "$WAIT_SECONDS"); do
    # Refresh DHCP IP every iteration so a lease change cannot leave us
    # polling an old address.
    CURRENT_IP="$(get_lxc_ip)"
    if [ -n "$CURRENT_IP" ] && [ "$CURRENT_IP" != "$IP" ]; then
        IP="$CURRENT_IP"
        echo "LXC IP changed; using current IP: ${IP}"
    fi

    if curl --fail --silent --show-error \
        --connect-timeout "$API_TIMEOUT" \
        --max-time "$((API_TIMEOUT + 3))" \
        "http://${IP}:${API_PORT}/health" \
        >/tmp/browser-api-health.json 2>/dev/null; then
        API_READY=1
        break
    fi

    sleep 1
done

if [ "$API_READY" -ne 1 ]; then
    echo "ERROR: API failed to start at current IP ${IP}:${API_PORT}" >&2
    pct exec "$CTID" -- rc-service browser-supervisor status >&2 || true
    pct exec "$CTID" -- netstat -lntp >&2 || true
    pct exec "$CTID" -- tail -n 100 \
        /var/log/browser-supervisor.log >&2 || true
    pct exec "$CTID" -- tail -n 100 \
        /var/log/browser-desktop/uvicorn.log >&2 || true
    exit 1
fi

rm -f /tmp/browser-api-health.json

echo "API is ready"
echo "Current LXC IP: ${IP}"
echo "noVNC: http://${IP}:6080/vnc.html"
echo "API:   http://${IP}:${API_PORT}"
