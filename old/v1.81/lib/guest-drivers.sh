#!/bin/bash
# lib/guest-drivers.sh - Guest driver management
# Part of proxmox-vgpu-installer v1.81
# Handles guest driver catalog, resolution, and downloads

# Guest driver arrays (declared in main script)
# GUEST_LINUX_DRIVERS, GUEST_LINUX_LABELS, GUEST_WINDOWS_DRIVERS, GUEST_WINDOWS_LABELS

# Register a guest driver in the catalog
register_guest_driver() {
    local branch="$1"
    local linux_url="$2"
    local windows_url="$3"
    local linux_label="${4:-}"
    local windows_label="${5:-}"

    # Strip whitespace and special characters
    branch="${branch//[$'\r\n\t ']/}"
    [ -z "$branch" ] && return

    # Register Linux driver
    if [ -n "$linux_url" ]; then
        GUEST_LINUX_DRIVERS["$branch"]="$linux_url"
        if [ -z "$linux_label" ]; then
            linux_label="${linux_url##*/}"
        fi
        GUEST_LINUX_LABELS["$branch"]="$linux_label"
    fi

    # Register Windows driver
    if [ -n "$windows_url" ]; then
        GUEST_WINDOWS_DRIVERS["$branch"]="$windows_url"
        if [ -z "$windows_label" ]; then
            windows_label="${windows_url##*/}"
        fi
        GUEST_WINDOWS_LABELS["$branch"]="$windows_label"
    fi
}

# Load static guest driver catalog (called from main script)
# This function is kept in main script due to large HEREDOC data

# Resolve guest driver links by branch or host version
resolve_guest_driver_links() {
    local branch="$1"
    local host_version="$2"

    # Strip whitespace
    branch="${branch//[$'\r\n\t ']/}"
    host_version="${host_version//[$'\r\n\t ']/}"

    local resolved_branch=""

    # Try to resolve by branch first
    if [ -n "$branch" ]; then
        if [ -n "${GUEST_LINUX_DRIVERS[$branch]:-}" ] || [ -n "${GUEST_WINDOWS_DRIVERS[$branch]:-}" ]; then
            resolved_branch="$branch"
        fi
    fi

    # If not found, try to resolve by host version
    if [ -z "$resolved_branch" ] && [ -n "$host_version" ]; then
        local mapped_branch="${HOST_VERSION_TO_BRANCH[$host_version]:-}"
        if [ -n "$mapped_branch" ]; then
            if [ -n "${GUEST_LINUX_DRIVERS[$mapped_branch]:-}" ] || [ -n "${GUEST_WINDOWS_DRIVERS[$mapped_branch]:-}" ]; then
                resolved_branch="$mapped_branch"
            fi
        fi
    fi

    # Return error if not found
    if [ -z "$resolved_branch" ]; then
        echo "error=No guest driver catalog entry for branch ${branch:-$host_version}"
        return 0
    fi

    # Get driver URLs and labels
    local linux_url="${GUEST_LINUX_DRIVERS[$resolved_branch]:-}"
    local linux_label="${GUEST_LINUX_LABELS[$resolved_branch]:-}"
    local windows_url="${GUEST_WINDOWS_DRIVERS[$resolved_branch]:-}"
    local windows_label="${GUEST_WINDOWS_LABELS[$resolved_branch]:-}"

    # Output results
    if [ -n "$linux_url" ]; then
        echo "linux=$linux_url"
        [ -n "$linux_label" ] && echo "linux_label=$linux_label"
    fi

    if [ -n "$windows_url" ]; then
        echo "windows=$windows_url"
        [ -n "$windows_label" ] && echo "windows_label=$windows_label"
    fi
}

# Download guest driver asset
download_guest_driver_asset() {
    local url="$1"
    local dest_dir="$2"
    local display_name="$3"

    if [ -z "$url" ]; then
        return 1
    fi

    mkdir -p "$dest_dir"

    # Extract filename from URL
    local filename="${url##*/}"
    filename="${filename%%\?*}"
    if [ -z "$filename" ]; then
        filename=$(echo "${display_name:-guest-driver}" | tr ' /' '__')
    fi

    local target="$dest_dir/$filename"

    log_info "Downloading ${display_name:-guest driver}"

    # Try curl first, then wget
    if command -v curl >/dev/null 2>&1; then
        if curl -fSL "$url" -o "$target"; then
            log_info "Saved to $target"
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -O "$target" "$url"; then
            log_info "Saved to $target"
            return 0
        fi
    else
        log_error "Neither curl nor wget is available to download guest drivers."
        return 1
    fi

    log_error "Failed to download ${display_name:-guest driver} from $url"
    rm -f "$target"
    return 1
}

# Prompt user to download guest drivers
# Prompt user to download guest drivers
prompt_guest_driver_downloads() {
    local branch="$1"
    local driver_filename="$2"

    # Reload guest driver catalog from online sources before downloading
    log_info "Reloading guest driver catalog from online sources..."
    load_auto_guest_driver_catalog

    # Try to extract host version from filename
    local host_version=""
    if ! host_version=$(extract_host_version_from_filename "$driver_filename" 2>/dev/null); then
        log_warn "Unable to derive host driver version from $driver_filename for guest driver lookup."
        host_version=""
    fi

    # Create download directory
    local branch_token="${branch:-${host_version:-guest}}"
    branch_token="${branch_token//[^0-9A-Za-z._-]/_}"
    local version_token="${host_version//[^0-9A-Za-z._-]/_}"
    local download_dir="$SCRIPT_DIR/guest-drivers/$branch_token"
    if [ -n "$version_token" ] && [ "$version_token" != "$branch_token" ]; then
        download_dir="$SCRIPT_DIR/guest-drivers/${branch_token}_${version_token}"
    fi

    # Local fallback / auto-discovery logic
    local local_found_dir=""
    local zip_file=""

    # 1. Look for downloaded ZIP in SCRIPT_DIR
    zip_file=$(find "$SCRIPT_DIR" -maxdepth 1 -type f \( -name "NVIDIA-GRID-Linux-KVM-*.zip" -o -name "NVIDIA-GRID-vGPU-*.zip" \) -print -quit 2>/dev/null)

    if [ -n "$zip_file" ]; then
        local base_zip_name
        base_zip_name=$(basename "$zip_file" .zip)
        if [ ! -d "$SCRIPT_DIR/$base_zip_name" ]; then
            log_info "Found local guest driver ZIP: $(basename "$zip_file"). Extracting..."
            if unzip -q -o "$zip_file" -d "$SCRIPT_DIR"; then
                log_info "Extracted to $SCRIPT_DIR/$base_zip_name"
            else
                log_warn "Failed to extract $zip_file"
            fi
        fi
    fi

    # 2. Look for extracted KVM folder in SCRIPT_DIR
    local kvm_dir=""
    kvm_dir=$(find "$SCRIPT_DIR" -maxdepth 1 -type d \( -name "NVIDIA-GRID-Linux-KVM-*" -o -name "NVIDIA-GRID-vGPU-*" \) -print -quit 2>/dev/null)

    if [ -n "$kvm_dir" ]; then
        if [ -d "$kvm_dir/Guest_Drivers" ]; then
            local_found_dir="$kvm_dir/Guest_Drivers"
        elif [ -d "$kvm_dir/guest_drivers" ]; then
            local_found_dir="$kvm_dir/guest_drivers"
        fi
    fi

    local local_linux_file=""
    local local_windows_file=""

    if [ -n "$local_found_dir" ]; then
        local_linux_file=$(find "$local_found_dir" -maxdepth 1 -type f \( -name "NVIDIA-Linux-x86_64-*-grid.run" -o -name "NVIDIA-Linux-x86_64-*-vgpu-kvm.run" -o -name "NVIDIA-Linux-*.run" \) -print -quit 2>/dev/null)
        local_windows_file=$(find "$local_found_dir" -maxdepth 1 -type f -name "*.exe" -print -quit 2>/dev/null)
    fi

    local used_local=0
    if [ -n "$local_linux_file" ] || [ -n "$local_windows_file" ]; then
        log_info "Local guest drivers discovered in: $local_found_dir"
        [ -n "$local_linux_file" ] && log_info "  - Linux: $(basename "$local_linux_file")"
        [ -n "$local_windows_file" ] && log_info "  - Windows: $(basename "$local_windows_file")"
        
        local import_choice
        read -r -p "$(log_question "Import guest drivers from local directory instead of downloading? (y/n): ")" import_choice || import_choice=""
        import_choice=$(strip_trailing_carriage_return "$import_choice")
        if [[ "$import_choice" =~ ^[Yy]$ ]]; then
            mkdir -p "$download_dir"
            if [ -n "$local_linux_file" ]; then
                cp "$local_linux_file" "$download_dir/"
                log_info "Imported Linux driver: $download_dir/$(basename "$local_linux_file")"
            fi
            if [ -n "$local_windows_file" ]; then
                cp "$local_windows_file" "$download_dir/"
                log_info "Imported Windows driver: $download_dir/$(basename "$local_windows_file")"
            fi
            used_local=1
        fi
    fi

    if [ "$used_local" -eq 1 ]; then
        return 0
    fi

    # Resolve guest driver links
    local lookup_output
    lookup_output=$(resolve_guest_driver_links "$branch" "$host_version" || true)

    if [ -z "${lookup_output}" ]; then
        log_warn "Unable to locate guest driver downloads for branch ${branch:-$host_version}."
        return
    fi

    # Parse lookup output
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

    # Handle errors
    if [ -n "$error_message" ]; then
        log_warn "$error_message"
        return
    fi

    if [ -z "$linux_url" ] && [ -z "$windows_url" ]; then
        log_warn "No guest driver download links were published for branch ${branch:-$host_version}."
        return
    fi

    # Strip trailing carriage returns
    linux_url=$(strip_trailing_carriage_return "$linux_url")
    linux_label=$(strip_trailing_carriage_return "$linux_label")
    windows_url=$(strip_trailing_carriage_return "$windows_url")
    windows_label=$(strip_trailing_carriage_return "$windows_label")

    # Prompt for Linux driver download
    if [ -n "$linux_url" ]; then
        local linux_choice
        read -r -p "$(log_question "Download Linux guest drivers now? (y/n): ")" linux_choice || linux_choice=""
        linux_choice=$(strip_trailing_carriage_return "$linux_choice")
        if [[ "$linux_choice" =~ ^[Yy]$ ]]; then
            download_guest_driver_asset "$linux_url" "$download_dir" "${linux_label:-Linux guest driver}" || true
        else
            log_warn "Skipping Linux guest driver download."
        fi
    fi

    # Prompt for Windows driver download
    if [ -n "$windows_url" ]; then
        local windows_choice
        read -r -p "$(log_question "Download Windows guest drivers now? (y/n): ")" windows_choice || windows_choice=""
        windows_choice=$(strip_trailing_carriage_return "$windows_choice")
        if [[ "$windows_choice" =~ ^[Yy]$ ]]; then
            download_guest_driver_asset "$windows_url" "$download_dir" "${windows_label:-Windows guest driver}" || true
        else
            log_warn "Skipping Windows guest driver download."
        fi
    else
        log_warn "No Windows guest driver download link was published for branch ${branch:-$host_version}."
    fi
}

# List available guest drivers
list_guest_drivers() {
    log_info "Available guest drivers:"
    echo ""
    
    # Combine and sort unique branches
    local branches=()
    for branch in "${!GUEST_LINUX_DRIVERS[@]}"; do
        branches+=("$branch")
    done
    for branch in "${!GUEST_WINDOWS_DRIVERS[@]}"; do
        if [[ ! " ${branches[@]} " =~ " ${branch} " ]]; then
            branches+=("$branch")
        fi
    done
    
    # Sort branches
    IFS=$'\n' sorted_branches=($(sort <<<"${branches[*]}"))
    unset IFS
    
    for branch in "${sorted_branches[@]}"; do
        local linux_url="${GUEST_LINUX_DRIVERS[$branch]:-}"
        local windows_url="${GUEST_WINDOWS_DRIVERS[$branch]:-}"
        
        echo "  Branch $branch:"
        [ -n "$linux_url" ] && echo "    Linux: ${GUEST_LINUX_LABELS[$branch]:-$linux_url}"
        [ -n "$windows_url" ] && echo "    Windows: ${GUEST_WINDOWS_LABELS[$branch]:-$windows_url}"
    done
    echo ""
}

# Get guest driver info by branch
get_guest_driver_info() {
    local branch="$1"
    
    local linux_url="${GUEST_LINUX_DRIVERS[$branch]:-}"
    local windows_url="${GUEST_WINDOWS_DRIVERS[$branch]:-}"
    
    if [ -z "$linux_url" ] && [ -z "$windows_url" ]; then
        return 1
    fi
    
    echo "Branch: $branch"
    [ -n "$linux_url" ] && echo "Linux URL: $linux_url"
    [ -n "$linux_url" ] && echo "Linux Label: ${GUEST_LINUX_LABELS[$branch]:-}"
    [ -n "$windows_url" ] && echo "Windows URL: $windows_url"
    [ -n "$windows_url" ] && echo "Windows Label: ${GUEST_WINDOWS_LABELS[$branch]:-}"
}

# Module loaded indicator
module_init "guest-drivers.sh"
