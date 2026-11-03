#!/usr/bin/env bash
set -Eeuo pipefail

# End-to-end browser LXC download test.
# Run on the PVE host from the project directory.
#
# Usage:
#   cd /root/api
#   ./test-lxc.sh
#
# Optional overrides:
#   CTID=9000 FILENAME=file.run DRIVER_URL=https://example.com/file.run ./test-lxc.sh

CTID="${CTID:-9000}"
FILENAME="${FILENAME:-NVIDIA-Linux-x86_64-550.163.01-grid.run}"
DRIVER_URL="${DRIVER_URL:-https://alist.homelabproject.cc/d/foxipan/vGPU/17.6/NVIDIA-GRID-Linux-KVM-550.163.02-550.163.01-553.74/Guest_Drivers/NVIDIA-Linux-x86_64-550.163.01-grid.run}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/home/user/Downloads}"
POLL_INTERVAL="${POLL_INTERVAL:-10}"
POLL_LIMIT="${POLL_LIMIT:-360}"

log() { printf '%s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; }

get_lxc_ip() {
    pct exec "$CTID" -- sh -c '
        ip -4 -o addr show dev eth0 2>/dev/null |
        awk "{print \$4}" |
        cut -d/ -f1 |
        grep -v "^127\." |
        head -n 1
    ' 2>/dev/null || true
}

service_status() {
    pct exec "$CTID" -- rc-service browser-supervisor status 2>&1 || true
}

ports() {
    pct exec "$CTID" -- netstat -lntp 2>/dev/null || true
}

show_logs() {
    log "--- browser-supervisor status ---"
    service_status || true
    log "--- listening ports ---"
    ports || true
    log "--- supervisor log ---"
    pct exec "$CTID" -- tail -n 100 /var/log/browser-supervisor.log 2>/dev/null || true
    log "--- x11vnc log ---"
    pct exec "$CTID" -- tail -n 100 /var/log/browser-desktop/x11vnc.log 2>/dev/null || true
    log "--- noVNC log ---"
    pct exec "$CTID" -- tail -n 100 /var/log/browser-desktop/novnc.log 2>/dev/null || true
    log "--- API log ---"
    pct exec "$CTID" -- tail -n 100 /var/log/browser-desktop/uvicorn.log 2>/dev/null || true
    log "--- Chromium log ---"
    pct exec "$CTID" -- tail -n 100 /var/log/browser-desktop/chromium.log 2>/dev/null || true
}

on_error() {
    error "test failed"
    show_logs
}

trap on_error ERR

[ "$(id -u)" -eq 0 ] || { error "run as root on PVE"; exit 1; }
command -v pct >/dev/null 2>&1 || { error "pct command not found"; exit 1; }
pct status "$CTID" >/dev/null 2>&1 || { error "LXC ${CTID} does not exist"; exit 1; }

log "Waiting for DHCP address..."
IP=""
for _ in $(seq 1 30); do
    IP="$(get_lxc_ip)"
    [ -n "$IP" ] && break
    sleep 1
done

[ -n "$IP" ] || { error "unable to obtain DHCP IP"; exit 1; }
log "LXC IP: ${IP}"

log "[1/7] Starting LXC"
pct start "$CTID" 2>/dev/null || true
sleep 3

log "[2/7] Checking service state"
SERVICE_STATUS="$(service_status)"
if echo "$SERVICE_STATUS" | grep -q "started"; then
    log "browser-supervisor already running; reusing it"
else
    pct exec "$CTID" -- rc-service browser-supervisor start
fi

log "[3/7] Browser desktop/API start check"
SERVICE_STATUS="$(service_status)"
if ! echo "$SERVICE_STATUS" | grep -q "started"; then
    error "browser-supervisor failed to start"
    show_logs
    exit 1
fi

log "[4/7] Waiting for ports"
PORTS_READY=0
for _ in $(seq 1 30); do
    LISTENING="$(ports)"
    if echo "$LISTENING" | grep -q ':5901' && \
       echo "$LISTENING" | grep -q ':6080' && \
       echo "$LISTENING" | grep -q ':6081'; then
        PORTS_READY=1
        break
    fi
    sleep 1
done

[ "$PORTS_READY" -eq 1 ] || {
    error "required ports are not all listening"
    show_logs
    exit 1
}

log "5901, 6080 and 6081 are listening"
log "[5/7] Testing HTTP endpoints"

curl --fail --max-time 10 \
    "http://${IP}:6080/vnc.html" \
    -o /dev/null

curl --fail --max-time 10 \
    "http://${IP}:6081/health"
echo

curl --fail --silent --show-error --get \
    --data-urlencode "filename=${FILENAME}" \
    "http://${IP}:6081/api/check"
echo

log "Open noVNC:"
log "http://${IP}:6080/vnc.html"
echo

log "[6/7] Calling download API"
DOWNLOAD_RESPONSE="$(
    curl --fail --silent --show-error --get \
        --data-urlencode "url=${DRIVER_URL}" \
        "http://${IP}:6081/api/download"
)"
printf '%s\n' "$DOWNLOAD_RESPONSE"
echo

log "Waiting for download: ${FILENAME}"
READY=0
LAST_STATE=""

for _ in $(seq 1 "$POLL_LIMIT"); do
    LAST_STATE="$(
        curl --fail --silent --show-error --get \
            --data-urlencode "filename=${FILENAME}" \
            "http://${IP}:6081/api/check" \
            2>/dev/null || true
    )"

    printf '\r%s' "$LAST_STATE"

    if echo "$LAST_STATE" | grep -q '"status":"ready"' && \
       echo "$LAST_STATE" | grep -q '"exists":true'; then
        READY=1
        printf '\n'
        break
    fi

    sleep "$POLL_INTERVAL"
done

if [ "$READY" -ne 1 ]; then
    printf '\n'
    error "download timeout"
    show_logs
    exit 1
fi

log "[7/7] Pulling file to PVE"
CONTAINER_FILE="${DOWNLOAD_DIR}/${FILENAME}"
HOST_PART="/root/${FILENAME}.part"
HOST_FILE="/root/${FILENAME}"

if ! pct exec "$CTID" -- test -s "$CONTAINER_FILE"; then
    error "downloaded file is missing or empty: ${CONTAINER_FILE}"
    pct exec "$CTID" -- ls -lah "$DOWNLOAD_DIR" 2>/dev/null || true
    exit 1
fi

rm -f "$HOST_PART"
pct pull "$CTID" "$CONTAINER_FILE" "$HOST_PART"

if [ ! -s "$HOST_PART" ]; then
    error "pulled file is missing or empty: ${HOST_PART}"
    exit 1
fi

mv -f "$HOST_PART" "$HOST_FILE"

if [ ! -s "$HOST_FILE" ]; then
    error "final PVE file is missing or empty: ${HOST_FILE}"
    exit 1
fi

log "Removing downloaded file from LXC"
pct exec "$CTID" -- rm -f "$CONTAINER_FILE"

if pct exec "$CTID" -- test -e "$CONTAINER_FILE"; then
    error "failed to remove file from LXC: ${CONTAINER_FILE}"
    exit 1
fi

log ""
log "File saved: ${HOST_FILE}"
ls -lh "$HOST_FILE"
file "$HOST_FILE"
log ""
log "LXC file removed: ${CONTAINER_FILE}"
log "Test completed successfully."
