#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"

# Variables
LOG_FILE="$SCRIPT_DIR/debug.log"
DEBUG=false
STEP="${STEP:-1}"
URL="${URL:-}"
FILE="${FILE:-}"
DRIVER_VERSION="${DRIVER_VERSION:-}"
SCRIPT_VERSION=1.6
VGPU_DIR="$SCRIPT_DIR"
VGPU_SUPPORT="${VGPU_SUPPORT:-}"
VGPU_HELPER_STATUS="${VGPU_HELPER_STATUS:-}"
SECURE_BOOT_DIR="$SCRIPT_DIR/secure-boot"
SECURE_BOOT_KEY="$SECURE_BOOT_DIR/module-signing.key"
SECURE_BOOT_CERT="$SECURE_BOOT_DIR/module-signing.crt"
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
}

# Driver registry (URLs requiring authenticated access are left empty for manual supply)
register_driver "19.2" "19.2 (580.95.02)" "NVIDIA-Linux-x86_64-580.95.02-vgpu-kvm.run" "" "" "" "manual download"
register_driver "19.1" "19.1 (580.82.02)" "NVIDIA-Linux-x86_64-580.82.02-vgpu-kvm.run" "https://alist.homelabproject.cc/d/foxipan/vGPU/19.1/NVIDIA-GRID-Linux-KVM-580.82.02-580.82.07-581.15/Host_Drivers/NVIDIA-Linux-x86_64-580.82.02-vgpu-kvm.run" "fe3ecc481c3332422f33b6fab1d51a36" "" "community mirror"
register_driver "19.0" "19.0 (580.65.05)" "NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run" "https://alist.homelabproject.cc/d/foxipan/vGPU/19.0/NVIDIA-GRID-Linux-KVM-580.65.05-580.65.06-580.88/Host_Drivers/NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run" "c75f6465338f0178fcbffe654b5e2086" "" "community mirror"
register_driver "18.4" "18.4 (570.172.07)" "NVIDIA-Linux-x86_64-570.172.07-vgpu-kvm.run" "https://alist.homelabproject.cc/d/foxipan/vGPU/18.4/NVIDIA-GRID-Linux-KVM-570.172.07-570.172.08-573.48/Host_Drivers/NVIDIA-Linux-x86_64-570.172.07-vgpu-kvm.run" "5b370637f2aaf2f1828027aeaabafff9" "" "community mirror"
register_driver "18.3" "18.3 (570.158.02)" "NVIDIA-Linux-x86_64-570.158.02-vgpu-kvm.run" "https://alist.homelabproject.cc/d/foxipan/vGPU/18.3/NVIDIA-GRID-Linux-KVM-570.158.02-570.158.01-573.39/Host_Drivers/NVIDIA-Linux-x86_64-570.158.02-vgpu-kvm.run" "c68a523bb835ea753bab2c1e9055d610" "" "community mirror"
register_driver "18.2" "18.2 (570.148.06)" "NVIDIA-Linux-x86_64-570.148.06-vgpu-kvm.run" "" "" "" "manual download"
register_driver "18.1" "18.1 (570.133.10)" "NVIDIA-Linux-x86_64-570.133.10-vgpu-kvm.run" "https://mega.nz/file/0YpHTAxJ#_XMpdJ68w3sM72p87kYSiEQXFA5BbFZl_xvF_XZSd4k" "f435eacdbe3c8002ccad14bd62c9bd2d" "" "mega.nz mirror"
register_driver "18.0" "18.0 (570.124.03)" "NVIDIA-Linux-x86_64-570.124.03-vgpu-kvm.run" "https://mega.nz/file/RUxgjLRZ#aDy-DWKJXg-rTrisraE2MKrKbl1jbX4-13L0W32fiHQ" "1804b889e27b7f868afb5521d871b095" "" "mega.nz mirror"
register_driver "17.6" "17.6 (550.163.02)" "NVIDIA-Linux-x86_64-550.163.02-vgpu-kvm.run" "https://mega.nz/file/NAYAGYpL#en-eYfid3GYmHkGVCAUagc6P2rbdw1Y2E9-7hOW19m8" "093036d83baf879a4bb667b484597789" "" "mega.nz mirror"
register_driver "17.5" "17.5 (550.144.02)" "NVIDIA-Linux-x86_64-550.144.02-vgpu-kvm.run" "https://mega.nz/file/sYQ10b4b#hfGVeRog1pmNyx63N_I-siFENBWZj3w_ZQDsjW4PzW4" "37016ba868a0b4390c38aebbacfba09e" "" "mega.nz mirror"
register_driver "17.4" "17.4 (550.127.06)" "NVIDIA-Linux-x86_64-550.127.06-vgpu-kvm.run" "https://mega.nz/file/VJIVTBiB#nFOU3zkoWyk4Dq1eW-y2dWUQ-YuvxVh_PYXT3bzdfYE" "400b1b2841908ea36fd8f7fdbec18401" "" "mega.nz mirror"
register_driver "17.3" "17.3 (550.90.05)" "NVIDIA-Linux-x86_64-550.90.05-vgpu-kvm.run" "https://mega.nz/file/1dYWAaDJ#9lGnw1CccnIcH7n7UAZ5nfGt3yUXcen72nOUiztw-RU" "a3cddad85eee74dc15dbadcbe30dcf3a" "" "mega.nz mirror"
register_driver "17.1" "17.1 (550.54.16)" "NVIDIA-Linux-x86_64-550.54.16-vgpu-kvm.run" "https://mega.nz/file/sAYwDS7S#eyIeE_GYk_A0hwhayj3nOpcybLV_KAokJwXifDMQtPQ" "4d78514599c16302a0111d355dbf11e3" "" "mega.nz mirror"
register_driver "17.0" "17.0 (550.54.10)" "NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" "https://mega.nz/file/JjtyXRiC#cTIIvOIxu8vf-RdhaJMGZAwSgYmqcVEKNNnRRJTwDFI" "5f5e312cbd5bb64946e2a1328a98c08d" "" "mega.nz mirror"
register_driver "16.9" "16.9 (535.230.02)" "NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run" "https://mega.nz/file/JFYDETBa#IqaXaoqrPAmSZSjbAXCWvHtiUxU0n9O7RJF8Xu5HXIo" "3f6412723880aa5720b44cf0a9a13009" "" "mega.nz mirror"
register_driver "16.8" "16.8 (535.216.01)" "NVIDIA-Linux-x86_64-535.216.01-vgpu-kvm.run" "https://mega.nz/file/gJBGSZxK#cqyK3KCsfB0mYL8QCsV6P5C9ABmUcV7bQgE9DQ4_8O4" "18627628e749f893cd2c3635452006a46" "" "mega.nz mirror"
register_driver "16.7" "16.7 (535.183.04)" "NVIDIA-Linux-x86_64-535.183.04-vgpu-kvm.run" "https://mega.nz/file/gIwxGSyJ#xDcaxkymYcNFUTzwZ_m1HWcTgQrMSofJLPYMU-YGLMo" "68961f01a2332b613fe518afd4bfbfb2" "" "mega.nz mirror"
register_driver "16.5" "16.5 (535.161.05)" "NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" "https://mega.nz/file/RvsyyBaB#7fe_caaJkBHYC6rgFKtiZdZKkAvp7GNjCSa8ufzkG20" "bad6e09aeb58942750479f091bb9c4b6" "" "mega.nz mirror"
register_driver "16.4" "16.4 (535.161.05)" "NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" "https://mega.nz/file/RvsyyBaB#7fe_caaJkBHYC6rgFKtiZdZKkAvp7GNjCSa8ufzkG20" "bad6e09aeb58942750479f091bb9c4b6" "" "mega.nz mirror"
register_driver "16.3" "16.3 (535.154.02)" "NVIDIA-Linux-x86_64-535.154.02-vgpu-kvm.run" "" "" "" "manual download"
register_driver "16.2" "16.2 (535.129.03)" "NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run" "https://mega.nz/file/EyEXTbbY#J9FUQL1Mo4ZpNyDijStEH4bWn3AKwnSAgJEZcxUnOiQ" "0048208a62bacd2a7dd12fa736aa5cbb" "" "mega.nz mirror"
register_driver "16.1" "16.1 (535.104.06)" "NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" "https://mega.nz/file/wy1WVCaZ#Yq2Pz_UOfydHy8nC_X_nloR4NIFC1iZFHqJN0EiAicU" "1020ad5b89fa0570c27786128385ca48" "" "mega.nz mirror"
register_driver "16.0" "16.0 (535.54.06)" "NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" "https://mega.nz/file/xrNCCAaT#UuUjqRap6urvX4KA1m8-wMTCW5ZwuWKUj6zAB4-NPSo" "b892f75f8522264bc176f5a555acb176" "" "mega.nz mirror"

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
        grep -v "^${key}=" "$CONFIG_FILE" > "$tmp"
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
        grep -v "^${key}=" "$CONFIG_FILE" > "$tmp"
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

detect_os_codename() {
    local codename=""

    if [ -r /etc/os-release ]; then
        codename=$(awk -F= '$1 == "VERSION_CODENAME" {print $2}' /etc/os-release | tr -d '"')
    fi

    if [ -z "$codename" ]; then
        case "$major_version" in
            9) codename="trixie" ;;
            8) codename="bookworm" ;;
            7) codename="bullseye" ;;
        esac
    fi

    echo "$codename"
}

configure_proxmox_repos() {
    local codename
    codename=$(detect_os_codename)

    if [ -z "$codename" ]; then
        echo -e "${RED}[!]${NC} Unable to determine Debian codename for this Proxmox host."
        exit 1
    fi

    local repo_line="deb http://download.proxmox.com/debian/pve ${codename} pve-no-subscription"
    echo -e "${GREEN}[+]${NC} Configuring Proxmox no-subscription repository: ${repo_line}"
    printf '%s\n' "$repo_line" > /etc/apt/sources.list.d/pve-no-subscription.list

    if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
        echo -e "${YELLOW}[-]${NC} Disabling enterprise repository entries in pve-enterprise.list"
        sed -i 's/^[[:space:]]*deb/# &/' /etc/apt/sources.list.d/pve-enterprise.list
    fi

    if [ -f /etc/apt/sources.list.d/ceph.list ]; then
        echo -e "${YELLOW}[-]${NC} Disabling enterprise Ceph repository entries in ceph.list"
        sed -i 's/^[[:space:]]*deb/# &/' /etc/apt/sources.list.d/ceph.list
    fi

    local ceph_line=""
    case "$codename" in
        bullseye)
            ceph_line="deb http://download.proxmox.com/debian/ceph-pacific bullseye no-subscription"
            ;;
        bookworm)
            ceph_line="deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription"
            ;;
        trixie)
            ceph_line="deb http://download.proxmox.com/debian/ceph-reef trixie no-subscription"
            ;;
    esac

    if [ -n "$ceph_line" ]; then
        echo -e "${GREEN}[+]${NC} Configuring Ceph no-subscription repository: ${ceph_line}"
        printf '%s\n' "$ceph_line" > /etc/apt/sources.list.d/ceph-no-subscription.list
    else
        echo -e "${YELLOW}[-]${NC} No Ceph no-subscription repository configured for codename ${codename}."
    fi
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

secure_boot_enabled() {
    if ! command -v mokutil >/dev/null 2>&1; then
        return 1
    fi

    mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"
}

secure_boot_key_enrolled() {
    if ! command -v mokutil >/dev/null 2>&1; then
        return 0
    fi

    if [ ! -f "$SECURE_BOOT_CERT" ]; then
        return 1
    fi

    local fingerprint
    fingerprint=$(openssl x509 -in "$SECURE_BOOT_CERT" -fingerprint -noout 2>/dev/null | cut -d'=' -f2 | tr -d ':')
    if [ -z "$fingerprint" ]; then
        return 1
    fi

    mokutil --list-enrolled 2>/dev/null | tr -d ':' | tr '[:lower:]' '[:upper:]' | grep -q "$fingerprint"
}

generate_secure_boot_keys() {
    mkdir -p "$SECURE_BOOT_DIR"

    if [ ! -f "$SECURE_BOOT_KEY" ] || [ ! -f "$SECURE_BOOT_CERT" ]; then
        echo -e "${GREEN}[+]${NC} Generating Secure Boot module signing keys in $SECURE_BOOT_DIR"
        openssl req -new -x509 -newkey rsa:4096 -sha256 -days 3650 \
            -nodes -out "$SECURE_BOOT_CERT" -keyout "$SECURE_BOOT_KEY" \
            -subj "/CN=Proxmox vGPU Module Signing/" >/dev/null 2>&1
        chmod 600 "$SECURE_BOOT_KEY"
        chmod 644 "$SECURE_BOOT_CERT"
    fi
}

prepare_secure_boot_enrollment() {
    if ! command -v mokutil >/dev/null 2>&1; then
        echo -e "${RED}[!]${NC} mokutil is required to manage Secure Boot keys. Please install mokutil and rerun the script."
        exit 1
    fi

    generate_secure_boot_keys

    echo -e "${YELLOW}[-]${NC} Secure Boot is enabled. The NVIDIA modules must be signed."
    echo -e "${YELLOW}[-]${NC} You will now be prompted to enter a one-time password for enrolling the signing certificate."
    echo -e "${YELLOW}[-]${NC} Record this password; you must confirm it in the firmware MOK manager on the next reboot."

    mokutil --import "$SECURE_BOOT_CERT"

    echo -e "${GREEN}[+]${NC} Enrollment request queued. Reboot the host and complete the MOK enrollment when prompted."
    set_config_value "SECURE_BOOT_PENDING" "1"
    set_config_value "SECURE_BOOT_READY" "0"
    echo -e "${YELLOW}[-]${NC} After the reboot and enrollment, rerun this installer to continue."
    exit 0
}

secure_boot_precheck() {
    if ! secure_boot_enabled; then
        remove_config_key "SECURE_BOOT_PENDING"
        remove_config_key "SECURE_BOOT_READY"
        return
    fi

    echo -e "${GREEN}[+]${NC} Secure Boot detected."

    if secure_boot_key_enrolled; then
        echo -e "${GREEN}[+]${NC} Secure Boot signing certificate already enrolled."
        set_config_value "SECURE_BOOT_READY" "1"
        set_config_value "SECURE_BOOT_PENDING" "0"
        return
    fi

    if [[ "${SECURE_BOOT_PENDING}" == "1" ]]; then
        echo -e "${YELLOW}[-]${NC} Secure Boot enrollment still pending."
        echo -e "${YELLOW}[-]${NC} Please reboot, approve the MOK enrollment, then rerun this installer."
        exit 0
    fi

    prepare_secure_boot_enrollment
}

build_secure_boot_flags() {
    if secure_boot_enabled && [[ "${SECURE_BOOT_READY}" == "1" ]] && [ -f "$SECURE_BOOT_KEY" ] && [ -f "$SECURE_BOOT_CERT" ]; then
        printf -- "--module-signing-secret-key=%s --module-signing-public-key=%s" "$SECURE_BOOT_KEY" "$SECURE_BOOT_CERT"
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
NC='\033[0m' # No color

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

SECURE_BOOT_PENDING="${SECURE_BOOT_PENDING:-0}"
SECURE_BOOT_READY="${SECURE_BOOT_READY:-0}"

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
        local url="${DRIVER_URLS[$branch]}"
        if [ "$require_downloadable" = "true" ] && [ -z "$url" ]; then
            continue
        fi

        local label="${DRIVER_LABELS[$branch]}"
        local note="${DRIVER_NOTES[$branch]}"
        printf "%d: %s" "$index" "$label"
        if [ -n "$note" ]; then
            printf " [%s]" "$note"
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
    read -p "Enter your choice: " driver_choice

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
    read -p "$(echo -e "${BLUE}[?]${NC} Do you want to license the vGPU? (y/n): ")" choice
    echo ""

    if [ "$choice" = "y" ]; then
        # Installing Docker-CE
        run_command "Installing Docker-CE" "info" "apt install ca-certificates curl -y; \
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; \
        chmod a+r /etc/apt/keyrings/docker.asc; \
        echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null; \
        apt update; \
        apt install docker-ce docker-compose -y"

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
    restart: always
    container_name: wvthoog-fastapi-dls
    environment:
      <<: *dls-variables
    ports:
      - "$portnumber:443"
    volumes:
      - /opt/docker/fastapi-dls/cert:/app/cert
      - dls-db:/app/database
    logging:  # optional, for those who do not need logs
      driver: "json-file"
      options:
        max-file: "5"
        max-size: "10m"

volumes:
  dls-db:
EOF
        # Issue docker-compose
        run_command "Running Docker Compose" "info" "docker-compose -f \"$fastapi_dir/docker-compose.yml\" up -d"

        # Create directory where license script (Windows/Linux are stored)
        mkdir -p $VGPU_DIR/licenses

        echo -e "${GREEN}[+]${NC} Generate FastAPI-DLS Windows/Linux executables"
        # Create .sh file for Linux
        cat > "$VGPU_DIR/licenses/license_linux.sh" <<EOF
#!/bin/bash

curl --insecure -L -X GET "https://$host_address:$portnumber/-/client-token" -o /etc/nvidia/ClientConfigToken/client_configuration_token_\$(date '+%d-%m-%Y-%H-%M-%S').tok
service nvidia-gridd restart
nvidia-smi -q | grep "License"
EOF

        # Create .ps1 file for Windows
        cat > "$VGPU_DIR/licenses/license_windows.ps1" <<EOF
curl.exe --insecure -L -X GET "https://$host_address:$portnumber/-/client-token" -o "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_\$(Get-Date -f 'dd-MM-yy-hh-mm-ss').tok"
Restart-Service NVDisplay.ContainerLocalSystem
& 'nvidia-smi' -q  | Select-String "License"
EOF

        echo -e "${GREEN}[+]${NC} license_windows.ps1 and license_linux.sh created and stored in: $VGPU_DIR/licenses"
        echo -e "${YELLOW}[-]${NC} Copy these files to your Windows or Linux VM's and execute"
        echo ""
        echo "Exiting script."
        echo ""
        exit 0

        # Put the stuff below in here
    elif [ "$choice" = "n" ]; then
        echo ""
        echo "Exiting script."
        echo "Install the Docker container in a VM/LXC yourself."
        echo "By using this guide: https://git.collinwebdesigns.de/oscar.krause/fastapi-dls#docker"
        echo ""
        exit 0

        # Write instruction on how to setup Docker in a VM/LXC container
        # Echo .yml script and docker-compose instructions
    else
        echo -e "${RED}[!]${NC} Invalid choice. Please enter (y/n)."
        exit 1
    fi
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
echo -e "${BLUE}by wvthoog.nl${NC}"
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
    echo "5) License vGPU"
    echo "6) Exit"
    echo ""
    read -p "Enter your choice: " choice

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

            if command -v pve-nvidia-vgpu-helper >/dev/null 2>&1 && [ "${VGPU_HELPER_STATUS}" != "done" ]; then
                echo -e "${GREEN}[+]${NC} Detected pve-nvidia-vgpu-helper."
                echo -e "${YELLOW}[-]${NC} This tool prepares headers, DKMS dependencies and kernel settings for vGPU."
                read -p "$(echo -e "${BLUE}[?]${NC} Run 'pve-nvidia-vgpu-helper setup' now? (y/n): ")" helper_choice
                if [ "$helper_choice" = "y" ]; then
                    if run_command "Running pve-nvidia-vgpu-helper setup" "info" "pve-nvidia-vgpu-helper setup"; then
                        set_config_value "VGPU_HELPER_STATUS" "done"
                        VGPU_HELPER_STATUS="done"
                    else
                        echo -e "${RED}[!]${NC} pve-nvidia-vgpu-helper setup reported an error; review the log and rerun if needed."
                    fi
                else
                    echo -e "${YELLOW}[-]${NC} Skipping helper setup. You can run 'pve-nvidia-vgpu-helper setup' manually later."
                fi
            fi

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

            # Prompt the user for confirmation
            echo ""
            read -p "$(echo -e "${BLUE}[?]${NC} Do you want to proceed with APT Dist-Upgrade ? (y/n): ")" confirmation
            echo ""

            # Check user's choice
            if [ "$confirmation" == "y" ]; then
                #echo "running apt dist-upgrade"
                run_command "Running APT Dist-Upgrade (...this might take some time)" "info" "apt dist-upgrade -y"
            else
                echo -e "${YELLOW}[-]${NC} Skipping APT Dist-Upgrade"
            fi          

            # APT installing packages
            # Ensure required tooling for kernel builds, downloads, and secure boot signing
            run_command "Installing packages" "info" "apt install -y git build-essential dkms mdevctl curl wget unzip jq megatools mokutil"
            ensure_kernel_headers

            # Pinning the kernel
            kernel_version_compare() {
                ver1=$1
                ver2=$2
                printf '%s\n' "$ver1" "$ver2" | sort -V -r | head -n 1
            }

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
            query_gpu_info() {
            local gpu_device_id="$1"
            local query_result=$(sqlite3 gpu_info.db "SELECT * FROM gpu_info WHERE deviceid='$gpu_device_id';")
            echo "$query_result"
            }

            gpu_info=$(lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)')

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
                gpu_devices=$(lspci -nn | grep -Ei '(VGA compatible controller|3D controller).*NVIDIA Corporation')

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
                    update_grub

                elif [ "$VGPU_SUPPORT" = "Native" ]; then
                    # Execute steps for "Native" VGPU_SUPPORT
                    update_grub
                fi
            # Removing previous installations of vgpu
            elif [ "$choice" -eq 2 ]; then
                #echo "removing nvidia driver"
                # Removing previous Nvidia driver
                run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s"
                # Removing previous vgpu_unlock-rs
                run_command "Removing previous vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs/ 2>/dev/null"
                # Removing vgpu-proxmox
                run_command "Removing vgpu-proxmox" "notification" "rm -rf $VGPU_DIR/vgpu-promox 2>/dev/null"
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

            # Function to prompt for user confirmation
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

            # Removing previous Nvidia driver
            if confirm_action "Do you want to remove the previous Nvidia driver?"; then
                #echo "removing previous nvidia driver"
                run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s"
            fi

            # Removing previous vgpu_unlock-rs
            if confirm_action "Do you want to remove vgpu_unlock-rs?"; then
                #echo "removing previous vgpu_unlock-rs"
                run_command "Removing previous vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs"
            fi

            # Removing vgpu-proxmox
            if confirm_action "Do you want to remove vgpu-proxmox?"; then
                #echo "removing vgpu-proxmox"
                run_command "Removing vgpu-proxmox" "notification" "rm -rf $VGPU_DIR/vgpu-promox"
            fi

            # Removing FastAPI-DLS
            if confirm_action "Do you want to remove vGPU licensing?"; then
                run_command "Removing FastAPI-DLS" "notification" "docker rm -f -v wvthoog-fastapi-dls"
            fi
            
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

            if [ -z "$driver_url" ]; then
                echo -e "${RED}[!]${NC} No download URL registered for $driver_filename."
                echo -e "${YELLOW}[-]${NC} Supply the driver manually using --url or --file parameters."
                exit 1
            fi

            echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"

            DRIVER_VERSION="$driver_version"

            if [ -e "$driver_filename" ]; then
                mv "$driver_filename" "$driver_filename.bak"
                echo -e "${YELLOW}[-]${NC} Moved $driver_filename to $driver_filename.bak"
            fi

            download_command=""
            if [[ "$driver_url" == https://mega.nz/* ]]; then
                if command -v megadl >/dev/null 2>&1; then
                    download_command="megadl '$driver_url'"
                else
                    echo -e "${RED}[!]${NC} megadl is required to download from Mega.nz. Install megatools or provide an alternate URL."
                    exit 1
                fi
            else
                if command -v curl >/dev/null 2>&1; then
                    download_command="curl -fSL '$driver_url' -o '$driver_filename'"
                elif command -v wget >/dev/null 2>&1; then
                    download_command="wget -O '$driver_filename' '$driver_url'"
                else
                    echo -e "${RED}[!]${NC} Neither curl nor wget is available for downloading."
                    exit 1
                fi
            fi

            echo -e "${GREEN}[+]${NC} Downloading vGPU $driver_filename host driver"
            if ! eval "$download_command"; then
                echo -e "${RED}[!]${NC} Download failed."
                exit 1
            fi

            if [ -n "$md5" ]; then
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
            else
                echo -e "${YELLOW}[-]${NC} No MD5 checksum available for validation."
            fi

            exit 0
            ;;
        5)  
            echo ""
            echo "This will setup a FastAPI-DLS Nvidia vGPU licensing server on this Proxmox server"         
            echo ""

            configure_fastapi_dls
            
            exit 0
            ;;
        6)
            echo ""
            echo "Exiting script."
            exit 0
            ;;
        *)
            echo ""
            echo "Invalid choice. Please enter 1, 2, 3, 4, 5 or 6."
            echo ""
            ;;
        esac
    ;;
    2)
        # Step 2: Commands for the second reboot of a new installation or upgrade
        echo ""
        echo "You are currently at step ${STEP} of the installation process"
        echo ""
        echo "Proceeding with the installation"
        echo ""

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
                echo -e "GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt""
                echo ""
            elif [ "$vendor_id" = "GenuineIntel" ]; then
                echo -e "${RED}[!]${NC} Intel IOMMU Disabled"
                echo -e ""
                echo -e "Please make sure you have VT-d enabled in the BIOS"
                echo -e "and make sure that this line is present in /etc/default/grub"
                echo -e "GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt""
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
            
            # Download the file using curl
            run_command "Downloading $driver_filename" "info" "curl -s -o $driver_filename -L $URL"
            
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

            contains_version() {
                local version="$1"
                if [[ "$DRIVER_VERSION" == *"$version"* ]]; then
                    return 0
                else
                    return 1
                fi
            }

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

            if [ -z "$URL" ] && [ -z "$driver_url" ]; then
                echo -e "${RED}[!]${NC} No download URL registered for $driver_filename. Provide the file manually or use --url."
                exit 1
            fi

            if [ -z "$URL" ]; then
                if [ -e "$driver_filename" ]; then
                    mv "$driver_filename" "$driver_filename.bak"
                    echo -e "${YELLOW}[-]${NC} Moved $driver_filename to $driver_filename.bak"
                fi

                download_command=""
                if [[ "$driver_url" == https://mega.nz/* ]]; then
                    if command -v megadl >/dev/null 2>&1; then
                        download_command="megadl '$driver_url'"
                    else
                        echo -e "${RED}[!]${NC} megadl is required to download from Mega.nz. Install megatools or provide an alternate URL."
                        exit 1
                    fi
                else
                    if command -v curl >/dev/null 2>&1; then
                        download_command="curl -fSL '$driver_url' -o '$driver_filename'"
                    elif command -v wget >/dev/null 2>&1; then
                        download_command="wget -O '$driver_filename' '$driver_url'"
                    else
                        echo -e "${RED}[!]${NC} Neither curl nor wget is available for downloading."
                        exit 1
                    fi
                fi

                echo -e "${GREEN}[+]${NC} Downloading vGPU $driver_filename host driver"
                if ! eval "$download_command"; then
                    echo -e "${RED}[!]${NC} Download failed."
                    exit 1
                fi

                if [ -n "$md5" ]; then
                    downloaded_md5=$(md5sum "$driver_filename" | awk '{print $1}')
                    if [ "$downloaded_md5" != "$md5" ]; then
                        echo -e "${RED}[!]${NC}  MD5 checksum mismatch. Downloaded file is corrupt."
                        echo ""
                        read -p "$(echo -e "${BLUE}[?]${NC}Do you want to continue? (y/n): ")" choice
                        echo ""
                        if [ "$choice" != "y" ]; then
                            echo "Exiting script."
                            exit 1
                        fi
                    else
                        echo -e "${GREEN}[+]${NC} MD5 checksum matched. Downloaded file is valid."
                    fi
                else
                    echo -e "${YELLOW}[-]${NC} No MD5 checksum available for validation."
                fi
            fi
        fi

        # Make driver executable
        chmod +x "$driver_filename"

        secure_boot_flags=$(build_secure_boot_flags)
        if [ -n "$secure_boot_flags" ]; then
            echo -e "${GREEN}[+]${NC} Secure Boot signing parameters will be applied during driver installation."
        fi

        if version_ge "$driver_version" "18.0"; then
            install_flags="--dkms -s"
        else
            install_flags="--dkms -m=kernel -s"
        fi
        if [ -n "$secure_boot_flags" ]; then
            install_flags="$install_flags $secure_boot_flags"
        fi

        # Patch and install the driver only if vGPU is not native
        if [ "$VGPU_SUPPORT" = "Yes" ]; then
            if [ -z "$driver_patch" ]; then
                echo -e "${RED}[!]${NC} Patch metadata missing for driver $driver_filename. Unable to continue unlock-based installation."
                exit 1
            fi
            # Add custom to original filename
            custom_filename="${driver_filename%.run}-custom.run"

            # Check if $custom_filename exists
            if [ -e "$custom_filename" ]; then
                mv "$custom_filename" "$custom_filename.bak"
                echo -e "${YELLOW}[-]${NC} Moved $custom_filename to $custom_filename.bak"
            fi

            # Patch and install the driver
            ensure_patch_compat
            run_command "Patching driver" "info" "./$driver_filename --apply-patch $VGPU_DIR/vgpu-proxmox/$driver_patch"
            # Run the patched driver installer
            chmod +x "$custom_filename"
            run_command "Installing patched driver" "info" "./$custom_filename $install_flags"
        elif [ "$VGPU_SUPPORT" = "Native" ] || [ "$VGPU_SUPPORT" = "Native" ] || [ "$VGPU_SUPPORT" = "Unknown" ]; then
            # Run the regular driver installer
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
        FILE_VERSION=$(echo "$driver_filename" | grep -oP '\d+\.\d+\.\d+')

        if [[ "$nvidia_smi_output" == *"NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver."* ]] || [[ "$nvidia_smi_output" == *"No supported devices in vGPU mode"* ]]; then
            echo -e "${RED}[+]${NC} Nvidia driver not properly loaded"
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

        if [ "${FASTAPI_WARNING}" = "1" ]; then
            echo -e "${YELLOW}[!]${NC} Reminder: Driver branch ${driver_version} requires gridd-unlock patches or nvlts for licensing."
        fi

        # Check DRIVER_VERSION against specific branches for guest driver guidance
        case "$driver_version" in
            19.*)
                echo -e "${GREEN}[+]${NC} Download the matching vGPU 19.x guest drivers (Windows/Linux) from NVIDIA's enterprise portal."
                ;;
            18.*)
                echo -e "${GREEN}[+]${NC} Download the matching vGPU 18.x guest drivers (Windows/Linux) from NVIDIA's enterprise portal."
                ;;
            17.4)
                echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.127.06"
                ;;
            17.3)
                echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.90.05"
                ;;
            17.0)
                echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.54.10"
                echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.0/NVIDIA-Linux-x86_64-550.54.14-grid.run"
                echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.0/551.61_grid_win10_win11_server2022_dch_64bit_international.exe"
                ;;
            16.4)
                echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.161.05"
                echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.4/NVIDIA-Linux-x86_64-535.161.07-grid.run"
                echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.4/538.33_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
                ;;
            16.2)
                echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.129.03"
                echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.2/NVIDIA-Linux-x86_64-535.129.03-grid.run"
                echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.2/537.70_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
                ;;
            16.1)
                echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.104.06"
                echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.1/NVIDIA-Linux-x86_64-535.104.05-grid.run"
                echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.1/537.13_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
                ;;
            16.0)
                echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.54.06"
                echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.0/NVIDIA-Linux-x86_64-535.54.03-grid.run"
                echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.0/536.25_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
                ;;
            *)
                echo -e "${YELLOW}[-]${NC} Download guest drivers matching host version ${driver_filename} from NVIDIA's enterprise portal."
                ;;
        esac

        echo ""
        echo "Step 2 completed and installation process is now finished."
        echo ""
        echo "List all available mdevs by typing: mdevctl types and choose the one that fits your needs and VRAM capabilities"
        echo "Login to your Proxmox server over http/https. Click the VM and go to Hardware."
        echo "Under Add choose PCI Device and assign the desired mdev type to your VM"
        echo ""
        echo "Removing the config.txt file."
        echo ""

        rm -f "$CONFIG_FILE" 

        # Option to license the vGPU
        configure_fastapi_dls
        ;;
    *)
        echo "Invalid installation step. Please check the script."
        exit 1
        ;;
esac
