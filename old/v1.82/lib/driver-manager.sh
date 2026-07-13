#!/bin/bash
# lib/driver-manager.sh - Driver management functions
# Part of proxmox-vgpu-installer v1.82
# Handles driver download, registration, and installation

# Driver registry arrays (declared in main script, used here)
# DRIVER_ORDER, DRIVER_LABELS, DRIVER_FILES, DRIVER_URLS, DRIVER_MD5, DRIVER_PATCHES, DRIVER_NOTES
# DRIVER_BY_FILENAME, HOST_VERSION_TO_BRANCH

# Download driver file with error handling and smart download logic (v1.72+)
download_driver_file() {
    local driver_url="$1"
    local driver_filename="$2"

    if [[ "$driver_url" == https://mega.nz/* ]]; then
        if ! command -v megadl >/dev/null 2>&1; then
            log_error "megadl is required to download from Mega.nz. Install megatools or provide an alternate URL."
            exit 1
        fi

        if ! megadl "$driver_url"; then
            log_error "Download failed."
            exit 1
        fi
    else
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fSL "$driver_url" -o "$driver_filename"; then
                log_error "Download failed."
                exit 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -O "$driver_filename" "$driver_url"; then
                log_error "Download failed."
                exit 1
            fi
        else
            log_error "Neither curl nor wget is available for downloading."
            exit 1
        fi
    fi
}

# Register a driver in the driver registry
register_driver() {
    local branch="$1"
    local label="$2"
    local filename="$3"
    local url="$4"
    local md5="$5"
    local patch="$6"
    local note="${7:-}"

    # Check for patch overrides
    if [ -z "$patch" ]; then
        if [ -n "${PATCH_OVERRIDES[$branch]:-}" ]; then
            patch="${PATCH_OVERRIDES[$branch]}"
        elif [ -n "${PATCH_OVERRIDES[$filename]:-}" ]; then
            patch="${PATCH_OVERRIDES[$filename]}"
        fi
    fi

    # Register driver in arrays
    DRIVER_ORDER+=("$branch")
    DRIVER_LABELS["$branch"]="$label"
    DRIVER_FILES["$branch"]="$filename"
    DRIVER_URLS["$branch"]="$url"
    DRIVER_MD5["$branch"]="$md5"
    DRIVER_PATCHES["$branch"]="$patch"
    DRIVER_NOTES["$branch"]="$note"

    # Register by filename
    if [ -n "$filename" ] && [ -z "${DRIVER_BY_FILENAME[$filename]:-}" ]; then
        DRIVER_BY_FILENAME["$filename"]="$branch"
    fi

    # Register by host version
    if [ -n "$filename" ]; then
        local host_version_lookup=""
        if host_version_lookup=$(extract_host_version_from_filename "$filename" 2>/dev/null); then
            if [ -z "${HOST_VERSION_TO_BRANCH[$host_version_lookup]:-}" ]; then
                HOST_VERSION_TO_BRANCH["$host_version_lookup"]="$branch"
            fi
        fi
    fi
}

# Verify driver file MD5 checksum
verify_driver_md5() {
    local driver_filename="$1"
    local expected_md5="$2"
    
    if [ ! -f "$driver_filename" ]; then
        log_error "Driver file not found: $driver_filename"
        return 1
    fi
    
    if [ -z "$expected_md5" ]; then
        log_warn "No MD5 checksum provided for verification"
        return 0
    fi
    
    local actual_md5
    actual_md5=$(md5sum "$driver_filename" | awk '{print $1}')
    
    if [ "$actual_md5" = "$expected_md5" ]; then
        log_info "MD5 checksum verified: $driver_filename"
        return 0
    else
        log_error "MD5 checksum mismatch for $driver_filename"
        log_error "Expected: $expected_md5"
        log_error "Actual:   $actual_md5"
        return 1
    fi
}

# Smart download with existence checking and MD5 verification (v1.72+)
smart_download_driver() {
    local driver_url="$1"
    local driver_filename="$2"
    local expected_md5="$3"
    
    # Check if file already exists
    if [ -f "$driver_filename" ]; then
        log_info "Driver file already exists: $driver_filename"
        
        # Verify MD5 if provided
        if [ -n "$expected_md5" ]; then
            local actual_md5
            actual_md5=$(md5sum "$driver_filename" | awk '{print $1}')
            
            if [ "$actual_md5" = "$expected_md5" ]; then
                log_info "MD5 checksum matches. Skipping download."
                return 0
            else
                log_warn "MD5 checksum mismatch. Backing up and re-downloading."
                mv "$driver_filename" "${driver_filename}.bak"
                log_info "Old file backed up as ${driver_filename}.bak"
            fi
        else
            log_warn "No MD5 checksum available. Using existing file."
            return 0
        fi
    fi
    
    # Download the file
    log_info "Downloading driver: $driver_filename"
    download_driver_file "$driver_url" "$driver_filename"
    
    # Verify downloaded file
    if [ -n "$expected_md5" ]; then
        verify_driver_md5 "$driver_filename" "$expected_md5"
    fi
}

# Get driver installation arguments based on version
get_driver_install_args() {
    local driver_version="$1"
    
    # Extract major version (e.g., "16" from "16.5")
    local major_version="${driver_version%%.*}"
    
    # Determine install arguments based on version and card type
    if [ "${VGPU_SUPPORT:-}" = "Yes" ] || [ "${VGPU_SUPPORT:-}" = "Native" ]; then
        # Both consumer vGPU unlock and Native vGPU cards MUST force proprietary closed-source modules (-m=kernel)
        # because the open-source kernel modules (nvidia-open) do not support vGPU virtual functions at all.
        echo "--dkms -m=kernel -s"
    else
        # For non-vGPU or other fallback scenarios, respect the driver version's default behavior
        if [ "$major_version" -ge 18 ]; then
            echo "--dkms -s"
        else
            echo "--dkms -m=kernel -s"
        fi
    fi
}

# Check if driver requires megatools
driver_requires_megatools() {
    local driver_url="$1"
    [[ "$driver_url" == https://mega.nz/* ]]
}

# List all registered drivers
list_drivers() {
    local require_downloadable="${1:-false}"
    
    log_info "Available drivers:"
    echo ""
    
    for branch in "${DRIVER_ORDER[@]}"; do
        local label="${DRIVER_LABELS[$branch]}"
        local url="${DRIVER_URLS[$branch]}"
        local note="${DRIVER_NOTES[$branch]}"
        
        # Skip if downloadable required and no URL
        if [ "$require_downloadable" = "true" ] && [ -z "$url" ]; then
            continue
        fi
        
        echo "  $branch: $label"
        if [ -n "$note" ]; then
            echo "      Note: $note"
        fi
    done
    echo ""
}

# Get driver info by branch
get_driver_info() {
    local branch="$1"
    
    if [ -z "${DRIVER_LABELS[$branch]:-}" ]; then
        return 1
    fi
    
    echo "Branch: $branch"
    echo "Label: ${DRIVER_LABELS[$branch]}"
    echo "File: ${DRIVER_FILES[$branch]}"
    echo "URL: ${DRIVER_URLS[$branch]}"
    echo "MD5: ${DRIVER_MD5[$branch]}"
    echo "Patch: ${DRIVER_PATCHES[$branch]}"
    echo "Note: ${DRIVER_NOTES[$branch]}"
}

# Check if driver branch exists
driver_exists() {
    local branch="$1"
    [ -n "${DRIVER_LABELS[$branch]:-}" ]
}

# Get driver filename by branch
get_driver_filename() {
    local branch="$1"
    echo "${DRIVER_FILES[$branch]:-}"
}

# Get driver URL by branch
get_driver_url() {
    local branch="$1"
    echo "${DRIVER_URLS[$branch]:-}"
}

# Get driver MD5 by branch
get_driver_md5() {
    local branch="$1"
    echo "${DRIVER_MD5[$branch]:-}"
}

# Get driver patch by branch
get_driver_patch() {
    local branch="$1"
    echo "${DRIVER_PATCHES[$branch]:-}"
}

# Module loaded indicator
module_init "driver-manager.sh"
