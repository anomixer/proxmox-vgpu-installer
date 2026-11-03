#!/bin/bash
# lib/lxc-browser.sh - Browser LXC downloader (v1.90)
# Uses the api/ directory (create-lxc.sh / setup-lxc.sh / start-browser-lxc.sh)
# and the LXC Browser API (native Chromium via Xvfb + noVNC) to download files
# directly onto the PVE host, so the user does not need to download manually and
# scp the file back.

# --- configuration -----------------------------------------------------------
VGPU_LXC_CTID_BASE="${VGPU_LXC_CTID_BASE:-9000}"
VGPU_LXC_API_PORT="${VGPU_LXC_API_PORT:-6081}"
VGPU_LXC_NOVNC_PORT="${VGPU_LXC_NOVNC_PORT:-6080}"
VGPU_LXC_API_TIMEOUT="${VGPU_LXC_API_TIMEOUT:-60}"
VGPU_LXC_POLL_TIMEOUT="${VGPU_LXC_POLL_TIMEOUT:-900}"   # seconds, for large files
VGPU_LXC_POLL_INTERVAL="${VGPU_LXC_POLL_INTERVAL:-5}"
VGPU_LXC_PVE_DIR="${VGPU_LXC_PVE_DIR:-$SCRIPT_DIR/api}"

# --- helpers -----------------------------------------------------------------
lxc_browser_pve_dir() { echo "$VGPU_LXC_PVE_DIR"; }

lxc_browser_exists() {
    pct status "$1" >/dev/null 2>&1
}

# Read the LXC hostname from its config so this also works while the container
# is STOPPED (pct exec would fail on a stopped container and break reuse).
lxc_browser_hostname() {
    pct config "$1" 2>/dev/null | sed -n 's/^hostname:[[:space:]]*//p' | head -1
}

lxc_browser_get_ip() {
    pct exec "$1" -- sh -c '
        ip -4 -o addr show dev eth0 2>/dev/null |
        awk "{print \$4}" |
        cut -d/ -f1 |
        grep -v "^127\." |
        head -n 1
    ' 2>/dev/null || true
}

# Return 0 if the browser API for CTID is reachable.
lxc_browser_api_ready() {
    local ctid="$1"
    local ip
    ip=$(lxc_browser_get_ip "$ctid")
    if [ -z "$ip" ]; then
        return 1
    fi
    curl --fail --silent --connect-timeout 2 --max-time 5 \
        "http://${ip}:${VGPU_LXC_API_PORT}/health" >/dev/null 2>&1
}

# Return 0 if the CTID is a browser LXC (hostname browser-api).
lxc_browser_is_browser_ct() {
    [ "$(lxc_browser_hostname "$1")" = "browser-api" ]
}

# Find a browser LXC CTID to use: reuse a ready one, start a stopped browser
# LXC, else return the first free CTID (creating there). Echoes the CTID on
# stdout; returns 1 if none is available.
lxc_browser_find_ctid() {
    local base="$VGPU_LXC_CTID_BASE"
    local ctid i
    # 1. Reuse: an existing CTID whose API is already ready.
    for i in $(seq 0 9); do
        ctid=$((base + i))
        if lxc_browser_api_ready "$ctid"; then
            echo "$ctid"
            return 0
        fi
    done
    # 2. Reuse (stopped browser LXC): start it and wait for the API.
    for i in $(seq 0 9); do
        ctid=$((base + i))
        if lxc_browser_exists "$ctid" && lxc_browser_is_browser_ct "$ctid"; then
            pct start "$ctid" 2>/dev/null || true
            for _ in $(seq 1 "$VGPU_LXC_API_TIMEOUT"); do
                if lxc_browser_api_ready "$ctid"; then
                    echo "$ctid"
                    return 0
                fi
                sleep 1
            done
        fi
    done
    # 3. Create: first free CTID (base, base+1, ...).
    for i in $(seq 0 9); do
        ctid=$((base + i))
        if ! lxc_browser_exists "$ctid"; then
            echo "$ctid"
            return 0
        fi
    done
    return 1
}

# Create and set up a fresh browser LXC, then start it.
lxc_browser_create() {
    local ctid="$1"
    local pve_dir
    pve_dir=$(lxc_browser_pve_dir)
    if [ ! -f "$pve_dir/create-lxc.sh" ]; then
        log_error "api/create-lxc.sh not found"
        return 1
    fi
    if [ ! -f "$pve_dir/setup-lxc.sh" ]; then
        log_error "api/setup-lxc.sh not found"
        return 1
    fi
    if ! ( cd "$pve_dir" && CTID="$ctid" ./create-lxc.sh ); then
        log_error "Failed to create browser LXC (CTID ${ctid})"
        return 1
    fi
    if ! ( cd "$pve_dir" && CTID="$ctid" ./setup-lxc.sh ); then
        log_error "Failed to set up browser LXC (CTID ${ctid})"
        return 1
    fi
    lxc_browser_start "$ctid"
}

# Start (or confirm running) a browser LXC and wait until the API is ready.
lxc_browser_start() {
    local ctid="$1"
    local pve_dir
    pve_dir=$(lxc_browser_pve_dir)
    if [ ! -f "$pve_dir/start-browser-lxc.sh" ]; then
        log_error "api/start-browser-lxc.sh not found"
        return 1
    fi
    ( cd "$pve_dir" && CTID="$ctid" ./start-browser-lxc.sh )
}

# Download a single file from URL into dest on the PVE host via the browser
# API, then pull it out of the LXC with pct pull. Returns 1 if the result is an
# HTML page or the download did not complete.
lxc_browser_download() {
    local ctid="$1"
    local url="$2"
    local dest="$3"
    local label="${4:-file}"
    local ip filename tmp
    ip=$(lxc_browser_get_ip "$ctid")
    if [ -z "$ip" ]; then
        log_error "Could not get LXC IP for CTID ${ctid}"
        return 1
    fi
    local api="http://${ip}:${VGPU_LXC_API_PORT}"
    filename=$(basename "${url%%\?*}")

    if ! curl --fail --silent --show-error --get \
        --data-urlencode "url=$url" \
        --connect-timeout 5 --max-time 30 \
        "$api/api/download" >/dev/null 2>&1; then
        log_error "Failed to start browser download via API for ${label}"
        return 1
    fi
    log_info "Browser download started for ${label} (CTID ${ctid}); noVNC: http://${ip}:${VGPU_LXC_NOVNC_PORT}/vnc.html"

    local ready=0 i
    for i in $(seq 1 "$((VGPU_LXC_POLL_TIMEOUT / VGPU_LXC_POLL_INTERVAL))"); do
        if curl --fail --silent --show-error --get \
            --data-urlencode "filename=$filename" \
            --connect-timeout 3 --max-time 10 \
            "$api/api/check" 2>/dev/null | grep -qE '"exists": *true'; then
            ready=1
            break
        fi
        sleep "$VGPU_LXC_POLL_INTERVAL"
    done
    if [ "$ready" -ne 1 ]; then
        log_error "Timed out waiting for browser download of ${label}; check noVNC at http://${ip}:${VGPU_LXC_NOVNC_PORT}/vnc.html"
        return 1
    fi

    mkdir -p "$(dirname "$dest")"
    tmp="${dest}.part"
    if ! pct pull "$ctid" "/home/user/Downloads/${filename}" "$tmp" 2>/dev/null; then
        log_error "pct pull failed for ${label}"
        return 1
    fi
    if host_driver_is_html_raw "$tmp"; then
        rm -f "$tmp"
        log_error "Browser download returned an HTML page for ${label}"
        return 1
    fi
    if ! mv "$tmp" "$dest" 2>/dev/null; then
        rm -f "$tmp"
        log_error "could not finalize ${label}"
        return 1
    fi
    pct exec "$ctid" -- rm -f "/home/user/Downloads/${filename}" 2>/dev/null || true
    return 0
}

# For a real browser, use the alist /d/ (share-page) route rather than the raw
# /p/ proxy route that CrowdSec challenges. Non-alist URLs are left unchanged.
_lxc_browser_to_d_url() {
    local url="$1"
    if [[ "$url" == https://alist.homelabproject.cc/p/* ]]; then
        url="${url/\/p\//\/d\/}"
    fi
    echo "$url"
}

# High-level entry: download URL into dest via the browser LXC. Reuses an
# existing ready browser LXC silently; otherwise asks the user whether to
# create one. Returns 1 if the user declines or the download fails (caller then
# falls back to the manual guidance).
prompt_lxc_browser_download() {
    local url="$1"
    local dest="$2"
    local label="${3:-file}"
    local dl_url="$url"
    local is_zip=0
    local ctid

    # Strip the "|zip" download-marker; the ZIP itself is downloaded.
    if [[ "$url" == *"|zip" ]]; then
        dl_url="${url%|zip}"
        is_zip=1
    fi

    # A real browser uses the alist /d/ route (share page), not the raw /p/.
    dl_url=$(_lxc_browser_to_d_url "$dl_url")

    if ! ctid=$(lxc_browser_find_ctid); then
        log_error "No CTID available for a browser LXC"
        return 1
    fi

    if ! lxc_browser_api_ready "$ctid"; then
        log_error "The alist website is protected by CrowdSec; direct script download may fail."
        log_debug "Alternative: Create a browser-api LXC (CTID ${ctid}) to fetch it via noVNC."
        echo -e "    (LXC setup takes 5-10 mins. Depending on your IP reputation, this will be:\n     - Full-auto: No interaction needed.\n     - Semi-auto: You must open noVNC to pass the human verification.)"
        if ! confirm_action "Proceed with the LXC setup and then download ${label}?"; then
            return 1
        fi
        log_info "Creating browser LXC (CTID ${ctid})..."
        if ! lxc_browser_create "$ctid"; then
            log_error "Failed to create/start browser LXC (CTID ${ctid})"
            return 1
        fi
    fi

    if [ "$is_zip" = "1" ]; then
        # Download the ZIP, then extract the host .run from it.
        if ! lxc_browser_download "$ctid" "$dl_url" "${dest}.part" "$label"; then
            return 1
        fi
        if ! unzip -q -o "${dest}.part" -d "$(dirname "$dest")" 2>/dev/null; then
            rm -f "${dest}.part"
            log_error "Failed to extract ZIP downloaded via browser LXC for ${label}"
            return 1
        fi
        rm -f "${dest}.part"
        local extracted
        extracted=$(find "$(dirname "$dest")" -maxdepth 3 -name "*-vgpu-kvm.run" -type f -print -quit 2>/dev/null)
        if [ -z "$extracted" ]; then
            log_error "No host .run found in downloaded ZIP for ${label}"
            return 1
        fi
        if [ "$(basename "$extracted")" != "$(basename "$dest")" ]; then
            if ! mv "$extracted" "$dest" 2>/dev/null; then
                log_error "could not place extracted run for ${label}"
                return 1
            fi
        fi
        chmod +x "$dest" 2>/dev/null || true
    else
        if ! lxc_browser_download "$ctid" "$dl_url" "$dest" "$label"; then
            return 1
        fi
        chmod +x "$dest" 2>/dev/null || true
    fi
    log_info "Downloaded ${label} to ${dest} via browser LXC (CTID ${ctid})"
    return 0
}
