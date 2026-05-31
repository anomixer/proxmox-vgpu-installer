#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"

# Load library modules (v1.8+)
# Week 1 modules
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    echo "ERROR: Required library lib/common.sh not found"
    exit 1
fi

if [ -f "$SCRIPT_DIR/lib/config.sh" ]; then
    source "$SCRIPT_DIR/lib/config.sh"
else
    echo "ERROR: Required library lib/config.sh not found"
    exit 1
fi

# Week 2 modules (core functionality)
if [ -f "$SCRIPT_DIR/lib/driver-manager.sh" ]; then
    source "$SCRIPT_DIR/lib/driver-manager.sh"
else
    echo "ERROR: Required library lib/driver-manager.sh not found"
    exit 1
fi

if [ -f "$SCRIPT_DIR/lib/kernel-manager.sh" ]; then
    source "$SCRIPT_DIR/lib/kernel-manager.sh"
else
    echo "ERROR: Required library lib/kernel-manager.sh not found"
    exit 1
fi

if [ -f "$SCRIPT_DIR/lib/secure-boot.sh" ]; then
    source "$SCRIPT_DIR/lib/secure-boot.sh"
else
    echo "ERROR: Required library lib/secure-boot.sh not found"
    exit 1
fi

if [ -f "$SCRIPT_DIR/lib/gpu-detect.sh" ]; then
    source "$SCRIPT_DIR/lib/gpu-detect.sh"
else
    echo "ERROR: Required library lib/gpu-detect.sh not found"
    exit 1
fi

# Week 3 modules (advanced functionality)
if [ -f "$SCRIPT_DIR/lib/repo-manager.sh" ]; then
    source "$SCRIPT_DIR/lib/repo-manager.sh"
else
    echo "ERROR: Required library lib/repo-manager.sh not found"
    exit 1
fi

if [ -f "$SCRIPT_DIR/lib/guest-drivers.sh" ]; then
    source "$SCRIPT_DIR/lib/guest-drivers.sh"
else
    echo "ERROR: Required library lib/guest-drivers.sh not found"
    exit 1
fi

if [ -f "$SCRIPT_DIR/lib/guest-drivers-auto.sh" ]; then
    source "$SCRIPT_DIR/lib/guest-drivers-auto.sh"
else
    echo "ERROR: Required library lib/guest-drivers-auto.sh not found"
    exit 1
fi

if [ -f "$SCRIPT_DIR/lib/host-drivers-auto.sh" ]; then
    source "$SCRIPT_DIR/lib/host-drivers-auto.sh"
else
    echo "ERROR: Required library lib/host-drivers-auto.sh not found"
    exit 1
fi

if [ -f "$SCRIPT_DIR/lib/vgpu-unlock.sh" ]; then
    source "$SCRIPT_DIR/lib/vgpu-unlock.sh"
else
    echo "ERROR: Required library lib/vgpu-unlock.sh not found"
    exit 1
fi

if [ -f "$SCRIPT_DIR/lib/fastapi-dls.sh" ]; then
    source "$SCRIPT_DIR/lib/fastapi-dls.sh"
else
    echo "ERROR: Required library lib/fastapi-dls.sh not found"
    exit 1
fi

# Variables
LOG_FILE="$SCRIPT_DIR/debug.log"
DEBUG=false
STEP="${STEP:-1}"
URL="${URL:-}"
FILE="${FILE:-}"
DRIVER_VERSION="${DRIVER_VERSION:-}"
SCRIPT_VERSION=1.8
VGPU_DIR="$SCRIPT_DIR"
VGPU_SUPPORT="${VGPU_SUPPORT:-}"
VGPU_HELPER_STATUS="${VGPU_HELPER_STATUS:-}"
SECURE_BOOT_DIR="$SCRIPT_DIR/secure-boot"
SECURE_BOOT_KEY="$SECURE_BOOT_DIR/module-signing.key"
SECURE_BOOT_CERT="$SECURE_BOOT_DIR/module-signing.crt"
SECURE_BOOT_DER="$SECURE_BOOT_DIR/module-signing.der"
PATCH_MAP_FILE="$SCRIPT_DIR/driver_patches.json"
FASTAPI_WARNING="${FASTAPI_WARNING:-0}"
declare -a DRIVER_ORDER=()
declare -A DRIVER_LABELS=()
declare -A DRIVER_FILES=()
declare -A DRIVER_URLS=()
declare -A DRIVER_MD5=()
declare -A DRIVER_PATCHES=()
declare -A DRIVER_NOTES=()
declare -A DRIVER_BY_FILENAME=()
declare -A PATCH_OVERRIDES=()
declare -A HOST_VERSION_TO_BRANCH=()
declare -A GUEST_LINUX_DRIVERS=()
declare -A GUEST_LINUX_LABELS=()
declare -A GUEST_WINDOWS_DRIVERS=()
declare -A GUEST_WINDOWS_LABELS=()

register_guest_driver() {
    local branch="$1"
    local linux_url="$2"
    local windows_url="$3"
    local linux_label="${4:-}"
    local windows_label="${5:-}"

    branch="${branch//[$'\r\n\t ']/}"
    [ -z "$branch" ] && return

    if [ -n "$linux_url" ]; then
        GUEST_LINUX_DRIVERS["$branch"]="$linux_url"
        if [ -z "$linux_label" ]; then
            linux_label="${linux_url##*/}"
        fi
        GUEST_LINUX_LABELS["$branch"]="$linux_label"
    fi

    if [ -n "$windows_url" ]; then
        GUEST_WINDOWS_DRIVERS["$branch"]="$windows_url"
        if [ -z "$windows_label" ]; then
            windows_label="${windows_url##*/}"
        fi
        GUEST_WINDOWS_LABELS["$branch"]="$windows_label"
    fi
}

load_auto_guest_driver_catalog() {
    while IFS='|' read -r branch linux_url windows_url; do
        [ -z "$branch" ] && continue
        register_guest_driver "$branch" "$linux_url" "$windows_url"
    done <<'CATALOG'
20.1||
20.0|https://alist.homelabproject.cc/d/foxipan/vGPU/20.0/NVIDIA-GRID-Linux-KVM-595.58.02-595.58.03-595.97/Guest_Drivers/NVIDIA-Linux-x86_64-595.58.03-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/20.0/NVIDIA-GRID-Linux-KVM-595.58.02-595.58.03-595.97/Guest_Drivers/595.97_grid_win10_win11_server2022_server_2025_dch_64bit_international.exe
19.5|https://alist.homelabproject.cc/d/foxipan/vGPU/19.5/NVIDIA-GRID-Linux-KVM-580.159.01-580.159.03-582.53/Guest_Drivers/NVIDIA-Linux-x86_64-580.159.03-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/19.5/NVIDIA-GRID-Linux-KVM-580.159.01-580.159.03-582.53/Guest_Drivers/582.53_grid_win10_win11_server2022_server_2025_dch_64bit_international.exe
19.4|https://alist.homelabproject.cc/d/foxipan/vGPU/19.4/NVIDIA-GRID-Linux-KVM-580.126.08-580.126.09-582.16/Guest_Drivers/NVIDIA-Linux-x86_64-580.126.09-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/19.4/NVIDIA-GRID-Linux-KVM-580.126.08-580.126.09-582.16/Guest_Drivers/582.16_grid_win10_win11_server2022_server2025_dch_64bit_international.exe
19.3|https://alist.homelabproject.cc/d/foxipan/vGPU/19.3/NVIDIA-GRID-Linux-KVM-580.105.06-580.105.08-581.80/Guest_Drivers/NVIDIA-Linux-x86_64-580.105.08-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/19.3/NVIDIA-GRID-Linux-KVM-580.105.06-580.105.08-581.80/Guest_Drivers/581.80_grid_win10_win11_server2022_server2025_dch_64bit_international.exe
19.2|https://alist.homelabproject.cc/d/foxipan/vGPU/19.2/NVIDIA-GRID-Linux-KVM-580.95.02-580.95.05-581.42/Guest_Drivers/NVIDIA-Linux-x86_64-580.95.05-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/19.2/NVIDIA-GRID-Linux-KVM-580.95.02-580.95.05-581.42/Guest_Drivers/581.42_grid_win10_win11_server2019_server2022_server2025_dch_64bit_international.exe
19.1|https://alist.homelabproject.cc/d/foxipan/vGPU/19.1/NVIDIA-GRID-Linux-KVM-580.82.02-580.82.07-581.15/Guest_Drivers/NVIDIA-Linux-x86_64-580.82.07-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/19.1/NVIDIA-GRID-Linux-KVM-580.82.02-580.82.07-581.15/Guest_Drivers/581.15_grid_win10_win11_server2022_dch_64bit_international.exe
19.0|https://alist.homelabproject.cc/d/foxipan/vGPU/19.0/NVIDIA-GRID-Linux-KVM-580.65.05-580.65.06-580.88/Guest_Drivers/NVIDIA-Linux-x86_64-580.65.06-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/19.0/NVIDIA-GRID-Linux-KVM-580.65.05-580.65.06-580.88/Guest_Drivers/580.88_grid_win10_win11_server2022_dch_64bit_international.exe
18.4|https://alist.homelabproject.cc/d/foxipan/vGPU/18.4/NVIDIA-GRID-Linux-KVM-570.172.07-570.172.08-573.48/Guest_Drivers/NVIDIA-Linux-x86_64-570.172.08-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/18.4/NVIDIA-GRID-Linux-KVM-570.172.07-570.172.08-573.48/Guest_Drivers/573.48_grid_win10_win11_server2022_dch_64bit_international.exe
18.3|https://alist.homelabproject.cc/d/foxipan/vGPU/18.3/NVIDIA-GRID-Linux-KVM-570.158.02-570.158.01-573.39/Guest_Drivers/NVIDIA-Linux-x86_64-570.158.01-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/18.3/NVIDIA-GRID-Linux-KVM-570.158.02-570.158.01-573.39/Guest_Drivers/573.39_grid_win10_win11_server2022_dch_64bit_international.exe
18.2|https://alist.homelabproject.cc/d/foxipan/vGPU/18.2/NVIDIA-GRID-Linux-KVM-570.148.06-570.148.08-573.07/Guest_Drivers/NVIDIA-Linux-x86_64-570.148.08-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/18.2/NVIDIA-GRID-Linux-KVM-570.148.06-570.148.08-573.07/Guest_Drivers/573.07_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
18.1||
18.0||
17.6|https://alist.homelabproject.cc/d/foxipan/vGPU/17.6/NVIDIA-GRID-Linux-KVM-550.163.02-550.163.01-553.74/Guest_Drivers/NVIDIA-Linux-x86_64-550.163.01-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/17.6/NVIDIA-GRID-Linux-KVM-550.163.02-550.163.01-553.74/Guest_Drivers/553.74_grid_win10_win11_server2022_dch_64bit_international.exe
17.5||https://alist.homelabproject.cc/d/foxipan/vGPU/17.5/NVIDIA-GRID-Linux-KVM-550.144.02-550.144.03-553.62/Guest_Drivers/553.62_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
17.4||
17.3||
17.2|https://alist.homelabproject.cc/d/foxipan/vGPU/17.2/NVIDIA-GRID-Linux-KVM-550.90.05-550.90.07-552.55/Guest_Drivers/NVIDIA-Linux-x86_64-550.90.07-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/17.2/NVIDIA-GRID-Linux-KVM-550.90.05-550.90.07-552.55/Guest_Drivers/552.55_grid_win10_win11_server2022_dch_64bit_international.exe
17.1||
17.0||
16.14|https://alist.homelabproject.cc/d/foxipan/vGPU/16.14/NVIDIA-GRID-Linux-KVM-535.309.01-539.72/Guest_Drivers/NVIDIA-Linux-x86_64-535.309.01-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.14/NVIDIA-GRID-Linux-KVM-535.309.01-539.72/Guest_Drivers/539.72_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.13||
16.12||
16.11|https://alist.homelabproject.cc/d/foxipan/vGPU/16.11/NVIDIA-GRID-Linux-KVM-535.261.04-535.261.03-539.41/Guest_Drivers/NVIDIA-Linux-x86_64-535.261.03-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.11/NVIDIA-GRID-Linux-KVM-535.261.04-535.261.03-539.41/Guest_Drivers/539.41_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.10|https://alist.homelabproject.cc/d/foxipan/vGPU/16.10/NVIDIA-GRID-Linux-KVM-535.247.02-535.247.01-539.28/Guest_Drivers/NVIDIA-Linux-x86_64-535.247.01-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.10/NVIDIA-GRID-Linux-KVM-535.247.02-535.247.01-539.28/Guest_Drivers/539.28_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.9|https://alist.homelabproject.cc/d/foxipan/vGPU/16.9/NVIDIA-GRID-Linux-KVM-535.230.02-539.19/Guest_Drivers/NVIDIA-Linux-x86_64-535.230.02-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.9/NVIDIA-GRID-Linux-KVM-535.230.02-539.19/Guest_Drivers/539.19_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.8|https://alist.homelabproject.cc/d/foxipan/vGPU/16.8/NVIDIA-GRID-Linux-KVM-535.216.01-538.95/Guest_Drivers/NVIDIA-Linux-x86_64-535.216.01-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.8/NVIDIA-GRID-Linux-KVM-535.216.01-538.95/Guest_Drivers/538.95_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.7|https://alist.homelabproject.cc/d/foxipan/vGPU/16.7/NVIDIA-GRID-Linux-KVM-535.183.04-535.183.06-538.78/Guest_Drivers/NVIDIA-Linux-x86_64-535.183.06-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.7/NVIDIA-GRID-Linux-KVM-535.183.04-535.183.06-538.78/Guest_Drivers/538.78_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.6|https://alist.homelabproject.cc/d/foxipan/vGPU/16.6/NVIDIA-GRID-Linux-KVM-535.183.04-535.183.01-538.67/Guest_Drivers/NVIDIA-Linux-x86_64-535.183.01-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.6/NVIDIA-GRID-Linux-KVM-535.183.04-535.183.01-538.67/Guest_Drivers/538.67_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.5|https://alist.homelabproject.cc/d/foxipan/vGPU/16.5/NVIDIA-GRID-Linux-KVM-535.161.05-535.161.08-538.46/Guest_Drivers/NVIDIA-Linux-x86_64-535.161.08-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.5/NVIDIA-GRID-Linux-KVM-535.161.05-535.161.08-538.46/Guest_Drivers/538.46_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.4|https://alist.homelabproject.cc/d/foxipan/vGPU/16.4/NVIDIA-GRID-Linux-KVM-535.161.05-535.161.07-538.33/Guest_Drivers/NVIDIA-Linux-x86_64-535.161.07-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.4/NVIDIA-GRID-Linux-KVM-535.161.05-535.161.07-538.33/Guest_Drivers/538.33_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.3|https://alist.homelabproject.cc/d/foxipan/vGPU/16.3/NVIDIA-GRID-Linux-KVM-535.154.02-535.154.05-538.15/Guest_Drivers/NVIDIA-Linux-x86_64-535.154.05-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.3/NVIDIA-GRID-Linux-KVM-535.154.02-535.154.05-538.15/Guest_Drivers/538.15_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.2|https://alist.homelabproject.cc/d/foxipan/vGPU/16.2/NVIDIA-GRID-Linux-KVM-535.129.03-537.70/Guest_Drivers/NVIDIA-Linux-x86_64-535.129.03-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.2/NVIDIA-GRID-Linux-KVM-535.129.03-537.70/Guest_Drivers/537.70_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.1|https://alist.homelabproject.cc/d/foxipan/vGPU/16.1/NVIDIA-GRID-Linux-KVM-535.104.06-535.104.05-537.13/Guest_Drivers/NVIDIA-Linux-x86_64-535.104.05-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.1/NVIDIA-GRID-Linux-KVM-535.104.06-535.104.05-537.13/Guest_Drivers/537.13_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
16.0|https://alist.homelabproject.cc/d/foxipan/vGPU/16.0/NVIDIA-GRID-Linux-KVM-535.54.06-535.54.03-536.25/Guest_Drivers/NVIDIA-Linux-x86_64-535.54.03-grid.run|https://alist.homelabproject.cc/d/foxipan/vGPU/16.0/NVIDIA-GRID-Linux-KVM-535.54.06-535.54.03-536.25/Guest_Drivers/536.25_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
CATALOG
}

load_auto_guest_driver_catalog

snapshot_run_artifacts() {
    find . -maxdepth 1 -type f -name 'NVIDIA-Linux-x86_64-*-vgpu-kvm*.run' -printf '%f\n' 2>/dev/null | LC_ALL=C sort
}

select_new_run_artifact() {
    local pre_snapshot="$1"
    local post_snapshot="$2"
    local driver_filename="$3"

    declare -A seen_pre=()
    while IFS= read -r run_file; do
        if [ -n "$run_file" ]; then
            seen_pre["$run_file"]=1
        fi
    done <<<"$pre_snapshot"

    while IFS= read -r run_file; do
        if [ -z "$run_file" ] || [ "$run_file" = "$driver_filename" ]; then
            continue
        fi
        if [ -z "${seen_pre[$run_file]:-}" ]; then
            printf '%s\n' "$run_file"
            return 0
        fi
    done <<<"$post_snapshot"

    return 1
}

strip_trailing_carriage_return() {
    local value="$1"
    while [[ "$value" == *$'\r' ]]; do
        value="${value%$'\r'}"
    done
    printf '%s' "$value"
}

extract_host_version_from_filename() {
    local filename="$1"
    local base
    base=$(basename "$filename")
    if [[ "$base" =~ NVIDIA-Linux-x86_64-([0-9]+\.[0-9]+\.[0-9]+)-vgpu-kvm ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

resolve_guest_driver_links() {
    local branch="$1"
    local host_version="$2"

    branch="${branch//[$'\r\n\t ']/}"
    host_version="${host_version//[$'\r\n\t ']/}"

    local resolved_branch=""

    if [ -n "$branch" ]; then
        if [ -n "${GUEST_LINUX_DRIVERS[$branch]:-}" ] || [ -n "${GUEST_WINDOWS_DRIVERS[$branch]:-}" ]; then
            resolved_branch="$branch"
        fi
    fi

    if [ -z "$resolved_branch" ] && [ -n "$host_version" ]; then
        local mapped_branch="${HOST_VERSION_TO_BRANCH[$host_version]:-}"
        if [ -n "$mapped_branch" ]; then
            if [ -n "${GUEST_LINUX_DRIVERS[$mapped_branch]:-}" ] || [ -n "${GUEST_WINDOWS_DRIVERS[$mapped_branch]:-}" ]; then
                resolved_branch="$mapped_branch"
            fi
        fi
    fi

    if [ -z "$resolved_branch" ]; then
        echo "error=No guest driver catalog entry for branch ${branch:-$host_version}"
        return 0
    fi

    local linux_url="${GUEST_LINUX_DRIVERS[$resolved_branch]:-}"
    local linux_label="${GUEST_LINUX_LABELS[$resolved_branch]:-}"
    local windows_url="${GUEST_WINDOWS_DRIVERS[$resolved_branch]:-}"
    local windows_label="${GUEST_WINDOWS_LABELS[$resolved_branch]:-}"

    if [ -n "$linux_url" ]; then
        echo "linux=$linux_url"
        [ -n "$linux_label" ] && echo "linux_label=$linux_label"
    fi

    if [ -n "$windows_url" ]; then
        echo "windows=$windows_url"
        [ -n "$windows_label" ] && echo "windows_label=$windows_label"
    fi
}

download_guest_driver_asset() {
    local url="$1"
    local dest_dir="$2"
    local display_name="$3"

    if [ -z "$url" ]; then
        return 1
    fi

    mkdir -p "$dest_dir"

    local filename="${url##*/}"
    filename="${filename%%\?*}"
    if [ -z "$filename" ]; then
        filename=$(echo "${display_name:-guest-driver}" | tr ' /' '__')
    fi

    local target="$dest_dir/$filename"

    # Check if file already exists
    if [ -f "$target" ]; then
        echo -e "${GREEN}[+]${NC} File already exists at $target, skipping download"
        return 0
    fi

    echo -e "${GREEN}[+]${NC} Downloading ${display_name:-guest driver}"

    if command -v wget >/dev/null 2>&1; then
        if wget -O "$target" "$url"; then
            echo -e "${GREEN}[+]${NC} Saved to $target"
            return 0
        fi
    elif command -v curl >/dev/null 2>&1; then
        if curl -fSL "$url" -o "$target"; then
            echo -e "${GREEN}[+]${NC} Saved to $target"
            return 0
        fi
    else
        echo -e "${RED}[!]${NC} Neither curl nor wget is available to download guest drivers."
        return 1
    fi

    echo -e "${RED}[!]${NC} Failed to download ${display_name:-guest driver} from $url"
    rm -f "$target"
    return 1
}

prompt_guest_driver_downloads() {
    local branch="$1"
    local driver_filename="$2"

    local host_version=""
    if ! host_version=$(extract_host_version_from_filename "$driver_filename" 2>/dev/null); then
        echo -e "${YELLOW}[-]${NC} Unable to derive host driver version from $driver_filename for guest driver lookup."
        host_version=""
    fi

    local lookup_output
    lookup_output=$(resolve_guest_driver_links "$branch" "$host_version" || true)

    if [ -z "${lookup_output}" ]; then
        echo -e "${YELLOW}[-]${NC} Unable to locate guest driver downloads for branch ${branch:-$host_version}."
        return
    fi

    local linux_url=""
    local linux_label=""
    local windows_url=""
    local windows_label=""
    local error_message=""

    while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        case "$key" in
            linux)
                linux_url="$value"
                ;;
            linux_label)
                linux_label="$value"
                ;;
            windows)
                windows_url="$value"
                ;;
            windows_label)
                windows_label="$value"
                ;;
            error)
                error_message="$value"
                ;;
        esac
    done <<<"$lookup_output"

    if [ -n "$error_message" ]; then
        echo -e "${YELLOW}[-]${NC} $error_message"
        return
    fi

    if [ -z "$linux_url" ] && [ -z "$windows_url" ]; then
        echo -e "${YELLOW}[-]${NC} No guest driver download links were published for branch ${branch:-$host_version}."
        return
    fi

    linux_url=$(strip_trailing_carriage_return "$linux_url")
    linux_label=$(strip_trailing_carriage_return "$linux_label")
    windows_url=$(strip_trailing_carriage_return "$windows_url")
    windows_label=$(strip_trailing_carriage_return "$windows_label")

    local branch_token="${branch:-${host_version:-guest}}"
    branch_token="${branch_token//[^0-9A-Za-z._-]/_}"
    local version_token="${host_version//[^0-9A-Za-z._-]/_}"
    local download_dir="$SCRIPT_DIR/guest-drivers/$branch_token"
    if [ -n "$version_token" ] && [ "$version_token" != "$branch_token" ]; then
        download_dir="$SCRIPT_DIR/guest-drivers/${branch_token}_${version_token}"
    fi

    if [ -n "$linux_url" ]; then
        local linux_choice
        read -r -p "$(echo -e "${BLUE}[?]${NC} Download Linux guest drivers now? (y/n): ")" linux_choice || linux_choice=""
        linux_choice=$(strip_trailing_carriage_return "$linux_choice")
        if [[ "$linux_choice" =~ ^[Yy]$ ]]; then
            download_guest_driver_asset "$linux_url" "$download_dir" "${linux_label:-Linux guest driver}" || true
        else
            echo -e "${YELLOW}[-]${NC} Skipping Linux guest driver download."
        fi
    fi

    if [ -n "$windows_url" ]; then
        local windows_choice
        read -r -p "$(echo -e "${BLUE}[?]${NC} Download Windows guest drivers now? (y/n): ")" windows_choice || windows_choice=""
        windows_choice=$(strip_trailing_carriage_return "$windows_choice")
        if [[ "$windows_choice" =~ ^[Yy]$ ]]; then
            download_guest_driver_asset "$windows_url" "$download_dir" "${windows_label:-Windows guest driver}" || true
        else
            echo -e "${YELLOW}[-]${NC} Skipping Windows guest driver download."
        fi
    else
        echo -e "${YELLOW}[-]${NC} No Windows guest driver download link was published for branch ${branch:-$host_version}."
    fi
}

download_guest_drivers_interactive() {
    echo ""
    echo "Download guest drivers"
    echo ""

    if ! select_driver_branch false; then
        return 1
    fi

    if [ -z "$driver_filename" ]; then
        echo -e "${YELLOW}[-]${NC} Unable to determine host driver filename for the selected branch."
        return 1
    fi

    prompt_guest_driver_downloads "$driver_version" "$driver_filename"
}

load_patch_overrides() {
    if [ ! -f "$PATCH_MAP_FILE" ]; then
        return
    fi

    if command -v jq >/dev/null 2>&1; then
        while IFS='=' read -r key value; do
            PATCH_OVERRIDES["$key"]="$value"
        done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$PATCH_MAP_FILE" 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        while IFS='=' read -r key value; do
            PATCH_OVERRIDES["$key"]="$value"
        done < <(PATCH_MAP_FILE="$PATCH_MAP_FILE" python3 - <<'PY'
import json
import os
path = os.environ.get("PATCH_MAP_FILE")
if not path:
    raise SystemExit
with open(path, "r") as fh:
    data = json.load(fh)
for key, value in data.items():
    if value is None:
        continue
    print(f"{key}={value}")
PY
)
    fi
}

load_patch_overrides

version_ge() {
    dpkg --compare-versions "$1" ge "$2"
}

version_gt() {
    dpkg --compare-versions "$1" gt "$2"
}

# Function to check if kernel version is 6.17 or higher
is_kernel_617_or_higher() {
    local current_kernel
    current_kernel=$(uname -r | sed 's/-pve.*//')
    version_ge "$current_kernel" "6.17"
}

sync_fastapi_flag() {
    if [ -n "${driver_version:-}" ] && version_ge "$driver_version" "18.0"; then
        FASTAPI_WARNING=1
    else
        FASTAPI_WARNING=0
    fi
    set_config_value "FASTAPI_WARNING" "$FASTAPI_WARNING"
}

ensure_patch_compat() {
    local desired_version="2.7.6"
    local system_patch
    system_patch=$(command -v patch || true)

    if [ -z "$system_patch" ]; then
        run_command "Installing patch utility" "info" "apt install -y patch"
        system_patch=$(command -v patch || true)
    fi

    if [ -z "$system_patch" ]; then
        echo -e "${RED}[!]${NC} Unable to locate the 'patch' binary even after installation."
        exit 1
    fi

    local current_version
    current_version=$("$system_patch" --version | head -n1 | awk '{print $3}')
    if ! version_gt "$current_version" "$desired_version"; then
        return
    fi

    if [ -x /usr/local/bin/patch ]; then
        local local_version
        local_version=$(/usr/local/bin/patch --version | head -n1 | awk '{print $3}')
        if ! version_gt "$local_version" "$desired_version"; then
            export PATH="/usr/local/bin:$PATH"
            return
        fi
    fi

    echo -e "${YELLOW}[-]${NC} Installing GNU patch ${desired_version} for compatibility."
    local build_dir
    build_dir=$(mktemp -d)
    pushd "$build_dir" > /dev/null
    run_command "Downloading patch ${desired_version}" "info" "wget -q https://ftp.gnu.org/gnu/patch/patch-${desired_version}.tar.gz"
    run_command "Extracting patch ${desired_version}" "info" "tar xf patch-${desired_version}.tar.gz"
    cd "patch-${desired_version}"
    run_command "Configuring patch ${desired_version}" "info" "./configure --quiet"
    run_command "Building patch ${desired_version}" "info" "make -s"
    run_command "Installing patch ${desired_version}" "info" "make install"
    popd > /dev/null
    rm -rf "$build_dir"
    export PATH="/usr/local/bin:$PATH"
}

# Function to download driver file with error handling
download_driver_file() {
    local driver_url="$1"
    local driver_filename="$2"

    # Check if file already exists
    if [ -f "$driver_filename" ]; then
        echo -e "${GREEN}[+]${NC} Driver file already exists, skipping download"
        return 0
    fi

    if [[ "$driver_url" == https://mega.nz/* ]]; then
        if ! command -v megadl >/dev/null 2>&1; then
            echo -e "${RED}[!]${NC} megadl is required to download from Mega.nz. Install megatools or provide an alternate URL."
            exit 1
        fi

        if ! megadl "$driver_url"; then
            echo -e "${RED}[!]${NC} Download failed."
            exit 1
        fi
    else
        if command -v wget >/dev/null 2>&1; then
            if ! wget -O "$driver_filename" "$driver_url"; then
                echo -e "${RED}[!]${NC} Download failed."
                exit 1
            fi
        elif command -v curl >/dev/null 2>&1; then
            if ! curl -fSL "$driver_url" -o "$driver_filename"; then
                echo -e "${RED}[!]${NC} Download failed."
                exit 1
            fi
        else
            echo -e "${RED}[!]${NC} Neither curl nor wget is available for downloading."
            exit 1
        fi
    fi
}

register_driver() {
    local branch="$1"
    local label="$2"
    local filename="$3"
    local url="$4"
    local md5="$5"
    local patch="$6"
    local note="${7:-}"

    if [ -z "$patch" ]; then
        if [ -n "${PATCH_OVERRIDES[$branch]:-}" ]; then
            patch="${PATCH_OVERRIDES[$branch]}"
        elif [ -n "${PATCH_OVERRIDES[$filename]:-}" ]; then
            patch="${PATCH_OVERRIDES[$filename]}"
        fi
    fi

    DRIVER_ORDER+=("$branch")
    DRIVER_LABELS["$branch"]="$label"
    DRIVER_FILES["$branch"]="$filename"
    DRIVER_URLS["$branch"]="$url"
    DRIVER_MD5["$branch"]="$md5"
    DRIVER_PATCHES["$branch"]="$patch"
    DRIVER_NOTES["$branch"]="$note"

    if [ -n "$filename" ] && [ -z "${DRIVER_BY_FILENAME[$filename]:-}" ]; then
        DRIVER_BY_FILENAME["$filename"]="$branch"
    fi

    if [ -n "$filename" ]; then
        local host_version_lookup=""
        if host_version_lookup=$(extract_host_version_from_filename "$filename" 2>/dev/null); then
            if [ -z "${HOST_VERSION_TO_BRANCH[$host_version_lookup]:-}" ]; then
                HOST_VERSION_TO_BRANCH["$host_version_lookup"]="$branch"
            fi
        fi
    fi
}

# Driver registry — host URL "auto" = discover on alist.homelabproject.cc (lib/host-drivers-auto.sh)
register_driver "20.1" "20.1 (595.71.03)" "NVIDIA-Linux-x86_64-595.71.03-vgpu-kvm.run" "auto" "" "" "Native GPUs only (Kernel 7.x support)"
register_driver "20.0" "20.0 (595.58.02)" "NVIDIA-Linux-x86_64-595.58.02-vgpu-kvm.run" "auto" "" "" "Native GPUs only (Kernel 7.x support)"
register_driver "19.5" "19.5 (580.159.01)" "NVIDIA-Linux-x86_64-580.159.01-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "19.4" "19.4 (580.126.08)" "NVIDIA-Linux-x86_64-580.126.08-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "19.3" "19.3 (580.105.06)" "NVIDIA-Linux-x86_64-580.150.06-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "19.2" "19.2 (580.95.02)" "NVIDIA-Linux-x86_64-580.95.02-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "19.1" "19.1 (580.82.02)" "NVIDIA-Linux-x86_64-580.82.02-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "19.0" "19.0 (580.65.05)" "NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "18.4" "18.4 (570.172.07)" "NVIDIA-Linux-x86_64-570.172.07-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "18.3" "18.3 (570.158.02)" "NVIDIA-Linux-x86_64-570.158.02-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "18.2" "18.2 (570.148.06)" "NVIDIA-Linux-x86_64-570.148.06-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "18.1" "18.1 (570.133.10)" "NVIDIA-Linux-x86_64-570.133.10-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "18.0" "18.0 (570.124.03)" "NVIDIA-Linux-x86_64-570.124.03-vgpu-kvm.run" "auto" "" "" "Native GPUs only"
register_driver "17.6" "17.6 (550.163.02)" "NVIDIA-Linux-x86_64-550.163.02-vgpu-kvm.run" "auto" "" "" "Turing GPUs"
register_driver "17.5" "17.5 (550.144.02)" "NVIDIA-Linux-x86_64-550.144.02-vgpu-kvm.run" "auto" "" "" "Turing GPUs"
register_driver "17.4" "17.4 (550.127.06)" "NVIDIA-Linux-x86_64-550.127.06-vgpu-kvm.run" "auto" "" "" "Turing GPUs"
register_driver "17.3" "17.3 (550.90.05)" "NVIDIA-Linux-x86_64-550.90.05-vgpu-kvm.run" "auto" "" "" "Turing GPUs"
register_driver "17.1" "17.1 (550.54.16)" "NVIDIA-Linux-x86_64-550.54.16-vgpu-kvm.run" "auto" "" "" "Turing GPUs"
register_driver "17.0" "17.0 (550.54.10)" "NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" "auto" "" "" "Turing GPUs"
register_driver "16.14" "16.14 (535.309.01)" "NVIDIA-Linux-x86_64-535.309.01-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.13" "16.13 (535.288.01)" "NVIDIA-Linux-x86_64-535.288.01-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.12" "16.12 (535.274.03)" "NVIDIA-Linux-x86_64-535.274.03-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.11" "16.11 (535.261.03)" "NVIDIA-Linux-x86_64-535.261.03-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.10" "16.10 (535.247.01)" "NVIDIA-Linux-x86_64-535.247.01-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.9" "16.9 (535.230.02)" "NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.8" "16.8 (535.216.01)" "NVIDIA-Linux-x86_64-535.216.01-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.7" "16.7 (535.183.04)" "NVIDIA-Linux-x86_64-535.183.04-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.5" "16.5 (535.161.05)" "NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.4" "16.4 (535.161.05)" "NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.3" "16.3 (535.154.02)" "NVIDIA-Linux-x86_64-535.154.02-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.2" "16.2 (535.129.03)" "NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.1" "16.1 (535.104.06)" "NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"
register_driver "16.0" "16.0 (535.54.06)" "NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" "auto" "" "" "Pascal or older GPUs"

# Config helpers
ensure_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        : > "$CONFIG_FILE"
    fi
}

set_config_value() {
    local key="$1"
    local value="$2"

    ensure_config_file

    local tmp
    tmp=$(mktemp)
    if [ -s "$CONFIG_FILE" ]; then
        # grep exits with status 1 when no lines are selected. This is an
        # expected condition when the key is the only entry in the config
        # file, so ignore the non-zero status to keep set -e from aborting
        # the script prematurely.
        grep -v "^${key}=" "$CONFIG_FILE" > "$tmp" || true
    else
        : > "$tmp"
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$CONFIG_FILE"
}

remove_config_key() {
    local key="$1"

    if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then
        local tmp
        tmp=$(mktemp)
        # As above, allow grep to exit with status 1 when the key is absent
        # or the last remaining entry so that we can safely rewrite the
        # config file under set -e.
        grep -v "^${key}=" "$CONFIG_FILE" > "$tmp" || true
        mv "$tmp" "$CONFIG_FILE"
    fi
}

detect_primary_ip() {
    local host_ip=""

    if command -v hostname >/dev/null 2>&1; then
        host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        if [ -z "$host_ip" ]; then
            host_ip=$(hostname -i 2>/dev/null | awk '{print $1}')
        fi
    fi

    if [ -z "$host_ip" ] && command -v ip >/dev/null 2>&1; then
        host_ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | head -n1)
        host_ip=${host_ip%%/*}
    fi

    echo "$host_ip"
}



ensure_kernel_headers() {
    local kernel_release
    kernel_release=$(uname -r)

    if dpkg -s "pve-headers-$kernel_release" >/dev/null 2>&1; then
        echo -e "${GREEN}[+]${NC} Kernel headers already installed for $kernel_release"
        return
    fi

    if dpkg -s "linux-headers-$kernel_release" >/dev/null 2>&1; then
        echo -e "${GREEN}[+]${NC} Linux headers already installed for $kernel_release"
        return
    fi

    echo -e "${GREEN}[+]${NC} Installing headers for kernel $kernel_release"
    if ! run_command "Installing pve-headers-$kernel_release" "info" "apt install -y pve-headers-$kernel_release"; then
        echo -e "${YELLOW}[-]${NC} Falling back to linux-headers-$kernel_release"
        run_command "Installing linux-headers-$kernel_release" "info" "apt install -y linux-headers-$kernel_release"
    fi
}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
ORANGE='\033[0;33m'
PURPLE='\033[0;35m'
GRAY='\033[0;37m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No color

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

SECURE_BOOT_PENDING="${SECURE_BOOT_PENDING:-0}"
SECURE_BOOT_READY="${SECURE_BOOT_READY:-0}"

# Helper function to check if DRIVER_VERSION contains a specific version
contains_version() {
    local version="$1"
    if [[ "$DRIVER_VERSION" == *"$version"* ]]; then
        return 0
    else
        return 1
    fi
}

# Helper function to compare kernel versions
kernel_version_compare() {
    ver1=$1
    ver2=$2
    printf '%s\n' "$ver1" "$ver2" | sort -V -r | head -n 1
}

# Helper function to query GPU information from database
query_gpu_info() {
    local gpu_device_id="$1"
    local query_result=$(sqlite3 gpu_info.db "SELECT * FROM gpu_info WHERE deviceid='$gpu_device_id';")
    echo "$query_result"
}

# Helper function to update GRUB configuration
update_grub() {
    # Checking CPU architecture
    echo -e "${GREEN}[+]${NC} Checking CPU architecture"
    vendor_id=$(cat /proc/cpuinfo | grep vendor_id | awk 'NR==1{print $3}')

    if [ "$vendor_id" = "AuthenticAMD" ]; then
        echo -e "${GREEN}[+]${NC} Your CPU vendor id: ${YELLOW}${vendor_id}"
        # Check if the required options are already present in GRUB_CMDLINE_LINUX_DEFAULT
        if grep -q "amd_iommu=on iommu=pt" /etc/default/grub; then
            echo -e "${YELLOW}[-]${NC} AMD IOMMU options are already set in GRUB_CMDLINE_LINUX_DEFAULT"
        else
            sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/"$/ amd_iommu=on iommu=pt"/' /etc/default/grub
            echo -e "${GREEN}[+]${NC} AMD IOMMU options added to GRUB_CMDLINE_LINUX_DEFAULT"
        fi
    elif [ "$vendor_id" = "GenuineIntel" ]; then
        echo -e "${GREEN}[+]${NC} Your CPU vendor id: ${YELLOW}${vendor_id}${NC}"
        # Check if the required options are already present in GRUB_CMDLINE_LINUX_DEFAULT
        if grep -q "intel_iommu=on iommu=pt" /etc/default/grub; then
            echo -e "${YELLOW}[-]${NC} Intel IOMMU options are already set in GRUB_CMDLINE_LINUX_DEFAULT"
        else
            sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/"$/ intel_iommu=on iommu=pt"/' /etc/default/grub
            echo -e "${GREEN}[+]${NC} Intel IOMMU options added to GRUB_CMDLINE_LINUX_DEFAULT"
        fi
    else
        echo -e "${RED}[!]${NC} Unknown CPU architecture. Unable to configure GRUB"
        exit 1
    fi           
    # Update GRUB
    #echo "updating grub"
    run_command "Updating GRUB" "info" "update-grub"
}

# Helper function to prompt for user confirmation
confirm_action() {
    local message="$1"
    echo -en "${GREEN}[?]${NC} $message (y/n): "
    read confirmation
    if [ "$confirmation" = "y" ] || [ "$confirmation" = "Y" ]; then
        return 0  # Return success
    else
        return 1  # Return failure
    fi
}

# Function to display usage information
display_usage() {
    echo -e "Usage: $0 [--debug] [--step <step_number>] [--url <url>] [--file <file>]"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            DEBUG=true
            shift
            ;;
        --step)
            STEP="$2"
            set_config_value "STEP" "$STEP"
            shift 2
            ;;
        --url)
            URL="$2"
            set_config_value "URL" "$URL"
            shift 2
            ;;
        --file)
            FILE="$2"
            set_config_value "FILE" "$FILE"
            shift 2
            ;;
        *)
            # Unknown option
            display_usage
            ;;
    esac
done

# Function to run a command with specified description and log level
run_command() {
    local description="$1"
    local log_level="$2"
    local command="$3"

    case "$log_level" in
        "info")
            echo -e "${GREEN}[+]${NC} ${description}"
            ;;
        "notification")
            echo -e "${YELLOW}[-]${NC} ${description}"
            ;;
        "error")
            echo -e "${RED}[!]${NC} ${description}"
            ;;
        *)
            echo -e "[?] ${description}"
            ;;
    esac

    if [ "$DEBUG" != "true" ]; then
        if ! eval "$command" > /dev/null 2>> "$LOG_FILE"; then
            echo -e "${RED}[!]${NC} Command failed: $description (see $LOG_FILE)" >&2
            return 1
        fi
    else
        if ! eval "$command"; then
            echo -e "${RED}[!]${NC} Command failed: $description" >&2
            return 1
        fi
    fi
}

# Check Proxmox version
pve_info=$(pveversion)
version=$(echo "$pve_info" | sed -n 's/^pve-manager\/\([0-9.]*\).*$/\1/p')
#version=7.4-15
#version=8.1.4
kernel=$(echo "$pve_info" | sed -n 's/^.*kernel: \([0-9.-]*pve\).*$/\1/p')
major_version=$(echo "$version" | sed 's/\([0-9]*\).*/\1/')

# Function to map filename to driver version and patch
map_filename_to_version() {
    local filename="$1"
    local branch="${DRIVER_BY_FILENAME[$filename]:-}"

    if [ -n "${driver_version:-}" ]; then
        branch="${branch:-$driver_version}"
        if [ "$branch" != "$driver_version" ]; then
            branch="$driver_version"
        fi
    fi

    if [ -z "$branch" ]; then
        branch="$driver_version"
    fi

    if [ -z "$branch" ]; then
        return 1
    fi

    # Check patch availability for VGPU_SUPPORT = Yes cards
    if [ "${VGPU_SUPPORT:-}" = "Yes" ] && [ -z "${DRIVER_PATCHES[$branch]:-}" ]; then
        log_error "Driver version ${branch} requires a vGPU unlock patch, but no patch is available."
        return 1
    fi

    driver_version="$branch"
    driver_patch="${DRIVER_PATCHES[$branch]}"
    md5="${DRIVER_MD5[$branch]}"
    driver_filename="${DRIVER_FILES[$branch]}"
    return 0
}

select_driver_branch() {
    local require_downloadable="${1:-false}"
    local index=1
    declare -A selection_map=()

    echo ""
    echo "Select vGPU driver version:"
    echo ""

    for branch in "${DRIVER_ORDER[@]}"; do
        # If the card requires vGPU unlock patch (Yes), skip drivers that do not have patches
        if [ "${VGPU_SUPPORT:-}" = "Yes" ] && [ -z "${DRIVER_PATCHES[$branch]:-}" ]; then
            continue
        fi

        local url="${DRIVER_URLS[$branch]}"
        if [ "$require_downloadable" = "true" ] && [ -z "$url" ]; then
            continue
        fi

        local label="${DRIVER_LABELS[$branch]}"
        local note="${DRIVER_NOTES[$branch]}"
        
        # Remove "(Select this for most situations.)" notes
        note="${note// (Select this for most situations.)/}"
        note="${note//(Select this for most situations.)/}"

        local patch_info=""
        if [ -n "${DRIVER_PATCHES[$branch]:-}" ]; then
            patch_info=" (vGPU_Patchable)"
            # Remove "Native GPUs only" since it is patchable
            note="${note//Native GPUs only/}"
            note="${note# }"
            note="${note% }"
        fi

        printf "%d: %s" "$index" "$label"
        if [ -n "$note" ]; then
            printf " [%s]" "$note"
        fi
        if [ -n "$patch_info" ]; then
            printf "%s" "$patch_info"
        fi
        printf "\n"
        selection_map["$index"]="$branch"
        ((index++))
    done

    if [ "$index" -eq 1 ]; then
        echo -e "${RED}[!]${NC} No driver entries available for selection."
        return 1
    fi

    echo ""
    read -r -p "Enter your choice: " driver_choice
    driver_choice=$(strip_trailing_carriage_return "$driver_choice")

    local branch="${selection_map[$driver_choice]:-}"
    if [ -z "$branch" ]; then
        echo -e "${RED}[!]${NC} Invalid choice. Please enter a valid option."
        return 1
    fi

    driver_version="$branch"
    driver_filename="${DRIVER_FILES[$branch]}"
    driver_patch="${DRIVER_PATCHES[$branch]}"
    md5="${DRIVER_MD5[$branch]}"
    driver_url="${DRIVER_URLS[$branch]}"
    return 0
}

# License the vGPU
configure_fastapi_dls() {
    echo ""
    if [ "${FASTAPI_WARNING}" = "1" ]; then
        echo -e "${YELLOW}[!]${NC} Detected host driver branch ${DRIVER_VERSION}. FastAPI-DLS requires gridd-unlock patches for vGPU 18.x and newer."
        echo -e "${YELLOW}[-]${NC} Review https://git.collinwebdesigns.de/vgpu/nvlts for licensing alternatives."
        echo ""
    fi
    while true; do
        read -p "$(echo -e "${BLUE}[?]${NC} Do you want to license the vGPU? (y/n): ")" choice
        echo ""

        case "$choice" in
        y|Y)
        # Installing Docker-CE
        run_command "Installing Docker-CE" "info" "apt remove -y docker.io docker-compose docker-compose-v2 podman-docker || true; \
        apt install ca-certificates curl -y; \
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; \
        chmod a+r /etc/apt/keyrings/docker.asc; \
        echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null; \
        apt update; \
        apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y"

        # Docker pull FastAPI-DLS
        run_command "Docker pull FastAPI-DLS" "info" "docker pull collinwebdesigns/fastapi-dls:latest; \
        working_dir=/opt/docker/fastapi-dls/cert; \
        mkdir -p \$working_dir; \
        cd \$working_dir; \
        openssl genrsa -out \$working_dir/instance.private.pem 2048; \
        openssl rsa -in \$working_dir/instance.private.pem -outform PEM -pubout -out \$working_dir/instance.public.pem; \
        echo -e '\n\n\n\n\n\n\n' | openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout \$working_dir/webserver.key -out \$working_dir/webserver.crt; \
        docker volume create dls-db"

        # Get the timezone of the Proxmox server
        if command -v timedatectl >/dev/null 2>&1; then
            timezone=$(timedatectl 2>/dev/null | awk -F': ' '/Time zone/ {print $2}' | awk '{print $1}')
        fi
        timezone=${timezone:-UTC}

        # Determine host address for clients to reach FastAPI-DLS
        host_address=$(detect_primary_ip)
        if [ -z "$host_address" ]; then
            host_address=$(hostname 2>/dev/null || echo "localhost")
        fi

        fastapi_dir=~/fastapi-dls
        mkdir -p "$fastapi_dir"

        # Ask for desired port number here
        echo ""
        read -p "$(echo -e "${BLUE}[?]${NC} Enter the desired port number for FastAPI-DLS (default is 8443): ")" portnumber
        portnumber=${portnumber:-8443}
        echo -e "${RED}[!]${NC} Don't use port 80 or 443 since Proxmox is using those ports"
        echo ""

        echo -e "${GREEN}[+]${NC} Generate Docker YAML compose file"
        # Generate the Docker Compose YAML file
        cat > "$fastapi_dir/docker-compose.yml" <<EOF
version: '3.9'

x-dls-variables: &dls-variables
  TZ: "$timezone"
  DLS_URL: "$host_address"
  DLS_PORT: "$portnumber"
  LEASE_EXPIRE_DAYS: 90  # 90 days is maximum
  DATABASE: sqlite:////app/database/db.sqlite
  DEBUG: "false"

services:
  wvthoog-fastapi-dls:
    image: collinwebdesigns/fastapi-dls:latest
    container_name: wvthoog-fastapi-dls
    restart: always
    working_dir: /app
    environment:
      <<: *dls-variables
      PYTHONPATH: /app
    ports:
      - "${portnumber}:443"
    security_opt:
      - seccomp=unconfined
      - apparmor=unconfined
    command: >
      uvicorn main:app
      --host 0.0.0.0 --port 443
      --ssl-keyfile /app/cert/webserver.key
      --ssl-certfile /app/cert/webserver.crt
      --loop asyncio
    volumes:
      - dls-db:/app/database
      - /opt/docker/fastapi-dls/cert:/app/cert
    healthcheck:
      test: ["CMD", "curl", "-k", "--fail", "https://127.0.0.1:443/-/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s

volumes:
  dls-db:
EOF
        # Issue docker compose
        run_command "Running Docker Compose" "info" "docker compose -f \"$fastapi_dir/docker-compose.yml\" up -d"

        echo -e "${BLUE}[i]${NC} FastAPI-DLS health endpoint: https://$host_address:$portnumber/-/health"
        echo -e "${BLUE}[i]${NC} Docker Compose defaults to the asyncio event loop for compatibility. Review $fastapi_dir/docker-compose.yml if you need uvloop." 

        # Create directory where license script (Windows/Linux are stored)
        mkdir -p $VGPU_DIR/licenses

        echo -e "${GREEN}[+]${NC} Generate FastAPI-DLS Windows/Linux executables"
        # Create .sh file for Linux
        cat > "$VGPU_DIR/licenses/license_linux.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
DEST_DIR="/etc/nvidia/ClientConfigToken"
DEST="\${DEST_DIR}/client_configuration_token_\$(date +%Y%m%d_%H%M%S).tok"
mkdir -p "\$DEST_DIR"
curl -fsSLk "https://${host_address}:${portnumber}/-/client-token" -o "\$DEST"
if systemctl list-units --type=service 2>/dev/null | grep -qi nvidia-gridd; then
  systemctl restart nvidia-gridd
fi
nvidia-smi -q | grep -i license || true
echo "Token saved to: \$DEST"
EOF

        # Create .ps1 file for Windows
# Windows .ps1 — keep PS dollars intact, then inject host/port
        cat > "$VGPU_DIR/licenses/license_windows.ps1" <<'EOF'
$ErrorActionPreference = "Stop"
$dest = "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_$(Get-Date -f 'yyyyMMdd_HHmmss').tok"

# Trust self-signed (process-local)
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint s, X509Certificate c, WebRequest r, int p) { return true; }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Invoke-WebRequest -Uri "https://__DLS_HOST__:__DLS_PORT__/-/client-token" -OutFile $dest -UseBasicParsing
Restart-Service NVDisplay.ContainerLocalSystem -Force -ErrorAction SilentlyContinue
& nvidia-smi -q | Select-String -SimpleMatch "License"
EOF

# Inject resolved values
sed -i "s|__DLS_HOST__|$host_address|g; s|__DLS_PORT__|$portnumber|g" "$VGPU_DIR/licenses/license_windows.ps1"


        echo -e "${GREEN}[+]${NC} license_windows.ps1 and license_linux.sh created and stored in: $VGPU_DIR/licenses"
        echo -e "${YELLOW}[-]${NC} Copy these files to your Windows or Linux VM's and execute"
        echo ""
        return 0
        ;;
        n|N)
        echo -e "${YELLOW}[-]${NC} Skipping FastAPI-DLS deployment. You can run option 6 later if needed."
        echo ""
        return 0
        ;;
        *)
        echo -e "${RED}[!]${NC} Invalid choice. Please enter (y/n)."
        echo ""
        ;;
        esac
    done
}

print_guest_driver_guidance() {
    local branch="$1"
    local driver_filename="$2"

    if [[ -z "$branch" ]]; then
        printf "%b\n" "${GREEN}[+]${NC} Guest drivers matching ${driver_filename} can be downloaded automatically via the prompts above or main menu option 5."
        return
    fi

    case "$branch" in
        19.*)
            printf "%b\n" "${BLUE}[i]${NC} NVIDIA's enterprise portal still hosts the 19.x catalog if you need an alternate source."
            ;;
        18.*)
            printf "%b\n" "${BLUE}[i]${NC} NVIDIA's enterprise portal remains a fallback for 18.x guest drivers if direct downloads are unavailable."
            ;;
        17.4)
            printf "%b\n" "${BLUE}[i]${NC} Reference guest driver version: 550.127.06"
            ;;
        17.3)
            printf "%b\n" "${BLUE}[i]${NC} Reference guest driver version: 550.90.05"
            ;;
        17.0)
            printf "%b\n" "${BLUE}[i]${NC} Manual download references:"
            printf "%b\n" "${BLUE}[i]${NC}   Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.0/NVIDIA-Linux-x86_64-550.54.14-grid.run"
            printf "%b\n" "${BLUE}[i]${NC}   Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.0/551.61_grid_win10_win11_server2022_dch_64bit_international.exe"
            ;;
        16.4)
            printf "%b\n" "${BLUE}[i]${NC} Manual download references:"
            printf "%b\n" "${BLUE}[i]${NC}   Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.4/NVIDIA-Linux-x86_64-535.161.07-grid.run"
            printf "%b\n" "${BLUE}[i]${NC}   Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.4/538.33_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
            ;;
        16.2)
            printf "%b\n" "${BLUE}[i]${NC} Manual download references:"
            printf "%b\n" "${BLUE}[i]${NC}   Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.2/NVIDIA-Linux-x86_64-535.129.03-grid.run"
            printf "%b\n" "${BLUE}[i]${NC}   Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.2/537.70_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
            ;;
        16.1)
            printf "%b\n" "${BLUE}[i]${NC} Manual download references:"
            printf "%b\n" "${BLUE}[i]${NC}   Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.1/NVIDIA-Linux-x86_64-535.104.05-grid.run"
            printf "%b\n" "${BLUE}[i]${NC}   Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.1/537.13_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
            ;;
        16.0)
            printf "%b\n" "${BLUE}[i]${NC} Manual download references:"
            printf "%b\n" "${BLUE}[i]${NC}   Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.0/NVIDIA-Linux-x86_64-535.54.03-grid.run"
            printf "%b\n" "${BLUE}[i]${NC}   Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.0/536.25_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
            ;;
        *)
            printf "%b\n" "${BLUE}[i]${NC} NVIDIA's enterprise portal remains a fallback source if the automated download catalog is unreachable."
            ;;
    esac
}

print_installation_summary() {
    local branch="$1"
    local driver_filename="$2"

    local host_version=""
    if ! host_version=$(extract_host_version_from_filename "$driver_filename" 2>/dev/null); then
        host_version=""
    fi

    echo ""
    echo -e "${GREEN}[✓]${NC} Step 2 completed and installation process is now finished."
    echo ""
    echo -e "${CYAN}Summary of actions:${NC}"
    echo -e "  ${GREEN}•${NC} Installed and validated host driver: ${driver_filename}"
    if [ -n "$host_version" ]; then
        echo -e "  ${GREEN}•${NC} Confirmed driver version ${host_version} for branch ${branch:-unknown}"
    elif [ -n "$branch" ]; then
        echo -e "  ${GREEN}•${NC} Target driver branch: ${branch}"
    fi
    echo -e "  ${GREEN}•${NC} Enabled required vGPU services"
    echo -e "  ${GREEN}•${NC} Cleaned installer configuration (config.txt removed)"
    echo ""
    echo -e "${GREEN}${BOLD}-------------------------------------${NC}"
    echo -e "${GREEN}${BOLD}vGPU Install Successfull!${NC}"
    echo -e "${GREEN}${BOLD}-------------------------------------${NC}"
    echo -e "${CYAN}Viewing the status of vGPU on the host:${NC}"
    echo -e "${WHITE}Type - ${BOLD}nvidia-smi${NC} - to view your vGPU"
    echo -e "${WHITE}Type - ${BOLD}mdevctl types${NC} - to view mdev profiles available"
    echo -e "${GREEN}${BOLD}-------------------------------------${NC}"
    echo -e "${CYAN}To add vGPU to VM's:${NC}"
    echo -e "${WHITE}1)${NC} Do this once: Enter Proxmox Web UI, navigate to ${BOLD}Datacenter → Resource Mappings → PCI Devices → Add${NC} → Check ${BOLD}'Use with Mediated Devices'${NC} → Check following NVIDIA device → Input Name (e.g. ${BOLD}'vGPU'${NC}) → ${BOLD}Create${NC}."
    echo -e "${WHITE}2)${NC} Navigate to the VM in Proxmox, choose ${BOLD}Hardware → Add → PCI Device${NC}, select ${BOLD}'vGPU'${NC} at 'Mapped Device', then pick the desired ${BOLD}'MDev Type'${NC} (typically a Q profile), toggle ${BOLD}'Advanced'${NC}, check ${BOLD}'PCI-Express'${NC}, click ${BOLD}'Add'${NC}."
    echo -e "${WHITE}3)${NC} Boot the VM and install the downloaded guest drivers matched with the host driver (or rerun this script later to fetch them)."
    echo -e "${WHITE}4)${NC} Inside the guest, run ${BOLD}nvidia-smi${NC} to confirm the vGPU is active."
    echo ""
    echo -e "${CYAN}nvidia-smi status check:${NC}"
    if command -v nvidia-smi >/dev/null 2>&1; then
        if nvidia_smi_runtime_output=$(nvidia-smi 2>&1); then
            echo -e "${GREEN}[+]${NC} nvidia-smi executed successfully:"
            printf '%s\n' "$nvidia_smi_runtime_output"
        else
            status=$?
            echo -e "${RED}[!]${NC} nvidia-smi exited with status $status. Output:"
            printf '%s\n' "$nvidia_smi_runtime_output"
            echo -e "${YELLOW}[-]${NC} Driver may not be loaded correctly; investigate before deploying workloads."
        fi
    else
        echo -e "${YELLOW}[-]${NC} nvidia-smi command not found. Ensure the NVIDIA driver is installed and in your PATH."
    fi
    echo ""
    echo -e "${GREEN}Installation tasks complete.${NC}"
    echo ""
}

perform_step_two() {
    echo ""
    echo "You are currently at step ${STEP} of the installation process"
    echo ""
    echo "Proceeding with the installation"
    echo ""

    # Auto-detect GPU if VGPU_SUPPORT is empty (e.g. config.txt was cleaned or running step 2 directly)
    if [ -z "${VGPU_SUPPORT:-}" ]; then
        if [ -f "$SCRIPT_DIR/gpu_info.db" ]; then
            if check_gpu_database; then
                detect_gpus
            fi
        fi
    fi

    load_patch_overrides

    secure_boot_precheck

    # Check if IOMMU / DMAR is enabled
    if dmesg | grep -e IOMMU | grep -q "Detected AMD IOMMU"; then
        echo -e "${GREEN}[+]${NC} AMD IOMMU Enabled"
    elif dmesg | grep -e DMAR | grep -q "IOMMU enabled"; then
        echo -e "${GREEN}[+]${NC} Intel IOMMU Enabled"
    else
        vendor_id=$(cat /proc/cpuinfo | grep vendor_id | awk 'NR==1{print $3}')
        if [ "$vendor_id" = "AuthenticAMD" ]; then
            echo -e "${RED}[!]${NC} AMD IOMMU Disabled"
            echo -e ""
            echo -e "Please make sure you have IOMMU enabled in the BIOS"
            echo -e "and make sure that this line is present in /etc/default/grub"
            echo -e "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet amd_iommu=on iommu=pt\""
            echo ""
        elif [ "$vendor_id" = "GenuineIntel" ]; then
            echo -e "${RED}[!]${NC} Intel IOMMU Disabled"
            echo -e ""
            echo -e "Please make sure you have VT-d enabled in the BIOS"
            echo -e "and make sure that this line is present in /etc/default/grub"
            echo -e "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet intel_iommu=on iommu=pt\""
            echo ""
        else
            echo -e "${RED}[!]${NC} Unknown CPU architecture."
            echo ""
            exit 1
        fi
        echo -n -e "${RED}[!]${NC} IOMMU is disabled. Do you want to continue anyway? (y/n): "
        read -r continue_choice
        if [ "$continue_choice" != "y" ]; then
            echo "Exiting script."
            exit 0
        fi
    fi

    if [ -n "$URL" ]; then
        echo -e "${GREEN}[+]${NC} Downloading vGPU host driver using curl"
        # Extract filename from URL
        driver_filename=$(extract_filename_from_url "$URL")

        # Download the file using wget
        run_command "Downloading $driver_filename" "info" "wget -O $driver_filename $URL"

        if [[ "$driver_filename" == *.zip ]]; then
            # Extract the zip file
            unzip -q "$driver_filename"
            # Look for .run file inside
            run_file=$(find . -name '*.run' -type f -print -quit)
            if [ -n "$run_file" ]; then
                # Map filename to driver version and patch
                if map_filename_to_version "$run_file"; then
                    driver_filename="$run_file"
                    sync_fastapi_flag
                else
                    echo -e "${RED}[!]${NC} Unrecognized filename inside the zip file. Exiting."
                    exit 1
                fi
            else
                echo -e "${RED}[!]${NC} No .run file found inside the zip. Exiting."
                exit 1
            fi
        fi

        # Check if it's a .run file
        if [[ "$driver_filename" =~ \.run$ ]]; then
            # Map filename to driver version and patch
            if map_filename_to_version "$driver_filename"; then
                echo -e "${GREEN}[+]${NC} Compatible filename found: $driver_filename"
                sync_fastapi_flag
            else
                echo -e "${RED}[!]${NC} Unrecognized filename: $driver_filename. Exiting."
                exit 1
            fi
        else
            echo -e "${RED}[!]${NC} Invalid file format. Only .zip and .run files are supported. Exiting."
            exit 1
        fi

    elif [ -n "$FILE" ]; then
        echo -e "${GREEN}[+]${NC} Using $FILE as vGPU host driver"
        # Map filename to driver version and patch
        if map_filename_to_version "$FILE"; then
            # If the filename is recognized
            driver_filename="$FILE"
            echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"
            sync_fastapi_flag
        else
            # If the filename is not recognized
            echo -e "${RED}[!]${NC} No patches available for your vGPU driver version"
            exit 1
        fi
    else

        case "$major_version" in
            9)
                echo -e "${YELLOW}[-]${NC} You are running Proxmox version $version"
                if contains_version "19"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver branch 19.x"
                elif contains_version "18"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver branch 18.x"
                elif contains_version "17"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver branch 17.x"
                else
                    echo -e "${YELLOW}[-]${NC} Review GPU database output for the recommended branch."
                fi
                ;;
            8)
                echo -e "${YELLOW}[-]${NC} You are running Proxmox version $version"
                if contains_version "18"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver branch 18.x"
                elif contains_version "17" && contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver branches 17.x and 16.x"
                elif contains_version "17"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver branch 17.x"
                elif contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver branch 16.x"
                fi
                ;;
            7)
                echo -e "${YELLOW}[-]${NC} You are running Proxmox version $version"
                if contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver branch 16.x"
                fi
                ;;
        esac

        if ! select_driver_branch false; then
            exit 1
        fi

        echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"

        DRIVER_VERSION="$driver_version"
        sync_fastapi_flag

        # Auto-discover host driver from alist if no URL registered or URL is "auto"
        if [ -z "$URL" ] && { [ -z "$driver_url" ] || [ "$driver_url" = "auto" ]; }; then
            log_info "Auto-discovering host driver from alist..."
            discovered_url=""
            discovered_url=$(resolve_host_driver_url "$driver_version" "$driver_url" 2>/dev/null) || discovered_url=""
            if [ -n "$discovered_url" ]; then
                driver_url="$discovered_url"
                display_url="${driver_url%|zip}"
                log_info "Found host driver: $display_url"
            fi
        fi

        if [ -z "$URL" ] && { [ -z "$driver_url" ] || [ "$driver_url" = "auto" ]; }; then
            echo -e "${RED}[!]${NC} No download URL registered for $driver_filename. Provide the file manually or use --url."
            echo -e "${YELLOW}[-]${NC} Auto-discovery from alist failed for vGPU ${driver_version}. Check network access or place the driver file in this directory."
            exit 1
        fi

        if [ -z "$URL" ]; then
            # Check if driver file already exists
            if [ -e "$driver_filename" ]; then
                echo -e "${GREEN}[+]${NC} Driver file $driver_filename already exists. Using existing file."
            else
                # Auto-download using host-drivers-auto module
                if [ -n "$driver_url" ]; then
                    echo -e "${GREEN}[+]${NC} Downloading vGPU $driver_filename host driver"
                    if install_host_driver_download "$driver_url" "$driver_filename" "."; then
                        echo -e "${GREEN}[+]${NC} Download completed: $driver_filename"
                    else
                        echo -e "${RED}[!]${NC} Failed to download driver"
                        exit 1
                    fi
                fi
            fi
        fi
    fi

    # Fallback to pre-patched custom driver if the original is not present
    custom_filename="${driver_filename%.run}-custom.run"
    if [[ "$driver_filename" == *-vgpu-kvm-custom.run ]]; then
        custom_filename="$driver_filename"
    fi
    if [ ! -f "$driver_filename" ] && [ -f "$custom_filename" ]; then
        driver_filename="$custom_filename"
        echo -e "${GREEN}[+]${NC} Pre-patched driver detected: using $driver_filename"
    fi

    # Make driver executable
    chmod +x "$driver_filename"

    secure_boot_flags=$(build_secure_boot_flags)
    if [ -n "$secure_boot_flags" ]; then
        echo -e "${GREEN}[+]${NC} Secure Boot signing parameters will be applied during driver installation."
    fi

    if [ "$VGPU_SUPPORT" = "Yes" ]; then
        # Consumer vGPU unlock cards MUST force proprietary closed-source modules (-m=kernel)
        # because the open-source kernel modules (nvidia-open) do not support vGPU virtual functions at all.
        install_flags="--dkms -m=kernel -s"
    elif [ "$VGPU_SUPPORT" = "Native" ]; then
        # Native vGPU enterprise drivers (vgpu-kvm.run) do not contain open-source modules
        # and do not support the -m parameter.
        install_flags="--dkms -s"
    else
        # For non-vGPU or other fallback scenarios, respect the driver version's default behavior
        if version_ge "$driver_version" "17.6"; then
            install_flags="--dkms -s"
        else
            install_flags="--dkms -m=kernel -s"
        fi
    fi
    if [ -n "$secure_boot_flags" ]; then
        install_flags="$install_flags $secure_boot_flags"
    fi

    # Patch and install the driver only if vGPU is not native
    if [ "$VGPU_SUPPORT" = "Yes" ]; then
        if is_kernel_617_or_higher; then
            local target_k; target_k=$(discover_target_kernel_version)
            echo -e "${RED}[!]${NC} Kernel $(uname -r) is too new for the vGPU unlock drivers (maximum supported branch is 17.6)."
            echo -e "${YELLOW}[-]${NC} You must complete step 1 to downgrade/pin the compatible kernel (${target_k}) and reboot before running step 2."
            exit 1
        fi

        # Add custom to original filename
        custom_filename="${driver_filename%.run}-custom.run"
        if [[ "$driver_filename" == *-vgpu-kvm-custom.run ]]; then
            custom_filename="$driver_filename"
        fi
        custom_backup=""
        patched_installer=""

        # Pre-patched installer from alist (or left from a previous run)
        if [ -e "$custom_filename" ]; then
            patched_installer="$custom_filename"
            echo -e "${GREEN}[+]${NC} Using pre-patched driver: $custom_filename (skipping --apply-patch)"
        fi

        if [ -z "$patched_installer" ]; then
        if [ -z "$driver_patch" ]; then
            echo -e "${RED}[!]${NC} Patch metadata missing for driver $driver_filename. Unable to continue unlock-based installation."
            exit 1
        fi

        # Check if $custom_filename exists
        if [ -e "$custom_filename" ]; then
            custom_backup="${custom_filename}.bak.$(date +%s)"
            mv "$custom_filename" "$custom_backup"
            echo -e "${YELLOW}[-]${NC} Moved $custom_filename to $custom_backup"
        fi

        pre_patch_snapshot=$(snapshot_run_artifacts)
        original_driver_checksum=""
        original_driver_mtime=""
        if [ -e "$driver_filename" ]; then
            original_driver_checksum=$(sha256sum "$driver_filename" 2>/dev/null | awk '{print $1}')
            original_driver_mtime=$(stat -c '%Y' "$driver_filename" 2>/dev/null || echo "")
        fi

        # Patch and install the driver
        ensure_patch_compat
        if ! ensure_vgpu_proxmox_patch "$driver_patch"; then
            echo -e "${YELLOW}[-]${NC} Complete step 1 (new install) or run: git clone https://gitlab.com/polloloco/vgpu-proxmox.git $VGPU_DIR/vgpu-proxmox"
            exit 1
        fi

        if ! run_command "Patching driver" "info" "./$driver_filename --apply-patch $VGPU_DIR/vgpu-proxmox/$driver_patch"; then
            echo -e "${RED}[!]${NC} Driver patch command failed."
            show_debug_log_tail 60
            echo -e "${YELLOW}[-]${NC} Retry manually: ./$driver_filename --apply-patch $VGPU_DIR/vgpu-proxmox/$driver_patch"
            exit 1
        fi

        post_patch_snapshot=$(snapshot_run_artifacts)
        patched_installer=""

        if [ -e "$custom_filename" ]; then
            patched_installer="$custom_filename"
        fi

        if [ -z "$patched_installer" ]; then
            patched_installer=$(select_new_run_artifact "$pre_patch_snapshot" "$post_patch_snapshot" "$driver_filename" || true)
        fi

        if [ -z "$patched_installer" ] && [ -n "$original_driver_checksum" ] && [ -e "$driver_filename" ]; then
            new_driver_checksum=$(sha256sum "$driver_filename" 2>/dev/null | awk '{print $1}')
            new_driver_mtime=$(stat -c '%Y' "$driver_filename" 2>/dev/null || echo "")
            if [ -n "$new_driver_checksum" ] && [ "$new_driver_checksum" != "$original_driver_checksum" ]; then
                patched_installer="$driver_filename"
                echo -e "${YELLOW}[-]${NC} Patched installer appears to reuse $driver_filename (checksum changed)."
            elif [ -n "$new_driver_mtime" ] && [ -n "$original_driver_mtime" ] && [ "$new_driver_mtime" != "$original_driver_mtime" ]; then
                patched_installer="$driver_filename"
                echo -e "${YELLOW}[-]${NC} Patched installer appears to reuse $driver_filename (timestamp updated)."
            fi
        fi

        if [ -n "$custom_backup" ] && [ -e "$custom_backup" ]; then
            if [ -n "$patched_installer" ]; then
                rm -f "$custom_backup"
            elif [ ! -e "$custom_filename" ]; then
                mv "$custom_backup" "$custom_filename"
            fi
        fi
        fi

        if [ -z "$patched_installer" ] || [ ! -e "$patched_installer" ]; then
            echo -e "${RED}[!]${NC} Patched driver file not found after applying patch."
            echo -e "${YELLOW}[-]${NC} Expected ${custom_filename} or a new *-vgpu-kvm*.run after patching."
            echo -e "${YELLOW}[-]${NC} The host .run downloaded OK; vgpu_unlock patch did not produce an installer (see log below)."
            show_debug_log_tail 60
            echo -e "${YELLOW}[-]${NC} Manual test: ./$driver_filename --apply-patch $VGPU_DIR/vgpu-proxmox/$driver_patch"
            echo -e "${YELLOW}[-]${NC} Success ends with: Self-extractible archive \"...-vgpu-kvm-custom.run\" successfully created."
            available_runs="$post_patch_snapshot"
            if [ -z "$available_runs" ]; then
                available_runs=$(snapshot_run_artifacts)
            fi
            if [ -n "${available_runs:-}" ]; then
                available_runs=$(printf '%s\n' "$available_runs" | sed 's/^/    - /')
                echo -e "${YELLOW}[-]${NC} Installer artifacts detected in $(pwd):\n${available_runs}"
            fi
            exit 1
        fi

        # Run the patched driver installer
        chmod +x "$patched_installer"
        if ! run_command "Installing patched driver" "info" "./$patched_installer $install_flags"; then
            echo -e "${RED}[!]${NC} Patched driver installation failed (often kernel/DKMS mismatch on 6.17+ or 7.x)."
            echo -e "${YELLOW}[-]${NC} Check: uname -r  and  tail -50 /var/log/nvidia-installer.log"
            show_debug_log_tail 40
            if is_kernel_617_or_higher; then
                local target_k; target_k=$(discover_target_kernel_version)
                echo -e "${YELLOW}[-]${NC} For vGPU unlock on 16.x–19.x: reboot into pinned kernel ${target_k} after step 1, then rerun step 2."
            fi
            exit 1
        fi
    elif [ "$VGPU_SUPPORT" = "Native" ] || [ "$VGPU_SUPPORT" = "Unknown" ]; then
        # Run the regular driver installer
		
		echo "Installing native driver" "info" "./$driver_filename $install_flags"
		
        run_command "Installing native driver" "info" "./$driver_filename $install_flags"
    else
        echo -e "${RED}[!]${NC} Unknown or unsupported GPU: $VGPU_SUPPORT"
        echo ""
        echo "Exiting script."
        echo ""
        exit 1
    fi

    echo -e "${GREEN}[+]${NC} Driver installed successfully."

    echo -e "${GREEN}[+]${NC} Nvidia driver version: $driver_filename"

    nvidia_smi_output=$(nvidia-smi vgpu 2>&1)

    # Extract version from FILE
    FILE_VERSION=$(echo "$driver_filename" | grep -oP '\d+\.\d+\.\d+' || true)

    # For consumer cards (vgpu_unlock), nvidia-smi vgpu will output "No supported devices in vGPU mode"
    # because vgpu_unlock is only preloaded in the systemd services, not in the active shell.
    # We fall back to running standard nvidia-smi to confirm the driver itself is active.
    if [ "$VGPU_SUPPORT" = "Yes" ] && [[ "$nvidia_smi_output" == *"No supported devices in vGPU mode"* ]]; then
        if nvidia_smi_std=$(nvidia-smi 2>&1) && [[ "$nvidia_smi_std" != *"NVIDIA-SMI has failed"* ]]; then
            nvidia_smi_output="$nvidia_smi_std"
        fi
    fi

    if [[ "$nvidia_smi_output" == *"NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver."* ]] || [[ "$nvidia_smi_output" == *"No supported devices in vGPU mode"* ]]; then
        echo -e "${RED}[!]${NC} Nvidia driver not properly loaded"
    elif [[ "$nvidia_smi_output" == *"Driver Version: $FILE_VERSION"* ]]; then
        echo -e "${GREEN}[+]${NC} Nvidia driver properly loaded, version matches $FILE_VERSION"
    else
        echo -e "${GREEN}[+]${NC} Nvidia driver properly loaded"
    fi

    # Start nvidia-services
    if systemctl list-unit-files nvidia-vgpud.service >/dev/null 2>&1; then
        run_command "Enable nvidia-vgpud.service" "info" "systemctl enable --now nvidia-vgpud.service"
    else
        echo -e "${YELLOW}[-]${NC} Skipping enable for nvidia-vgpud.service (unit not found)."
    fi

    if systemctl list-unit-files nvidia-vgpu-mgr.service >/dev/null 2>&1; then
        run_command "Enable nvidia-vgpu-mgr.service" "info" "systemctl enable --now nvidia-vgpu-mgr.service"
    else
        echo -e "${YELLOW}[-]${NC} Skipping enable for nvidia-vgpu-mgr.service (unit not found)."
    fi

    # Enable SR-IOV capabilites for supported Native vGPU cards (wait for 5 seconds)
	sleep 5

    if [ "$VGPU_SUPPORT" = "Native" ]; then
        run_command "Enable SR-IOV" "info" "systemctl enable --now pve-nvidia-sriov@ALL.service" || {
            echo -e "${YELLOW}[-]${NC} SR-IOV service not available or failed to start, but continuing installation."
        }
        echo -e "${GREEN}[+]${NC} Listing vGPU VFs:"
        lspci -d 10de: || true
	fi

    if [ "${FASTAPI_WARNING}" = "1" ]; then
        echo -e "${YELLOW}[!]${NC} Reminder: Driver branch ${driver_version} requires gridd-unlock patches or nvlts for licensing."
    fi


    prompt_guest_driver_downloads "$driver_version" "$driver_filename"

    # Provide guest driver guidance without relying on nested case blocks to avoid parser issues on older bash releases
    print_guest_driver_guidance "$driver_version" "$driver_filename"

    rm -f "$CONFIG_FILE"

    # Option to license the vGPU
    configure_fastapi_dls

    print_installation_summary "$driver_version" "$driver_filename"
}


# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo or execute as root user."
    exit 1
fi

# Welcome message and disclaimer
echo -e ""
echo -e "${GREEN}        __________  __  __   ____           __        ____          "
echo -e "${YELLOW} _   __${GREEN}/ ____/ __ \/ / / /  /  _/___  _____/ /_____ _/ / /__  _____ "
echo -e "${YELLOW}| | / /${GREEN} / __/ /_/ / / / /   / // __ \/ ___/ __/ __ ' / / / _\/ ___/ "
echo -e "${YELLOW}| |/ /${GREEN} /_/ / ____/ /_/ /  _/ // / / (__  ) /_/ /_/ / / /  __/ /     "
echo -e "${YELLOW}|___/${GREEN}\____/_/    \____/  /___/_/ /_/____/\__/\__,_/_/_/\___/_/      ${NC}"
echo -e "${GREEN}By anomixer${NC} (based on wvthoog.nl's v1.1 script)"
echo -e "${GREEN}Thanks to: RocketRammer, LeonardSEO${NC}"
echo -e ""
echo -e "Welcome to the Nvidia vGPU installer version $SCRIPT_VERSION for Proxmox"
echo -e "This system is running Proxmox version ${version} with kernel ${kernel}"
echo ""

# Main installation process
case $STEP in
    1)
    echo "Select an option:"
    echo ""
    echo "1) New vGPU installation"
    echo "2) Upgrade vGPU installation"
    echo "3) Remove vGPU installation"
    echo "4) Download vGPU drivers"
    echo "5) Download guest drivers"
    echo "6) License vGPU"
    echo "7) Exit"
    echo ""
    read -r -p "Enter your choice: " choice
    choice=$(strip_trailing_carriage_return "$choice")

    case $choice in
        1|2)
            echo ""
            echo "You are currently at step ${STEP} of the installation process"
            echo ""
            if [ "$choice" -eq 1 ]; then
                echo -e "${GREEN}Selected:${NC} New vGPU installation"
                # Check if config file exists, if not, create it
                set_config_value "STEP" "1"
            elif [ "$choice" -eq 2 ]; then
                echo -e "${GREEN}Selected:${NC} Upgrade from previous vGPU installation"
            fi
            echo ""

            # Commands for new installation
            echo -e "${GREEN}[+]${NC} Preparing APT repositories for Proxmox major version ${RED}$major_version${NC}"
            configure_proxmox_repos

            # # Comment Proxmox enterprise repository
            # echo -e "${GREEN}[+]${NC} Commenting Proxmox enterprise repository"
            # sed -i 's/^/#/' /etc/apt/sources.list.d/pve-enterprise.list

            # # Replace ceph-quincy enterprise for non-subscribtion
            # echo -e "${GREEN}[+]${NC} Set Ceph to no-subscription"
            # sed -i 's#^enterprise #no-subscription#' /etc/apt/sources.list.d/ceph.list

            # APT update/upgrade
            run_command "Running APT Update" "info" "apt update"

            # Prompt the user for confirmation (Issue #12 - Added verbose option)
            echo ""
            echo -e "${CYAN}[i]${NC} APT Dist-Upgrade will update all packages to their latest versions."
            echo -e "${CYAN}[i]${NC} This may take several minutes depending on your system and internet speed."
            read -p "$(echo -e "${BLUE}[?]${NC} Do you want to proceed with APT Dist-Upgrade? (y/n): ")" confirmation
            echo ""

            # Check user's choice
            if [ "$confirmation" == "y" ]; then
                echo -e "${GREEN}[+]${NC} Starting APT Dist-Upgrade..."
                echo -e "${CYAN}[i]${NC} You can monitor progress below:"
                run_command "Running APT Dist-Upgrade" "info" "apt dist-upgrade -y"
                echo -e "${GREEN}[+]${NC} APT Dist-Upgrade completed successfully."
            else
                echo -e "${YELLOW}[-]${NC} Skipping APT Dist-Upgrade"
                echo -e "${YELLOW}[-]${NC} Note: Skipping may cause compatibility issues with newer drivers."
            fi          

            # APT installing packages (Issue #7 - Improved header installation)
            # Ensure required tooling for kernel builds, downloads, and secure boot signing
            echo -e "${GREEN}[+]${NC} Installing required packages..."
            echo -e "${CYAN}[i]${NC} This includes: git, build-essential, dkms, kernel headers, and utilities"
            
            # Install base packages first
            run_command "Installing base packages" "info" "apt install -y git build-essential dkms mdevctl wget curl megatools jq mokutil unzip pve-nvidia-vgpu-helper"
            
            # Install kernel and headers with better error handling
            kernel_version=$(uname -r)
            echo -e "${CYAN}[i]${NC} Current kernel: $kernel_version"
            # Issue #14: Install signed kernel if Secure Boot is enabled
            if secure_boot_enabled; then
                echo -e "${CYAN}[i]${NC} Secure Boot detected — attempting to install signed kernel package."
                if kernel_signed_available "$kernel_version"; then
                    if ! run_command "Installing signed kernel package" "info" "apt install -y proxmox-kernel-${kernel_version}-signed" 2>/dev/null; then
                        echo -e "${YELLOW}[-]${NC} Signed kernel install failed, may already be installed"
                    fi
                else
                    echo -e "${YELLOW}[!]${NC} No signed kernel package found for $kernel_version."
                    echo -e "${YELLOW}[!]${NC} Installing unsigned kernel — this may cause boot failure on Secure Boot systems."
                    echo -e "${CYAN}[i]${NC} Consider manually installing a signed kernel or disabling Secure Boot before continuing."
                    if ! run_command "Installing kernel package (unsigned)" "info" "apt install -y proxmox-kernel-$kernel_version" 2>/dev/null; then
                        echo -e "${YELLOW}[-]${NC} Kernel package not available, may already be installed"
                    fi
                fi
            else
                if ! run_command "Installing kernel package" "info" "apt install -y proxmox-kernel-$kernel_version" 2>/dev/null; then
                    echo -e "${YELLOW}[-]${NC} Kernel package not available, may already be installed"
                fi
            fi
            
            if ! run_command "Installing kernel headers" "info" "apt install -y proxmox-headers-$kernel_version" 2>/dev/null; then
                echo -e "${YELLOW}[-]${NC} Proxmox headers not available, trying alternative..."
                ensure_kernel_headers
            else
                ensure_kernel_headers
            fi

            # Pinning the kernel
            if command -v pve-nvidia-vgpu-helper >/dev/null 2>&1 && [ "${VGPU_HELPER_STATUS}" != "done" ]; then
                echo -e "${GREEN}[+]${NC} Detected pve-nvidia-vgpu-helper."
                echo -e "${YELLOW}[-]${NC} This tool prepares headers, DKMS dependencies and kernel settings for vGPU."
                read -p "$(echo -e "${BLUE}[?]${NC} Run 'pve-nvidia-vgpu-helper setup' now? (y/n): ")" helper_choice
                if [ "$helper_choice" = "y" ]; then
					echo "Running pve-nvidia-vgpu-helper setup. NOTE: ANSWER YES WHEN ASKED!"
					pve-nvidia-vgpu-helper setup
                    set_config_value "VGPU_HELPER_STATUS" "done"
                    VGPU_HELPER_STATUS="done"
                fi
            fi

            if [[ "$major_version" -le 8 ]]; then
                # Get the kernel list and filter for 6.5 kernels
                kernel_list=$(proxmox-boot-tool kernel list | grep "6.5" || true)

                # Check if any 6.5 kernels are available
                if [[ -n "$kernel_list" ]]; then
                    # Extract the highest version
                    highest_version=""
                    while read -r line; do
                        kernel_version=$(echo "$line" | awk '{print $1}')
                        if [[ -z "$highest_version" ]]; then
                            highest_version="$kernel_version"
                        else
                            highest_version=$(kernel_version_compare "$highest_version" "$kernel_version")
                        fi
                    done <<< "$kernel_list"

                    # Pin the highest 6.5 kernel
                    run_command "Pinning kernel: $highest_version" "info" "proxmox-boot-tool kernel pin $highest_version"
                else
                    echo -e "${YELLOW}[-]${NC} No 6.5 kernels detected; skipping kernel pin."
                fi
            else
                echo -e "${YELLOW}[-]${NC} Kernel pinning is skipped for Proxmox version ${major_version}."
            fi

            # Running NVIDIA GPU checks
            gpu_info=$(lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)' || true)

            # Check if no NVIDIA GPU was found
            if [ -z "$gpu_info" ]; then
                read -p "$(echo -e "${RED}[!]${NC} No Nvidia GPU available in system, Continue? (y/n): ")" continue_choice
                if [ "$continue_choice" != "y" ]; then
                    echo "Exiting script."
                    exit 0
                fi

            # Check if only one NVIDIA GPU was found
            elif [ -n "$gpu_info" ] && [ $(echo "$gpu_info" | wc -l) -eq 1 ]; then
                # Extract device IDs from the output
                gpu_device_id=$(echo "$gpu_info" | grep -oE '\[10de:[0-9a-fA-F]{2,4}\]' | cut -d ':' -f 2 | tr -d ']')
                query_result=$(query_gpu_info "$gpu_device_id")

                if [[ -n "$query_result" ]]; then
                    vendor_id=$(echo "$query_result" | cut -d '|' -f 1)
                    description=$(echo "$query_result" | cut -d '|' -f 3)
                    vgpu=$(echo "$query_result" | cut -d '|' -f 4)
                    driver=$(echo "$query_result" | cut -d '|' -f 5 | tr ';' ',')
                    chip=$(echo "$query_result" | cut -d '|' -f 6)

                    if [[ -z "$chip" ]]; then
                        chip="Unknown"
                    fi

                    echo -e "${GREEN}[*]${NC} Found one Nvidia GPU in your system"
                    echo ""

                    # Write $driver to CONFIG_FILE. To be used to determine which driver to download in step 2

                    if [[ "$vgpu" == "No" ]]; then
                        echo "$description is not vGPU capable"
                        VGPU_SUPPORT="No"
                    elif [[ "$vgpu" == "Yes" ]]; then
                        echo "$description is vGPU capable through vgpu_unlock with driver version $driver"
                        VGPU_SUPPORT="Yes"
                        DRIVER_VERSION=$driver
                    elif [[ "$vgpu" == "Native" ]]; then
                        echo "$description supports native vGPU with driver version $driver"
                        VGPU_SUPPORT="Native"
                        DRIVER_VERSION=$driver
                    else
                        echo "$description of the $chip architecture and vGPU capability is unknown"
                        VGPU_SUPPORT="Unknown"
                    fi
                else
                    echo "Device ID: $gpu_device_id not found in the database."
                    VGPU_SUPPORT="Unknown"
                fi
                echo ""

            # If multiple NVIDIA GPU's were found
            else
                # Extract GPU devices from lspci -nn output
                gpu_devices=$(lspci -nn | grep -Ei '(VGA compatible controller|3D controller).*NVIDIA Corporation' || true)

                # Declare associative array to store GPU PCI IDs and device IDs
                declare -A gpu_pci_groups

                # Iterate over each GPU device line
                while read -r device; do
                    pci_id=$(echo "$device" | awk '{print $1}')
                    pci_device_id=$(echo "$device" | grep -oE '\[10de:[0-9a-fA-F]{2,4}\]' | cut -d ':' -f 2 | tr -d ']')
                    gpu_pci_groups["$pci_id"]="$pci_device_id"
                done <<< "$gpu_devices"

                # Iterate over each VGA GPU device, query its info, and display it
                echo -e "${GREEN}[*]${NC} Found multiple Nvidia GPUs in your system"
                echo ""

                # Initialize VGPU_SUPPORT variable
                VGPU_SUPPORT="Unknown"

                index=1
                for pci_id in "${!gpu_pci_groups[@]}"; do
                    gpu_device_id=${gpu_pci_groups[$pci_id]}
                    query_result=$(query_gpu_info "$gpu_device_id")
                    
                    if [[ -n "$query_result" ]]; then
                        vendor_id=$(echo "$query_result" | cut -d '|' -f 1)
                        description=$(echo "$query_result" | cut -d '|' -f 3)
                        vgpu=$(echo "$query_result" | cut -d '|' -f 4)
                        driver=$(echo "$query_result" | cut -d '|' -f 5 | tr ';' ',')
                        chip=$(echo "$query_result" | cut -d '|' -f 6)

                        if [[ -z "$chip" ]]; then
                            chip="Unknown"
                        fi

                        #echo "Driver: $driver"                        
                        
                        case $vgpu in
                            No)
                                if [[ "$VGPU_SUPPORT" == "Unknown" ]]; then
                                    gpu_info="is not vGPU capable"
                                    VGPU_SUPPORT="No"
                                fi
                                ;;
                            Yes)
                                if [[ "$VGPU_SUPPORT" == "No" ]]; then
                                    gpu_info="is vGPU capable through vgpu_unlock with driver version $driver"
                                    VGPU_SUPPORT="Yes"
                                    echo "info1: $driver"  
                                elif [[ "$VGPU_SUPPORT" == "Unknown" ]]; then
                                    gpu_info="is vGPU capable through vgpu_unlock with driver version $driver"
                                    VGPU_SUPPORT="Yes"
                                    echo "info2: $driver"  
                                fi
                                ;;
                            Native)
                                if [[ "$VGPU_SUPPORT" == "No" ]]; then
                                    gpu_info="supports native vGPU with driver version $driver"
                                    VGPU_SUPPORT="Native"
                                elif [[ "$VGPU_SUPPORT" == "Yes" ]]; then
                                    gpu_info="supports native vGPU with driver version $driver"
                                    VGPU_SUPPORT="Native"
                                    # Implore the user to use the native vGPU card and pass through the other card(s)
                                elif [[ "$VGPU_SUPPORT" == "Unknown" ]]; then
                                    gpu_info="supports native vGPU with driver version $driver"
                                    VGPU_SUPPORT="Native"
                                fi
                                ;;
                            Unknown)
                                    gpu_info="is a unknown GPU"
                                    VGPU_SUPPORT="No"
                                ;;
                        esac

                        # Display GPU info
                        echo "$index: $description $gpu_info"
                    else
                        echo "$index: GPU Device ID: $gpu_device_id on PCI bus 0000:$pci_id (query result not found in database)"
                    fi
                    
                    ((index++))
                done

                echo ""

                # Prompt the user to select a GPU
                echo -e "${BLUE}[?]${NC} Select the GPU you want to enable vGPU for. All other GPUs will be passed through."
                read -p "$(echo -e "${BLUE}[?]${NC} Enter the corresponding number: ")" selected_index
                echo ""

                # Validate user input
                if [[ ! "$selected_index" =~ ^[1-$index]$ ]]; then
                    echo -e "${RED}[!]${NC} Invalid input. Please enter a number between 1 and $((index-1))."
                    exit 1
                fi

                # Get the PCI ID of the selected GPU
                index=1
                for pci_id in "${!gpu_pci_groups[@]}"; do
                    if [[ $index -eq $selected_index ]]; then
                        selected_pci_id=$pci_id
                        break
                    fi
                    ((index++))
                done

                gpu_device_id=${gpu_pci_groups[$selected_pci_id]}
                query_result=$(query_gpu_info "$gpu_device_id")

                if [[ -n "$query_result" ]]; then
                    description=$(echo "$query_result" | cut -d '|' -f 3)
                    echo -e "${GREEN}[*]${NC} You selected GPU: $description with Device ID: $gpu_device_id on PCI bus 0000:$selected_pci_id"
                    DRIVER_VERSION=$driver
                else
                    echo -e "${RED}[!]${NC} GPU Device ID: $gpu_device_id not found in the database."
                fi

                # Add all PCI bus IDs to a UDEV rule that were not selected
                echo ""
                read -p "$(echo -e "${BLUE}[?]${NC} Do you want me to enable pass through for all other GPU devices? (y/n): ")" enable_pass_through
                echo ""
                if [[ "$enable_pass_through" == "y" ]]; then
                    echo -e "${YELLOW}[-]${NC} Enabling passthrough for devices:"
                    echo ""
                    for pci_id in "${!gpu_pci_groups[@]}"; do
                        if [[ "$pci_id" != "$selected_pci_id" ]]; then
                            if [ ! -z "$(ls -A /sys/class/iommu)" ]; then
                                for iommu_dev in $(ls /sys/bus/pci/devices/0000:$pci_id/iommu_group/devices) ; do
                                    echo "PCI ID: $iommu_dev"
                                    echo "ACTION==\"add\", SUBSYSTEM==\"pci\", KERNELS==\"$iommu_dev\", DRIVERS==\"*\", ATTR{driver_override}=\"vfio-pci\"" >> /etc/udev/rules.d/90-vfio-pci.rules
                                done
                            fi
                        fi
                    done
                    echo ""
                elif [[ "$enable_pass_through" == "n" ]]; then
                    echo -e "${YELLOW}[-]${NC} Add these lines by yourself, and execute a modprobe vfio-pci afterwards or reboot the server at the end of the script"
                    echo ""
                else
                    echo -e "${RED}[!]${NC} Invalid input. Please enter (y/n)."
                fi
            fi

            #echo "VGPU_SUPPORT: $VGPU_SUPPORT"

            if [ "$choice" -eq 1 ]; then
                # Check the value of VGPU_SUPPORT
                if [ "$VGPU_SUPPORT" = "No" ]; then
                    echo -e "${RED}[!]${NC} You don't have a vGPU capable card in your system"
                    echo "Exiting  script."
                    exit 1
                elif [ "$VGPU_SUPPORT" = "Yes" ]; then
                    # Download vgpu-proxmox
                    rm -rf $VGPU_DIR/vgpu-proxmox 2>/dev/null 
                    #echo "downloading vgpu-proxmox"
                    run_command "Downloading vgpu-proxmox" "info" "git clone https://gitlab.com/polloloco/vgpu-proxmox.git $VGPU_DIR/vgpu-proxmox"

                    # Download vgpu_unlock-rs
                    mkdir -p /opt
                    cd /opt
                    rm -rf vgpu_unlock-rs 2>/dev/null 
                    #echo "downloading vgpu_unlock-rs"
                    run_command "Downloading vgpu_unlock-rs" "info" "git clone https://github.com/mbilker/vgpu_unlock-rs.git"

                    # Download and source Rust
                    #echo "downloading rust"
                    run_command "Downloading Rust" "info" "curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal"
                    if [ -f "$HOME/.cargo/env" ]; then
                        # shellcheck disable=SC1091
                        source "$HOME/.cargo/env"
                    fi
                    export PATH="$HOME/.cargo/bin:$PATH"

                    # Building vgpu_unlock-rs
                    cd vgpu_unlock-rs/
                    #echo "building vgpu_unlock-rs"
                    run_command "Building vgpu_unlock-rs" "info" "cargo build --release"
                    cd "$VGPU_DIR"

                    # Creating vgpu directory and toml file
                    echo -e "${GREEN}[+]${NC} Creating vGPU files and directories"
                    mkdir -p /etc/vgpu_unlock
                    touch /etc/vgpu_unlock/profile_override.toml

                    # Creating systemd folders
                    echo -e "${GREEN}[+]${NC} Creating systemd folders"
                    mkdir -p /etc/systemd/system/{nvidia-vgpud.service.d,nvidia-vgpu-mgr.service.d}

                    # Adding vgpu_unlock-rs library
                    echo -e "${GREEN}[+]${NC} Adding vgpu_unlock-rs library"
                    echo -e "[Service]\nEnvironment=LD_PRELOAD=/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so" > /etc/systemd/system/nvidia-vgpud.service.d/vgpu_unlock.conf
                    echo -e "[Service]\nEnvironment=LD_PRELOAD=/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so" > /etc/systemd/system/nvidia-vgpu-mgr.service.d/vgpu_unlock.conf
                
                    # Systemctl
                    run_command "Systemctl daemon-reload" "info" "systemctl daemon-reload"
                    echo -e "${YELLOW}[-]${NC} NVIDIA services will be enabled after the driver installation completes."

                    # vGPU unlock patches target kernel <= 6.16; 6.17+ / 7.x need 6.14 (v1.75 behavior)
                    if is_kernel_617_or_higher; then
                        local target_k; target_k=$(discover_target_kernel_version)
                        echo -e "${YELLOW}[-]${NC} Current kernel $(uname -r) is 6.17 or higher (includes 7.x)."
                        echo -e "${YELLOW}[-]${NC} vGPU 16.x–19.x unlock builds require kernel 6.14.x for DKMS compilation."
                        
                        echo ""
                        read -p "$(echo -e "${BLUE}[?]${NC} Do you want to downgrade and pin kernel to ${target_k} now? (y/n): ")" downgrade_choice
                        echo ""
                        
                        if [ "$downgrade_choice" = "y" ] || [ "$downgrade_choice" = "Y" ]; then
                            echo -e "${GREEN}[+]${NC} Downgrading and pinning..."
                            if ! downgrade_kernel_for_vgpu; then
                                echo -e "${RED}[!]${NC} Kernel downgrade failed. Install manually or use native vGPU driver 20.x on kernel 7.x."
                                exit 1
                            fi
                        else
                            echo -e "${RED}[!]${NC} You chose not to downgrade the kernel. vGPU unlock cannot function on kernel $(uname -r)."
                            echo -e "${YELLOW}[-]${NC} Exiting."
                            exit 1
                        fi
                    fi

                    update_grub

                elif [ "$VGPU_SUPPORT" = "Native" ]; then
                    # Execute steps for "Native" VGPU_SUPPORT
                    update_grub
                fi
            # Removing previous installations of vgpu
            elif [ "$choice" -eq 2 ]; then
                # Removing previous Nvidia driver
                run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s"
				# Removing previous vgpu_unlock-rs
                run_command "Removing previous vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs/ 2>/dev/null"
                # Removing vgpu-proxmox
                run_command "Removing vgpu-proxmox" "notification" "rm -rf $VGPU_DIR/vgpu-proxmox 2>/dev/null"
            fi

            # Check if the specified lines are present in /etc/modules
            if grep -Fxq "vfio" /etc/modules && grep -Fxq "vfio_iommu_type1" /etc/modules && grep -Fxq "vfio_pci" /etc/modules && grep -Fxq "vfio_virqfd" /etc/modules; then
                echo -e "${YELLOW}[-]${NC} Kernel modules already present"
            else
                echo -e "${GREEN}[+]${NC} Enabling kernel modules"
                echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" >> /etc/modules
            fi

            # Check if /etc/modprobe.d/blacklist.conf exists
            if [ -f "/etc/modprobe.d/blacklist.conf" ]; then
                # Check if "blacklist nouveau" is present in /etc/modprobe.d/blacklist.conf
                if grep -q "blacklist nouveau" /etc/modprobe.d/blacklist.conf; then
                    echo -e "${YELLOW}[-]${NC} Nouveau already blacklisted"
                else
                    echo -e "${GREEN}[+]${NC} Blacklisting nouveau"
                    echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf
                fi
            else
                echo -e "${GREEN}[+]${NC} Blacklisting nouveau"
                echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf
            fi

            #echo "updating initramfs"
            run_command "Updating initramfs" "info" "update-initramfs -u -k all"

            echo ""
            echo "Step 1 completed. Reboot your machine to resume the installation."
            echo ""
            if [ "${KERNEL_DOWNGRADED:-0}" = "1" ]; then
                local target_k; target_k=$(discover_target_kernel_version)
                echo -e "${YELLOW}[!]${NC} Kernel has been downgraded to ${target_k} for vGPU patch compatibility."
                echo -e "${YELLOW}[!]${NC} Please reboot now to boot into the downgraded kernel."
                echo ""
            fi
            echo "After reboot, run the script again to install the Nvidia driver."
            echo ""

            read -p "$(echo -e "${BLUE}[?]${NC} Reboot your machine now? (y/n): ")" reboot_choice
            if [ "$reboot_choice" = "y" ]; then
                set_config_value "STEP" "2"
                set_config_value "VGPU_SUPPORT" "$VGPU_SUPPORT"
                set_config_value "DRIVER_VERSION" "$DRIVER_VERSION"
                reboot
            else
                echo "Exiting script. Remember to reboot your machine later."
                set_config_value "STEP" "2"
                set_config_value "VGPU_SUPPORT" "$VGPU_SUPPORT"
                set_config_value "DRIVER_VERSION" "$DRIVER_VERSION"
                exit 0
            fi
            ;;

        3)           
            echo ""
            echo "Clean vGPU installation"
            echo ""
            echo -e "${CYAN}[i]${NC} This will help resolve issues like improperly configured kernel sources (Issue #13)"
            echo ""

            # Removing previous Nvidia driver
            if confirm_action "Do you want to remove the previous Nvidia driver?"; then
                if command -v nvidia-uninstall >/dev/null 2>&1; then
                    run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s" || {
                        echo -e "${YELLOW}[-]${NC} Driver uninstall had issues, attempting DKMS cleanup..."
                        dkms status | grep nvidia | while read -r line; do
                            module=$(echo "$line" | cut -d',' -f1)
                            version=$(echo "$line" | cut -d',' -f2 | tr -d ' ')
                            echo -e "${CYAN}[i]${NC} Removing DKMS module: $module/$version"
                            dkms remove "$module/$version" --all 2>/dev/null || true
                        done
                    }
                else
                    echo -e "${YELLOW}[-]${NC} nvidia-uninstall not found, skipping driver removal"
                fi
            fi

            # Clean up kernel sources (Issue #13)
            if confirm_action "Do you want to clean up kernel sources and headers?"; then
                echo -e "${CYAN}[i]${NC} Cleaning up old kernel sources..."
                run_command "Cleaning kernel sources" "notification" "apt autoremove -y" || true
                run_command "Reinstalling current kernel headers" "notification" "apt install --reinstall -y proxmox-headers-$(uname -r)" || true
            fi

            # Removing previous vgpu_unlock-rs
            if confirm_action "Do you want to remove vgpu_unlock-rs?"; then
                run_command "Removing vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs"
                # Also remove systemd overrides
                rm -f /etc/systemd/system/nvidia-vgpud.service.d/vgpu_unlock.conf 2>/dev/null || true
                rm -f /etc/systemd/system/nvidia-vgpu-mgr.service.d/vgpu_unlock.conf 2>/dev/null || true
                systemctl daemon-reload
            fi

            # Removing vgpu-proxmox
            if confirm_action "Do you want to remove vgpu-proxmox?"; then
                run_command "Removing vgpu-proxmox" "notification" "rm -rf $VGPU_DIR/vgpu-proxmox"
            fi

            # Removing FastAPI-DLS
            if confirm_action "Do you want to remove vGPU licensing?"; then
                if command -v docker >/dev/null 2>&1; then
                    run_command "Removing FastAPI-DLS" "notification" "docker rm -f -v wvthoog-fastapi-dls" || true
                else
                    echo -e "${YELLOW}[-]${NC} Docker not found, skipping FastAPI-DLS removal"
                fi
            fi

            echo ""
            echo -e "${GREEN}[+]${NC} Cleanup completed."
            echo -e "${YELLOW}[!]${NC} Reboot the Proxmox host to finish cleaning up the vGPU stack before reinstalling."
            echo -e "${CYAN}[i]${NC} After reboot, kernel modules will be fully unloaded and you can reinstall cleanly."
            echo ""

            exit 0
            ;;
        4)  
            echo ""
            echo "This will download the Nvidia vGPU drivers"         
            echo ""
            echo -e "${GREEN}[+]${NC} Downloading Nvidia vGPU drivers"

            load_patch_overrides

            if ! select_driver_branch true; then
                exit 1
            fi

            if [ -z "$driver_url" ] || [ "$driver_url" = "auto" ]; then
                log_info "Auto-discovering host driver from alist..."
                discovered_url=""
                discovered_url=$(resolve_host_driver_url "$driver_version" "$driver_url" 2>/dev/null) || discovered_url=""
                if [ -n "$discovered_url" ]; then
                    driver_url="$discovered_url"
                    log_info "Found host driver: ${driver_url%|zip}"
                fi
            fi

            if [ -z "$driver_url" ] || [ "$driver_url" = "auto" ]; then
                echo -e "${RED}[!]${NC} No download URL registered for $driver_filename."
                echo -e "${YELLOW}[-]${NC} Auto-discovery from alist failed for vGPU ${driver_version}. Supply the driver manually using --url or --file parameters."
                exit 1
            fi

            echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"

            DRIVER_VERSION="$driver_version"

            # Check if driver file already exists and validate MD5
            if [ -e "$driver_filename" ]; then
                if [ -n "$md5" ]; then
                    current_md5=$(md5sum "$driver_filename" | awk '{print $1}')
                    if [ "$current_md5" == "$md5" ]; then
                        echo -e "${GREEN}[+]${NC} Driver file $driver_filename already exists and MD5 checksum matches. Skipping download."
                    else
                        echo -e "${YELLOW}[-]${NC} Driver file $driver_filename exists but MD5 checksum does not match."
                        echo -e "${YELLOW}[-]${NC} Expected MD5: $md5"
                        echo -e "${YELLOW}[-]${NC} Current MD5: $current_md5"
                        echo -e "${YELLOW}[-]${NC} Re-downloading the file..."
                        
                        # Backup old file and download new one
                        mv "$driver_filename" "$driver_filename.bak"
                        echo -e "${YELLOW}[-]${NC} Moved $driver_filename to $driver_filename.bak"
                        
                        # Download the driver
                        if [[ "$driver_url" == *"|zip" ]] || [[ "$driver_url" == https://alist.homelabproject.cc/* ]]; then
                            install_host_driver_download "$driver_url" "$driver_filename" "." || exit 1
                        else
                            download_driver_file "$driver_url" "$driver_filename"
                        fi
                    fi
                else
                    echo -e "${YELLOW}[-]${NC} Driver file $driver_filename exists but no MD5 checksum available for validation."
                    echo -e "${YELLOW}[-]${NC} Using existing file. If you want to re-download, please remove the file manually."
                fi
            else
                # File does not exist, proceed with download
                echo -e "${GREEN}[+]${NC} Downloading vGPU $driver_filename host driver"
                if [[ "$driver_url" == *"|zip" ]] || [[ "$driver_url" == https://alist.homelabproject.cc/* ]]; then
                    install_host_driver_download "$driver_url" "$driver_filename" "." || exit 1
                else
                    download_driver_file "$driver_url" "$driver_filename"
                fi
            fi

            # MD5 validation after download (if file was downloaded or needs validation)
            if [ -n "$md5" ] && [ ! -e "$driver_filename.bak" ] || [ -e "$driver_filename" ]; then
                downloaded_md5=$(md5sum "$driver_filename" | awk '{print $1}')
                if [ "$downloaded_md5" != "$md5" ]; then
                    echo -e "${RED}[!]${NC} MD5 checksum mismatch. Downloaded file is corrupt."
                    echo ""
                    read -p "$(echo -e "${BLUE}[?]${NC} Do you want to continue? (y/n): ")" choice
                    echo ""
                    if [ "$choice" != "y" ]; then
                        echo "Exiting script."
                        exit 1
                    fi
                else
                    echo -e "${GREEN}[+]${NC} MD5 checksum matched. Downloaded file is valid."
                fi
            fi

            prompt_guest_driver_downloads "$driver_version" "$driver_filename"

            exit 0
            ;;
        5)
            if ! download_guest_drivers_interactive; then
                exit 1
            fi
            exit 0
            ;;
        6)
            echo ""
            echo "This will setup a FastAPI-DLS Nvidia vGPU licensing server on this Proxmox server"
            echo ""

            configure_fastapi_dls

            exit 0
            ;;
        7)
            echo ""
            echo "Exiting script."
            exit 0
            ;;
        *)
            echo ""
            echo "Invalid choice. Please enter 1, 2, 3, 4, 5, 6 or 7."
            echo ;;
    esac
    ;;
    2)
        perform_step_two
        ;;
    *)
        echo "Invalid installation step. Please check the script."
        exit 1
        ;;
esac