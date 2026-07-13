#!/bin/bash
# lib/common.sh - Common functions and utilities
# Part of proxmox-vgpu-installer v1.82
# Extracted from main script for better maintainability

# Color codes (extracted from main script)
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

# Logging functions (wrapper around existing echo -e pattern)
log_info() {
    echo -e "${GREEN}[+]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[-]${NC} $*"
}

log_error() {
    echo -e "${RED}[!]${NC} $*"
}

log_debug() {
    echo -e "${CYAN}[i]${NC} $*"
}

log_question() {
    echo -e "${BLUE}[?]${NC} $*"
}

# Enhanced run_command wrapper (maintains compatibility with existing function)
# This is a helper that can be used alongside the main run_command
safe_run() {
    local description="$1"
    local command="$2"
    local error_msg="${3:-Command failed}"
    
    if ! run_command "$description" "info" "$command"; then
        log_error "$error_msg"
        return 1
    fi
    return 0
}

# Utility function: Strip trailing carriage return (already exists in main script)
# Kept here for reference and potential future use
strip_trailing_cr() {
    local value="$1"
    while [[ "$value" == *$'\r' ]]; do
        value="${value%$'\r'}"
    done
    printf '%s' "$value"
}

# Version comparison helpers (already exist in main script)
# Kept here for reference
version_ge() {
    dpkg --compare-versions "$1" ge "$2"
}

version_gt() {
    dpkg --compare-versions "$1" gt "$2"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Please use sudo or execute as root user."
        return 1
    fi
    return 0
}

# Display a separator line
print_separator() {
    echo -e "${GREEN}${BOLD}-------------------------------------${NC}"
}

# Display a section header
print_header() {
    local title="$1"
    echo ""
    print_separator
    echo -e "${GREEN}${BOLD}$title${NC}"
    print_separator
    echo ""
}

# Confirm action with user
confirm_action() {
    local message="$1"
    local response
    read -r -p "$(log_question "$message (y/n): ")" response
    response=$(strip_trailing_cr "$response")
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Display progress indicator
show_progress() {
    local message="$1"
    echo -ne "${CYAN}[⏳]${NC} $message\r"
}

# Clear progress indicator
clear_progress() {
    echo -ne "\r\033[K"
}

# Display success message
show_success() {
    local message="$1"
    echo -e "${GREEN}[✓]${NC} $message"
}

# Display failure message
show_failure() {
    local message="$1"
    echo -e "${RED}[✗]${NC} $message"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if file exists and is readable
file_readable() {
    [[ -f "$1" && -r "$1" ]]
}

# Check if directory exists and is writable
dir_writable() {
    [[ -d "$1" && -w "$1" ]]
}

# Get primary IP address
get_primary_ip() {
    local host_ip=""
    
    if command_exists hostname; then
        host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        if [ -z "$host_ip" ]; then
            host_ip=$(hostname -i 2>/dev/null | awk '{print $1}')
        fi
    fi
    
    if [ -z "$host_ip" ] && command_exists ip; then
        host_ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | head -n1)
        host_ip=${host_ip%%/*}
    fi
    
    echo "$host_ip"
}

# Detect CPU vendor
get_cpu_vendor() {
    local vendor_id
    vendor_id=$(grep vendor_id /proc/cpuinfo | awk 'NR==1{print $3}')
    echo "$vendor_id"
}

# Check if IOMMU is enabled
check_iommu_enabled() {
    if dmesg | grep -e IOMMU | grep -q "Detected AMD IOMMU"; then
        echo "AMD"
        return 0
    elif dmesg | grep -e DMAR | grep -q "IOMMU enabled"; then
        echo "Intel"
        return 0
    else
        return 1
    fi
}

# Backup file with timestamp
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.bak.$(date +%s)"
        cp "$file" "$backup"
        log_info "Backed up $file to $backup"
        echo "$backup"
    fi
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
}

# Module initialization message
module_init() {
    local module_name="$1"
    log_debug "Loaded module: $module_name"
}

# Module loaded indicator
module_init "common.sh"
