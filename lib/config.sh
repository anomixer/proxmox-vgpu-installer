#!/bin/bash
# lib/config.sh - Configuration management
# Part of proxmox-vgpu-installer v1.8
# Wraps config.txt operations for better maintainability

# Configuration file location (from main script)
# CONFIG_FILE is set in main script as "$SCRIPT_DIR/config.txt"

# Ensure config file exists
ensure_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        : > "$CONFIG_FILE"
        log_debug "Created config file: $CONFIG_FILE"
    fi
}

# Set a configuration value
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
    
    log_debug "Set config: $key=$value"
}

# Get a configuration value
get_config_value() {
    local key="$1"
    local default="${2:-}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "$default"
        return 1
    fi
    
    local value
    value=$(grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2-)
    
    if [ -z "$value" ]; then
        echo "$default"
        return 1
    fi
    
    echo "$value"
    return 0
}

# Remove a configuration key
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
        log_debug "Removed config key: $key"
    fi
}

# Check if a configuration key exists
config_key_exists() {
    local key="$1"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi
    
    grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null
}

# Load configuration into environment variables
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # Source the config file safely
        while IFS='=' read -r key value; do
            # Skip empty lines and comments
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            
            # Export the variable
            export "$key=$value"
        done < "$CONFIG_FILE"
        
        log_debug "Loaded configuration from $CONFIG_FILE"
    else
        log_debug "No configuration file found at $CONFIG_FILE"
    fi
}

# Save current state to config
save_state() {
    local step="${1:-$STEP}"
    local vgpu_support="${2:-$VGPU_SUPPORT}"
    local driver_version="${3:-$DRIVER_VERSION}"
    
    set_config_value "STEP" "$step"
    
    if [ -n "$vgpu_support" ]; then
        set_config_value "VGPU_SUPPORT" "$vgpu_support"
    fi
    
    if [ -n "$driver_version" ]; then
        set_config_value "DRIVER_VERSION" "$driver_version"
    fi
    
    log_info "Saved installation state (Step: $step)"
}

# Clear configuration file
clear_config() {
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        log_info "Cleared configuration file"
    fi
}

# Display current configuration
show_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "No configuration file found"
        return 1
    fi
    
    log_info "Current configuration:"
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        echo "  $key = $value"
    done < "$CONFIG_FILE"
}

# Validate configuration
validate_config() {
    local valid=true
    
    # Check required keys for step 2
    if [ "${STEP:-1}" = "2" ]; then
        if ! config_key_exists "VGPU_SUPPORT"; then
            log_error "Missing required config: VGPU_SUPPORT"
            valid=false
        fi
        
        if ! config_key_exists "DRIVER_VERSION"; then
            log_error "Missing required config: DRIVER_VERSION"
            valid=false
        fi
    fi
    
    if [ "$valid" = true ]; then
        log_debug "Configuration validation passed"
        return 0
    else
        log_error "Configuration validation failed"
        return 1
    fi
}

# Backup configuration file
backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        local backup="${CONFIG_FILE}.bak.$(date +%s)"
        cp "$CONFIG_FILE" "$backup"
        log_info "Backed up configuration to $backup"
        echo "$backup"
    fi
}

# Restore configuration from backup
restore_config() {
    local backup="$1"
    
    if [ ! -f "$backup" ]; then
        log_error "Backup file not found: $backup"
        return 1
    fi
    
    cp "$backup" "$CONFIG_FILE"
    log_info "Restored configuration from $backup"
    return 0
}

# Module loaded indicator
module_init "config.sh"
