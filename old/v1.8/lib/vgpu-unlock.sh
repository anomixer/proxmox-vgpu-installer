#!/bin/bash
# lib/vgpu-unlock.sh - vGPU unlock setup
# Part of proxmox-vgpu-installer v1.8
# Handles vgpu-proxmox and vgpu_unlock-rs setup for consumer GPUs

# Download vgpu-proxmox repository
download_vgpu_proxmox() {
    log_info "Downloading vgpu-proxmox patches"
    
    # Remove old directory if exists
    rm -rf "$VGPU_DIR/vgpu-proxmox" 2>/dev/null
    
    # Clone repository
    if ! run_command "Downloading vgpu-proxmox" "info" "git clone https://gitlab.com/polloloco/vgpu-proxmox.git $VGPU_DIR/vgpu-proxmox"; then
        log_error "Failed to download vgpu-proxmox"
        return 1
    fi
    
    log_info "vgpu-proxmox downloaded successfully"
    return 0
}

# Download vgpu_unlock-rs repository
download_vgpu_unlock_rs() {
    log_info "Downloading vgpu_unlock-rs"
    
    # Create /opt directory if not exists
    mkdir -p /opt
    cd /opt || return 1
    
    # Remove old directory if exists
    rm -rf vgpu_unlock-rs 2>/dev/null
    
    # Clone repository
    if ! run_command "Downloading vgpu_unlock-rs" "info" "git clone https://github.com/mbilker/vgpu_unlock-rs.git"; then
        log_error "Failed to download vgpu_unlock-rs"
        return 1
    fi
    
    log_info "vgpu_unlock-rs downloaded successfully"
    return 0
}

# Install Rust if not present
ensure_rust_installed() {
    if command -v cargo >/dev/null 2>&1; then
        log_info "Rust already installed"
        return 0
    fi
    
    log_info "Installing Rust..."
    
    # Download and install Rust
    if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
        log_error "Failed to install Rust"
        return 1
    fi
    
    # Source Rust environment
    export PATH="$HOME/.cargo/bin:$PATH"
    
    log_info "Rust installed successfully"
    return 0
}

# Compile vgpu_unlock-rs
compile_vgpu_unlock() {
    log_info "Compiling vgpu_unlock-rs"
    
    # Ensure Rust is installed
    if ! ensure_rust_installed; then
        return 1
    fi
    
    # Navigate to vgpu_unlock-rs directory
    cd /opt/vgpu_unlock-rs/ || return 1
    
    # Build release version
    if ! run_command "Building vgpu_unlock-rs" "info" "cargo build --release"; then
        log_error "Failed to compile vgpu_unlock-rs"
        return 1
    fi
    
    # Return to original directory
    cd "$VGPU_DIR" || return 1
    
    log_info "vgpu_unlock-rs compiled successfully"
    return 0
}

# Configure vgpu_unlock systemd services
configure_vgpu_unlock_services() {
    log_info "Configuring vgpu_unlock systemd services"
    
    # Create vgpu_unlock directory
    mkdir -p /etc/vgpu_unlock
    touch /etc/vgpu_unlock/profile_override.toml
    
    # Create systemd override directories
    mkdir -p /etc/systemd/system/{nvidia-vgpud.service.d,nvidia-vgpu-mgr.service.d}
    
    # Add vgpu_unlock-rs library to systemd services
    local lib_path="/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so"
    
    if [ ! -f "$lib_path" ]; then
        log_error "vgpu_unlock library not found at $lib_path"
        return 1
    fi
    
    log_info "Adding vgpu_unlock-rs library to NVIDIA services"
    
    # Configure nvidia-vgpud service
    cat > /etc/systemd/system/nvidia-vgpud.service.d/vgpu_unlock.conf <<EOF
[Service]
Environment=LD_PRELOAD=$lib_path
EOF
    
    # Configure nvidia-vgpu-mgr service
    cat > /etc/systemd/system/nvidia-vgpu-mgr.service.d/vgpu_unlock.conf <<EOF
[Service]
Environment=LD_PRELOAD=$lib_path
EOF
    
    log_info "vgpu_unlock systemd services configured"
    return 0
}

# Setup complete vGPU unlock
setup_vgpu_unlock() {
    log_info "Setting up vGPU unlock for consumer GPUs"
    echo ""
    
    # Download vgpu-proxmox
    if ! download_vgpu_proxmox; then
        log_error "Failed to download vgpu-proxmox"
        return 1
    fi
    
    # Download vgpu_unlock-rs
    if ! download_vgpu_unlock_rs; then
        log_error "Failed to download vgpu_unlock-rs"
        return 1
    fi
    
    # Compile vgpu_unlock-rs
    if ! compile_vgpu_unlock; then
        log_error "Failed to compile vgpu_unlock-rs"
        return 1
    fi
    
    # Configure systemd services
    if ! configure_vgpu_unlock_services; then
        log_error "Failed to configure vgpu_unlock services"
        return 1
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    log_info "vGPU unlock setup completed successfully"
    return 0
}

# Remove vgpu_unlock setup
remove_vgpu_unlock() {
    log_info "Removing vgpu_unlock setup"
    
    # Remove vgpu_unlock-rs
    if [ -d "/opt/vgpu_unlock-rs" ]; then
        run_command "Removing vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs"
    fi
    
    # Remove systemd overrides
    rm -f /etc/systemd/system/nvidia-vgpud.service.d/vgpu_unlock.conf 2>/dev/null || true
    rm -f /etc/systemd/system/nvidia-vgpu-mgr.service.d/vgpu_unlock.conf 2>/dev/null || true
    
    # Remove vgpu_unlock directory
    rm -rf /etc/vgpu_unlock 2>/dev/null || true
    
    # Reload systemd
    systemctl daemon-reload
    
    log_info "vgpu_unlock removed"
}

# Remove vgpu-proxmox
remove_vgpu_proxmox() {
    log_info "Removing vgpu-proxmox"
    
    if [ -d "$VGPU_DIR/vgpu-proxmox" ]; then
        run_command "Removing vgpu-proxmox" "notification" "rm -rf $VGPU_DIR/vgpu-proxmox"
    fi
    
    log_info "vgpu-proxmox removed"
}

# Check if vgpu_unlock is installed
is_vgpu_unlock_installed() {
    [ -f "/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so" ]
}

# Check if vgpu-proxmox is installed
is_vgpu_proxmox_installed() {
    [ -d "$VGPU_DIR/vgpu-proxmox" ]
}

# Print tail of installer debug log (patch/driver output is redirected there).
show_debug_log_tail() {
    local lines="${1:-50}"
    if [ -f "${LOG_FILE:-}" ]; then
        echo -e "${YELLOW}[-]${NC} Last ${lines} lines from ${LOG_FILE}:"
        tail -n "$lines" "$LOG_FILE" | sed 's/^/    /'
    else
        echo -e "${YELLOW}[-]${NC} No log file at ${LOG_FILE:-debug.log}."
    fi
}

# Ensure vgpu-proxmox exists and contains the requested patch file.
ensure_vgpu_proxmox_patch() {
    local patch_name="$1"
    local patch_path="$VGPU_DIR/vgpu-proxmox/$patch_name"

    if [ ! -d "$VGPU_DIR/vgpu-proxmox" ] || ! compgen -G "$VGPU_DIR/vgpu-proxmox/"'*.patch' > /dev/null; then
        log_warn "vgpu-proxmox patch repository missing; cloning from GitLab..."
        if ! download_vgpu_proxmox; then
            return 1
        fi
    fi

    if [ ! -f "$patch_path" ]; then
        log_error "Patch file not found: $patch_path"
        if compgen -G "$VGPU_DIR/vgpu-proxmox/"'*.patch' > /dev/null; then
            echo -e "${YELLOW}[-]${NC} Available patches in vgpu-proxmox:"
            compgen -G "$VGPU_DIR/vgpu-proxmox/"'*.patch' | sed 's/^/    /'
        fi
        return 1
    fi

    return 0
}

# Get vgpu_unlock status
get_vgpu_unlock_status() {
    if is_vgpu_unlock_installed; then
        echo "vgpu_unlock-rs: Installed"
        echo "Library: /opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so"
    else
        echo "vgpu_unlock-rs: Not installed"
    fi
    
    if is_vgpu_proxmox_installed; then
        echo "vgpu-proxmox: Installed"
        echo "Location: $VGPU_DIR/vgpu-proxmox"
    else
        echo "vgpu-proxmox: Not installed"
    fi
}

# Module loaded indicator
module_init "vgpu-unlock.sh"
