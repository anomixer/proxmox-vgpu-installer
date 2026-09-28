#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:1}"
export HOME="${HOME:-/root}"
export USER="${USER:-root}"

LOG_DIR="${LOG_DIR:-/var/log/browser-desktop}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/home/user/Downloads}"
API_DIR="${API_DIR:-/usr/local/bin}"
API_MODULE="${API_MODULE:-main:app}"
API_PYTHON="${API_PYTHON:-/opt/browser-api/bin/python}"
SCREEN_GEOMETRY="${SCREEN_GEOMETRY:-1280x800x24}"
VNC_PORT="${VNC_PORT:-5901}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
API_PORT="${API_PORT:-6081}"
PID_DIR="/run/browser-supervisor"

mkdir -p "$LOG_DIR" "$DOWNLOAD_DIR" "$PID_DIR"

XVFB_PIDFILE="$PID_DIR/xvfb.pid"
FLUXBOX_PIDFILE="$PID_DIR/fluxbox.pid"
XTERM_PIDFILE="$PID_DIR/xterm.pid"
X11VNC_PIDFILE="$PID_DIR/x11vnc.pid"
NOVNC_PIDFILE="$PID_DIR/novnc.pid"
API_PIDFILE="$PID_DIR/api.pid"

pid_alive() {
    local pid="${1:-}"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

stop_pidfile() {
    local pidfile="$1"
    local pid=""
    [ -f "$pidfile" ] && pid="$(cat "$pidfile" 2>/dev/null || true)"
    if pid_alive "$pid"; then
        kill "$pid" 2>/dev/null || true
        for _ in $(seq 1 20); do
            pid_alive "$pid" || break
            sleep 0.1
        done
        pid_alive "$pid" && kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile"
}

write_pid() { printf '%s\n' "$2" > "$1"; }

cleanup() {
    trap - EXIT INT TERM HUP
    stop_pidfile "$API_PIDFILE"
    stop_pidfile "$NOVNC_PIDFILE"
    stop_pidfile "$X11VNC_PIDFILE"
    stop_pidfile "$XTERM_PIDFILE"
    stop_pidfile "$FLUXBOX_PIDFILE"
    stop_pidfile "$XVFB_PIDFILE"
}

trap 'exit 0' INT TERM HUP
trap cleanup EXIT
cleanup

for command_name in Xvfb fluxbox xterm x11vnc websockify; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: ${command_name}" >&2
        exit 1
    }
done

[ -x "$API_PYTHON" ] || {
    echo "ERROR: API Python not found: ${API_PYTHON}" >&2
    exit 1
}

"$API_PYTHON" -c 'import fastapi, uvicorn' >/dev/null 2>&1 || {
    echo "ERROR: fastapi/uvicorn is not installed in ${API_PYTHON}" >&2
    exit 1
}

[ -f "${API_DIR}/main.py" ] || {
    echo "ERROR: API file not found: ${API_DIR}/main.py" >&2
    exit 1
}

[ -f /usr/share/novnc/vnc.html ] || {
    echo "ERROR: noVNC file not found: /usr/share/novnc/vnc.html" >&2
    exit 1
}

Xvfb "$DISPLAY" -screen 0 "$SCREEN_GEOMETRY" -ac -nolisten tcp \
    >"$LOG_DIR/xvfb.log" 2>&1 &
XVFB_PID="$!"
write_pid "$XVFB_PIDFILE" "$XVFB_PID"
sleep 2
pid_alive "$XVFB_PID" || { echo "ERROR: Xvfb exited" >&2; exit 1; }

fluxbox >"$LOG_DIR/fluxbox.log" 2>&1 &
FLUXBOX_PID="$!"
write_pid "$FLUXBOX_PIDFILE" "$FLUXBOX_PID"

xterm \
    -display "$DISPLAY" \
    -title "LXC Debug Terminal" \
    -geometry 100x30+20+20 \
    -e /bin/sh \
    >"$LOG_DIR/xterm.log" 2>&1 &
XTERM_PID="$!"
write_pid "$XTERM_PIDFILE" "$XTERM_PID"

x11vnc -display "$DISPLAY" -rfbport "$VNC_PORT" -forever -shared \
    -noxdamage -noxkb -cursor arrow -nopw \
    >"$LOG_DIR/x11vnc.log" 2>&1 &
X11VNC_PID="$!"
write_pid "$X11VNC_PIDFILE" "$X11VNC_PID"

websockify --web /usr/share/novnc "$NOVNC_PORT" "127.0.0.1:${VNC_PORT}" \
    >"$LOG_DIR/novnc.log" 2>&1 &
NOVNC_PID="$!"
write_pid "$NOVNC_PIDFILE" "$NOVNC_PID"

cd "$API_DIR"
"$API_PYTHON" -m uvicorn "$API_MODULE" --host 0.0.0.0 --port "$API_PORT" \
    >"$LOG_DIR/uvicorn.log" 2>&1 &
API_PID="$!"
write_pid "$API_PIDFILE" "$API_PID"

sleep 3
pid_alive "$API_PID" || {
    echo "ERROR: Browser API exited" >&2
    cat "$LOG_DIR/uvicorn.log" >&2 || true
    exit 1
}

for entry in "$XTERM_PIDFILE" "$X11VNC_PIDFILE" "$NOVNC_PIDFILE" "$API_PIDFILE"; do
    pid="$(cat "$entry" 2>/dev/null || true)"
    pid_alive "$pid" || {
        echo "ERROR: service process exited: ${entry}" >&2
        exit 1
    }
done

echo "desktop, Fluxbox, debug terminal, noVNC and API started"
echo "DISPLAY=${DISPLAY}"
echo "VNC_PORT=${VNC_PORT}"
echo "NOVNC_PORT=${NOVNC_PORT}"
echo "API_PORT=${API_PORT}"

wait "$XVFB_PID"
