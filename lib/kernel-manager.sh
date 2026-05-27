#!/bin/bash
# lib/kernel-manager.sh - Kernel management functions
# Part of proxmox-vgpu-installer v1.8
# Handles kernel version detection, downgrade, and header installation

# Helper: check if Secure Boot is enabled (fallback definition if not loaded)
if ! declare -F secure_boot_enabled >/dev/null 2>&1; then
    secure_boot_enabled() {
        if ! command -v mokutil >/dev/null 2>&1; then
            return 1
        fi
        mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"
    }
fi

# Helper: check if signed kernel variant is available (fallback definition if not loaded)
if ! declare -F kernel_signed_available >/dev/null 2>&1; then
    kernel_signed_available() {
        local kernel_ver="$1"
        apt-cache show "proxmox-kernel-${kernel_ver}-signed" >/dev/null 2>&1
    }
fi

# Check if kernel version is 6.17 or higher (including 7.x)
is_kernel_617_or_higher() {
    local current_kernel
    current_kernel=$(uname -r | sed 's/-pve.*//')
    version_ge "$current_kernel" "6.17"
}

# Check if kernel version is incompatible with NVIDIA driver (6.17+, 7.x+)
is_kernel_incompatible_with_driver() {
    local current_kernel
    current_kernel=$(uname -r | sed 's/-pve.*//')
    # Check if kernel is 6.17 or higher (includes 7.x)
    version_ge "$current_kernel" "6.17"
}

# Ensure kernel headers are installed
ensure_kernel_headers() {
    local kernel_release
    kernel_release=$(uname -r)

    # Check if headers already installed
    if dpkg -s "pve-headers-$kernel_release" >/dev/null 2>&1; then
        log_info "Kernel headers already installed for $kernel_release"
        return 0
    fi

    log_info "Kernel headers not found for $kernel_release"
    log_info "Attempting to install headers..."

    # Try pve-headers first
    log_info "Installing headers for kernel $kernel_release"
    if ! run_command "Installing pve-headers-$kernel_release" "info" "apt install -y pve-headers-$kernel_release"; then
        log_warn "Falling back to linux-headers-$kernel_release"
        run_command "Installing linux-headers-$kernel_release" "info" "apt install -y linux-headers-$kernel_release"
    fi
}

# Discover the latest available 6.14.11 kernel package in apt cache (to prevent not-found errors)
discover_target_kernel_version() {
    local default_fallback="6.14.11-9-pve"
    local pkg_name
    
    if command -v apt-cache >/dev/null 2>&1; then
        pkg_name=$(apt-cache pkgnames proxmox-kernel-6.14.11- 2>/dev/null | grep -E '^proxmox-kernel-6.14.11-[0-9]+-pve(-signed)?$' | sort -V | tail -n 1)
        if [ -n "$pkg_name" ]; then
            local ver
            ver=$(echo "$pkg_name" | sed -E 's/proxmox-kernel-(.*-pve)(-signed)?/\1/')
            if [ -n "$ver" ]; then
                echo "$ver"
                return 0
            fi
        fi
    fi
    echo "$default_fallback"
}

# Downgrade kernel to 6.14 for vGPU unlock compatibility (v1.75)
downgrade_kernel_for_vgpu() {
    local target_kernel
    target_kernel=$(discover_target_kernel_version)
    
    log_warn "Current kernel $(uname -r) is 6.17 or higher."
    log_warn "Downgrading to kernel $target_kernel for vGPU patch compatibility."
    echo ""
    
    # Check if Secure Boot is enabled and install appropriate kernel variant
    if secure_boot_enabled; then
        log_info "Secure Boot detected — attempting to install signed kernel package."
        if kernel_signed_available "$target_kernel"; then
            log_info "Signed kernel package found: proxmox-kernel-${target_kernel}-signed"
            run_command "Installing proxmox-kernel-${target_kernel}-signed" "info" "apt install -y proxmox-kernel-${target_kernel}-signed"
        else
            log_warn "No signed kernel package found for $target_kernel."
            log_warn "Installing unsigned kernel — this may cause 'bad shim signature' or boot failure on Secure Boot systems!"
            log_warn "Consider manually importing/signing the kernel or disabling Secure Boot in UEFI BIOS."
            run_command "Installing proxmox-kernel-$target_kernel" "info" "apt install -y proxmox-kernel-$target_kernel"
        fi
    else
        log_info "Installing proxmox-kernel-$target_kernel..."
        run_command "Installing proxmox-kernel-$target_kernel" "info" "apt install -y proxmox-kernel-$target_kernel"
    fi
    
    log_info "Installing proxmox-headers-$target_kernel..."
    run_command "Installing proxmox-headers-$target_kernel" "info" "apt install -y proxmox-headers-$target_kernel"
    
    # Pin the kernel to prevent automatic upgrades
    log_info "Pinning kernel $target_kernel..."
    run_command "Pinning kernel $target_kernel" "info" "proxmox-boot-tool kernel pin $target_kernel"
    
    log_info "Kernel downgraded to $target_kernel and pinned."
    set_config_value "KERNEL_DOWNGRADED" "1"
    
    return 0
}

# Check if kernel downgrade is needed for vGPU unlock
check_kernel_compatibility() {
    local vgpu_support="${1:-$VGPU_SUPPORT}"
    
    # Only check for vgpu_unlock scenarios
    if [ "$vgpu_support" != "Yes" ]; then
        return 0
    fi
    
    # Check if kernel is 6.17 or higher
    if is_kernel_617_or_higher; then
        log_warn "Kernel 6.17+ detected with vGPU unlock mode."
        log_warn "Kernel downgrade required for patch compatibility."
        return 1
    fi
    
    return 0
}

# Get current kernel version
get_kernel_version() {
    uname -r
}

# Get kernel major version (e.g., "6.17" from "6.17.0-1-pve")
get_kernel_major_version() {
    uname -r | sed 's/-pve.*//'
}

# Check if kernel is pinned
is_kernel_pinned() {
    proxmox-boot-tool kernel list 2>/dev/null | grep -q "pinned"
}

# Unpin kernel
unpin_kernel() {
    log_info "Unpinning kernel..."
    run_command "Unpinning kernel" "info" "proxmox-boot-tool kernel unpin"
}

# Pin specific kernel version
pin_kernel() {
    local kernel_version="$1"
    
    if [ -z "$kernel_version" ]; then
        log_error "Kernel version not specified"
        return 1
    fi
    
    log_info "Pinning kernel $kernel_version..."
    run_command "Pinning kernel $kernel_version" "info" "proxmox-boot-tool kernel pin $kernel_version"
}

# List available kernels
list_kernels() {
    log_info "Available kernels:"
    proxmox-boot-tool kernel list 2>/dev/null || dpkg -l | grep -E 'proxmox-kernel|pve-kernel' | awk '{print $2}'
}

# Install specific kernel version
install_kernel() {
    local kernel_version="$1"
    
    if [ -z "$kernel_version" ]; then
        log_error "Kernel version not specified"
        return 1
    fi
    
    if secure_boot_enabled; then
        log_info "Secure Boot detected — attempting to install signed kernel package."
        if kernel_signed_available "$kernel_version"; then
            log_info "Signed kernel package found: proxmox-kernel-${kernel_version}-signed"
            run_command "Installing proxmox-kernel-${kernel_version}-signed" "info" "apt install -y proxmox-kernel-${kernel_version}-signed"
        else
            log_warn "No signed kernel package found for $kernel_version."
            log_warn "Installing unsigned kernel — this may cause boot failure on Secure Boot systems."
            run_command "Installing proxmox-kernel-$kernel_version" "info" "apt install -y proxmox-kernel-$kernel_version"
        fi
    else
        log_info "Installing kernel $kernel_version..."
        run_command "Installing proxmox-kernel-$kernel_version" "info" "apt install -y proxmox-kernel-$kernel_version"
    fi
    
    log_info "Installing headers for $kernel_version..."
    run_command "Installing proxmox-headers-$kernel_version" "info" "apt install -y proxmox-headers-$kernel_version"
}

# Remove old kernels (cleanup)
cleanup_old_kernels() {
    log_info "Cleaning up old kernels..."
    
    # Get current kernel
    local current_kernel
    current_kernel=$(uname -r)
    
    log_warn "Current kernel: $current_kernel (will be preserved)"
    
    # List installed kernels
    local installed_kernels
    installed_kernels=$(dpkg -l | grep -E 'proxmox-kernel|pve-kernel' | awk '{print $2}')
    
    log_info "Installed kernels:"
    echo "$installed_kernels"
    
    # Prompt for confirmation
    if confirm_action "Do you want to remove old kernels (excluding current)?"; then
        run_command "Removing old kernels" "info" "apt autoremove -y --purge"
        log_info "Old kernels removed"
    else
        log_info "Kernel cleanup skipped"
    fi
}

# Reinstall current kernel headers
reinstall_current_headers() {
    local kernel_release
    kernel_release=$(uname -r)
    
    log_info "Reinstalling headers for current kernel: $kernel_release"
    run_command "Reinstalling headers" "info" "apt install --reinstall -y proxmox-headers-$kernel_release"
}

# Check if DKMS is installed
check_dkms_installed() {
    dpkg -s dkms >/dev/null 2>&1
}

# Install DKMS if not present
ensure_dkms() {
    if check_dkms_installed; then
        log_info "DKMS already installed"
        return 0
    fi
    
    log_info "Installing DKMS..."
    run_command "Installing DKMS" "info" "apt install -y dkms"
}

# Get DKMS module status
get_dkms_status() {
    local module_name="${1:-nvidia}"
    dkms status "$module_name" 2>/dev/null || echo "No DKMS modules found for $module_name"
}

# Module loaded indicator
module_init "kernel-manager.sh"
