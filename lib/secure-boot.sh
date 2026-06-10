#!/bin/bash
# lib/secure-boot.sh - Secure Boot management functions
# Part of proxmox-vgpu-installer v1.82
# Handles Secure Boot detection, key generation, and MOK enrollment

# Secure Boot directories and files (from main script)
# SECURE_BOOT_DIR, SECURE_BOOT_KEY, SECURE_BOOT_CERT

# Check if Secure Boot is enabled
secure_boot_enabled() {
    # Check EFI vars first if they exist
    local sb_file="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    if [ -f "$sb_file" ]; then
        local sb_val
        sb_val=$(od -An -t u1 -j 4 -N 1 "$sb_file" 2>/dev/null | tr -d ' ')
        if [ "$sb_val" = "1" ]; then
            return 0
        elif [ "$sb_val" = "0" ]; then
            return 1
        fi
    fi

    # Fallback to mokutil if available
    if command -v mokutil >/dev/null 2>&1; then
        if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
            return 0
        fi
    fi

    return 1
}

# Check if Secure Boot key is enrolled
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

# Generate Secure Boot module signing keys
generate_secure_boot_keys() {
    mkdir -p "$SECURE_BOOT_DIR"
    local secure_boot_der="${SECURE_BOOT_DER:-$SECURE_BOOT_DIR/module-signing.der}"

    if [ ! -f "$SECURE_BOOT_KEY" ] || [ ! -f "$SECURE_BOOT_CERT" ] || [ ! -f "$secure_boot_der" ]; then
        log_info "Generating Secure Boot module signing keys in $SECURE_BOOT_DIR"
        openssl req -new -x509 -newkey rsa:4096 -sha256 -days 3650 \
            -nodes -out "$SECURE_BOOT_CERT" -keyout "$SECURE_BOOT_KEY" \
            -subj "/CN=Proxmox vGPU Module Signing/" >/dev/null 2>&1
        chmod 600 "$SECURE_BOOT_KEY"
        chmod 644 "$SECURE_BOOT_CERT"
        
        # Convert PEM certificate to DER format for mokutil
        log_info "Converting certificate to DER format for mokutil..."
        openssl x509 -in "$SECURE_BOOT_CERT" -inform PEM -out "$secure_boot_der" -outform DER >/dev/null 2>&1
        chmod 644 "$secure_boot_der"
        
        log_info "Secure Boot keys generated successfully"
    else
        log_info "Secure Boot keys already exist"
    fi

    # Convert existing PEM certificate to DER format if missing
    if [ ! -f "$secure_boot_der" ] && [ -f "$SECURE_BOOT_CERT" ]; then
        log_info "Converting existing certificate to DER format for mokutil..."
        openssl x509 -in "$SECURE_BOOT_CERT" -inform PEM -out "$secure_boot_der" -outform DER >/dev/null 2>&1
        chmod 644 "$secure_boot_der"
    fi

    # Configure DKMS to use our custom keys for automatic signing
    if [ -d /etc/dkms ]; then
        log_info "Configuring DKMS to use custom Secure Boot keys..."
        if [ -d /etc/dkms/framework.conf.d ]; then
            cat > /etc/dkms/framework.conf.d/nvidia-vgpu.conf <<EOF
mok_signing_key="$SECURE_BOOT_KEY"
mok_certificate="$secure_boot_der"
EOF
            chmod 644 /etc/dkms/framework.conf.d/nvidia-vgpu.conf
        else
            # Append to framework.conf if not already present
            if [ -f /etc/dkms/framework.conf ]; then
                if ! grep -q "mok_signing_key=\"$SECURE_BOOT_KEY\"" /etc/dkms/framework.conf; then
                    echo "" >> /etc/dkms/framework.conf
                    echo "mok_signing_key=\"$SECURE_BOOT_KEY\"" >> /etc/dkms/framework.conf
                    echo "mok_certificate=\"$secure_boot_der\"" >> /etc/dkms/framework.conf
                fi
            fi
        fi
        log_info "DKMS signing configuration updated."
    fi
}

# Prepare Secure Boot enrollment (MOK)
prepare_secure_boot_enrollment() {
    if ! command -v mokutil >/dev/null 2>&1; then
        log_error "mokutil is required to manage Secure Boot keys. Please install mokutil and rerun the script."
        exit 1
    fi

    generate_secure_boot_keys
    local secure_boot_der="${SECURE_BOOT_DER:-$SECURE_BOOT_DIR/module-signing.der}"

    log_warn "Secure Boot is enabled. The NVIDIA modules must be signed."
    log_warn "You will now be prompted to enter a one-time password for enrolling the signing certificate."
    log_warn "Record this password; you must confirm it in the firmware MOK manager on the next reboot."
    echo ""
    log_debug "MOK Password policy:"
    log_debug "  - Minimum 8 characters (mokutil requirement)"
    log_debug "  - ASCII characters only (a-z, A-Z, 0-9, symbols)"
    log_debug "  - Avoid special characters like @ # $ that may not type correctly in UEFI"
    log_debug "  - Recommended: use only letters and numbers for maximum compatibility"
    echo ""

    mokutil --import "$secure_boot_der"

    log_info "Enrollment request queued. Reboot the host and complete the MOK enrollment when prompted."
    log_debug "MOK Enrollment Steps:"
    log_debug " 1. Select 'Enroll MOK'"
    log_debug " 2. Select 'Continue' then 'Yes'"
    log_debug " 3. Input the password you set above."
    log_debug " 4. Select 'Reboot' to finish MOK Enrollment."
    set_config_value "SECURE_BOOT_PENDING" "1"
    set_config_value "SECURE_BOOT_READY" "0"
    
    log_warn "After the reboot and enrollment, rerun this installer to continue."
    exit 0
}

# Secure Boot precheck (Issue #14 - Enhanced warnings)
secure_boot_precheck() {
    if ! secure_boot_enabled; then
        remove_config_key "SECURE_BOOT_PENDING"
        remove_config_key "SECURE_BOOT_READY"
        return 0
    fi

    # Secure Boot is active. Ensure prerequisites are installed.
    ensure_mokutil

    log_info "Secure Boot detected."
    log_debug "Secure Boot requires kernel modules to be signed."
    echo ""

    if secure_boot_key_enrolled; then
        log_info "Secure Boot signing certificate already enrolled."
        set_config_value "SECURE_BOOT_READY" "1"
        set_config_value "SECURE_BOOT_PENDING" "0"
        # Also update the in-memory variable so build_secure_boot_flags() sees the correct value
        # (set_config_value only writes to config.txt, not the current process environment)
        SECURE_BOOT_READY="1"
        SECURE_BOOT_PENDING="0"
        return 0
    fi

    if [[ "${SECURE_BOOT_PENDING}" == "1" ]]; then
        # Check if there is actually a pending MOK import in the firmware.
        # If the user dismissed the MOK screen (chose 'Continue' instead of 'Enroll MOK'),
        # the firmware clears the pending request but SECURE_BOOT_PENDING stays 1 in config.
        # In that case, automatically re-queue the enrollment instead of looping forever.
        if mokutil --list-new 2>/dev/null | grep -qi "CN=Proxmox"; then
            log_warn "Secure Boot enrollment still pending."
            log_warn "Please reboot, approve the MOK enrollment, then rerun this installer."
            echo ""
            log_debug "During boot, you will see a blue MOK Management screen."
            log_debug "Select 'Enroll MOK' -> 'Continue' -> Enter the password you set -> 'Reboot'"
            echo ""
            exit 0
        else
            # Firmware no longer has a pending import - the user skipped the MOK screen.
            # Re-queue the enrollment automatically.
            log_warn "The MOK enrollment was not completed (the MOK screen was dismissed or skipped)."
            log_warn "Re-queueing the Secure Boot certificate enrollment now."
            echo ""
            set_config_value "SECURE_BOOT_PENDING" "0"
            prepare_secure_boot_enrollment
            return
        fi
    fi

    # Issue #14 - Enhanced warning about unsigned kernel installation
    log_warn "WARNING: Installing drivers with Secure Boot enabled requires signed modules."
    log_warn "The installer will generate and enroll a signing key."
    echo ""
    log_debug "You will need to approve this key on next reboot to avoid 'bad shim signature' errors."
    log_debug "This is a one-time process that ensures your system remains secure."
    echo ""
    
    prepare_secure_boot_enrollment
}

# Build Secure Boot flags for driver installation
build_secure_boot_flags() {
    if secure_boot_enabled && [[ "${SECURE_BOOT_READY}" == "1" ]] && [ -f "$SECURE_BOOT_KEY" ] && [ -f "$SECURE_BOOT_CERT" ]; then
        printf -- "--module-signing-secret-key=%s --module-signing-public-key=%s" "$SECURE_BOOT_KEY" "$SECURE_BOOT_CERT"
    fi
}

# Get Secure Boot status
get_secure_boot_status() {
    if ! command -v mokutil >/dev/null 2>&1; then
        echo "mokutil not installed"
        return 1
    fi
    
    if secure_boot_enabled; then
        echo "Secure Boot: Enabled"
        if secure_boot_key_enrolled; then
            echo "MOK Status: Enrolled"
        else
            echo "MOK Status: Not enrolled"
        fi
    else
        echo "Secure Boot: Disabled"
    fi
}

# List enrolled MOK keys
list_mok_keys() {
    if ! command -v mokutil >/dev/null 2>&1; then
        log_error "mokutil not installed"
        return 1
    fi
    
    log_info "Enrolled MOK keys:"
    mokutil --list-enrolled 2>/dev/null || log_warn "No MOK keys enrolled"
}

# Check if mokutil is installed
check_mokutil_installed() {
    command -v mokutil >/dev/null 2>&1
}

# Install mokutil and shim-signed grub-efi-amd64-signed if not present
ensure_mokutil() {
    log_info "Ensuring Secure Boot prerequisites (shim-signed, grub-efi-amd64-signed, mokutil) are installed..."
    run_command "Installing Secure Boot prerequisites" "info" "apt-get install -y shim-signed grub-efi-amd64-signed mokutil"
}

# Verify Secure Boot certificate
verify_secure_boot_cert() {
    if [ ! -f "$SECURE_BOOT_CERT" ]; then
        log_error "Secure Boot certificate not found: $SECURE_BOOT_CERT"
        return 1
    fi
    
    log_info "Verifying Secure Boot certificate..."
    if openssl x509 -in "$SECURE_BOOT_CERT" -text -noout >/dev/null 2>&1; then
        log_info "Certificate is valid"
        return 0
    else
        log_error "Certificate is invalid or corrupted"
        return 1
    fi
}

# Backup Secure Boot keys
backup_secure_boot_keys() {
    if [ ! -d "$SECURE_BOOT_DIR" ]; then
        log_warn "Secure Boot directory not found"
        return 1
    fi
    
    local backup_dir="${SECURE_BOOT_DIR}.bak.$(date +%s)"
    log_info "Backing up Secure Boot keys to $backup_dir"
    cp -r "$SECURE_BOOT_DIR" "$backup_dir"
    log_info "Backup completed"
}

# Module loaded indicator
module_init "secure-boot.sh"
