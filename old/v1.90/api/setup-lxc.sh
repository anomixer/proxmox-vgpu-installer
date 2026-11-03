#!/usr/bin/env bash
set -Eeuo pipefail

CTID="${CTID:-9000}"
PROJECT_DIR="${PWD}"
SUPERVISOR_SOURCE="${PROJECT_DIR}/browser-supervisor.sh"
MAIN_SOURCE="${PROJECT_DIR}/main.py"

NOTE_TEMPLATE="${NOTE_TEMPLATE:-$(cat <<'EOF'
LXC Name: browser-api
by: anomixer

Purpose: Isolated Chromium browser environment for file downloads.

Ports:
- Browser API: port 6081
- noVNC web interface: port 6080
- VNC server: port 5901

APIs:
- noVNC: http://(LXC_IP):6080/vnc.html
- Health check: http://(LXC_IP):6081/health
- Start download: http://(LXC_IP):6081/api/download?url=(DOWNLOAD_URL)
- Check download status: http://(LXC_IP):6081/api/check?filename=(FILENAME)

API usage:
1. Open the noVNC URL to view or interact with Chromium when manual login or verification is required.
2. Call /api/download with the URL-encoded file URL to start a browser download.
3. Poll /api/check with the expected filename until the response shows "status":"ready" and "exists":true.
4. On the PVE host, use pct pull to retrieve the file from /home/user/Downloads/(FILENAME).

Example:
- Start download:
  curl --fail --silent --show-error --get \
    --data-urlencode "url=https://example.com/file.run" \
    "http://(LXC_IP):6081/api/download"

- Check status:
  curl --fail --silent --show-error --get \
    --data-urlencode "filename=file.run" \
    "http://(LXC_IP):6081/api/check"

Login:
- Username: root
- Password: 123456

Note: This is the default password for the test environment. Change it before production use. Restrict network access to ports 5901, 6080, and 6081.
EOF
)}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root on PVE" >&2; exit 1; }
command -v pct >/dev/null 2>&1 || { echo "ERROR: pct not found" >&2; exit 1; }
pct status "$CTID" >/dev/null 2>&1 || { echo "ERROR: LXC ${CTID} does not exist" >&2; exit 1; }

for file in "$SUPERVISOR_SOURCE" "$MAIN_SOURCE"; do
    [ -f "$file" ] || {
        echo "ERROR: required file not found: $file" >&2
        echo "Current directory: $PROJECT_DIR" >&2
        exit 1
    }
done

if ! pct status "$CTID" | grep -q 'status: running'; then
    echo "[1/8] Starting LXC"
    pct start "$CTID"
    sleep 5
else
    echo "[1/8] LXC already running"
fi

echo "[2/8] Waiting for LXC network"
NETWORK_READY=0
for _ in $(seq 1 30); do
    if pct exec "$CTID" -- ip link show eth0 >/dev/null 2>&1; then
        NETWORK_READY=1
        break
    fi
    sleep 1
done
[ "$NETWORK_READY" -eq 1 ] || { echo "ERROR: LXC network not ready" >&2; exit 1; }

echo "[3/8] Installing all runtime dependencies"
pct exec "$CTID" -- sh -euxc '
apk update
apk add --no-cache \
bash ca-certificates chromium curl fluxbox gcc musl-dev \
net-tools novnc openrc py3-pip python3 python3-dev \
tini websockify x11vnc xvfb xterm

python3 -m venv /opt/browser-api
/opt/browser-api/bin/pip install --no-cache-dir fastapi uvicorn

mkdir -p /home/user/Downloads /var/log/browser-desktop /run/browser-supervisor
'

echo "[4/8] Pushing main.py"
echo "Source: ${MAIN_SOURCE}"
echo "Target: /usr/local/bin/main.py"
pct push "$CTID" "$MAIN_SOURCE" /usr/local/bin/main.py --perms 0755

echo "[5/8] Pushing browser-supervisor.sh"
echo "Source: ${SUPERVISOR_SOURCE}"
echo "Target: /usr/local/bin/browser-supervisor.sh"
pct push "$CTID" "$SUPERVISOR_SOURCE" /usr/local/bin/browser-supervisor.sh --perms 0755

echo "[6/8] Installing OpenRC service"
cat >/tmp/browser-supervisor.openrc <<'RCFILE'
#!/sbin/openrc-run

name="browser-supervisor"
description="Xvfb, Fluxbox, debug terminal, VNC, noVNC and browser API"
command="/usr/local/bin/browser-supervisor.sh"
command_user="root"
supervisor="supervise-daemon"
supervise_daemon_args="--stdout /var/log/browser-supervisor.log --stderr /var/log/browser-supervisor.log"
pidfile="/run/browser-supervisor.pid"

depend() {
    need localmount
    after bootmisc
}
RCFILE
chmod 0755 /tmp/browser-supervisor.openrc
pct push "$CTID" /tmp/browser-supervisor.openrc /etc/init.d/browser-supervisor --perms 0755
rm -f /tmp/browser-supervisor.openrc

echo "[7/8] Configuring runtime and validating installation"
pct exec "$CTID" -- sh -euxc '
chmod 0755 /usr/local/bin/main.py /usr/local/bin/browser-supervisor.sh
rc-update add browser-supervisor default 2>/dev/null || true

/opt/browser-api/bin/python - <<"PY"
import fastapi, uvicorn
print("fastapi OK:", fastapi.__file__)
print("uvicorn OK:", uvicorn.__file__)
PY

command -v Xvfb
command -v fluxbox
command -v xterm
command -v x11vnc
command -v websockify
test -f /usr/share/novnc/vnc.html
test -f /usr/local/bin/main.py
test -x /usr/local/bin/browser-supervisor.sh
test -x /etc/init.d/browser-supervisor
'

echo "[8/8] Writing PVE note"
if pct set "$CTID" --description "$NOTE_TEMPLATE"; then
    echo "PVE note added to CTID ${CTID}"
else
    echo "WARNING: setup completed, but failed to set the PVE note" >&2
    exit 1
fi

echo
echo "========================================"
echo "LXC setup completed successfully"
echo "========================================"
echo "CTID: ${CTID}"
echo "Hostname: browser-api"
echo "Project dir: ${PROJECT_DIR}"
echo "main.py: ${MAIN_SOURCE} -> /usr/local/bin/main.py"
echo "supervisor: ${SUPERVISOR_SOURCE} -> /usr/local/bin/browser-supervisor.sh"
echo "PVE note: updated"
echo "API Python: /opt/browser-api/bin/python"
echo "========================================"
