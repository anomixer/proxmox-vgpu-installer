#!/bin/bash
# lib/gpu-detect.sh - GPU detection and compatibility checking
# Part of proxmox-vgpu-installer v1.84
# Handles GPU detection, database queries, and vGPU capability assessment

# Query GPU information from database
query_gpu_info() {
    local gpu_device_id="$1"
    
    if [ ! -f "gpu_info.db" ]; then
        log_error "GPU database not found: gpu_info.db"
        return 1
    fi
    
    local query_result=""
    if command -v sqlite3 >/dev/null 2>&1; then
        query_result=$(sqlite3 gpu_info.db "SELECT * FROM gpu_info WHERE deviceid='$gpu_device_id';" 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        query_result=$(python3 -c "import sqlite3; conn = sqlite3.connect('gpu_info.db'); cur = conn.cursor(); cur.execute(\"SELECT * FROM gpu_info WHERE deviceid='$gpu_device_id'\"); r = cur.fetchone(); print('|'.join(str(x) if x is not None else '' for x in r) if r else '')" 2>/dev/null)
    else
        log_error "Neither 'sqlite3' CLI nor 'python3' with sqlite3 is available to query the database."
        return 1
    fi
    
    echo "$query_result"
}

# Parse GPU query result
parse_gpu_info() {
    local query_result="$1"
    
    if [ -z "$query_result" ]; then
        return 1
    fi
    
    # Parse fields: vendorid|deviceid|description|vgpu|driver|chip
    local vendor_id=$(echo "$query_result" | cut -d '|' -f 1)
    local device_id=$(echo "$query_result" | cut -d '|' -f 2)
    local description=$(echo "$query_result" | cut -d '|' -f 3)
    local vgpu=$(echo "$query_result" | cut -d '|' -f 4)
    local driver=$(echo "$query_result" | cut -d '|' -f 5 | tr ';' ',')
    local chip=$(echo "$query_result" | cut -d '|' -f 6)
    
    # Set default for empty chip
    if [ -z "$chip" ]; then
        chip="Unknown"
    fi
    
    # Export as environment variables for easy access
    export GPU_VENDOR_ID="$vendor_id"
    export GPU_DEVICE_ID="$device_id"
    export GPU_DESCRIPTION="$description"
    export GPU_VGPU_SUPPORT="$vgpu"
    export GPU_DRIVER_VERSION="$driver"
    export GPU_CHIP="$chip"
    
    return 0
}

# Detect NVIDIA GPUs in the system
detect_nvidia_gpus() {
    local gpu_info
    gpu_info=$(lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)' || true)
    
    if [ -z "$gpu_info" ]; then
        return 1
    fi
    
    echo "$gpu_info"
    return 0
}

# Count NVIDIA GPUs
count_nvidia_gpus() {
    local gpu_info
    gpu_info=$(detect_nvidia_gpus)
    
    if [ -z "$gpu_info" ]; then
        echo "0"
    else
        echo "$gpu_info" | wc -l
    fi
}

# Extract device ID from lspci output
extract_device_id() {
    local lspci_line="$1"
    echo "$lspci_line" | grep -oE '\[10de:[0-9a-fA-F]{2,4}\]' | cut -d ':' -f 2 | tr -d ']'
}

# Extract PCI ID from lspci output
extract_pci_id() {
    local lspci_line="$1"
    echo "$lspci_line" | awk '{print $1}'
}

# Get vGPU support level description
get_vgpu_support_description() {
    local vgpu_support="$1"
    local driver_version="$2"
    
    case "$vgpu_support" in
        "Native")
            echo "supports native vGPU with driver version $driver_version"
            ;;
        "Yes")
            echo "is vGPU capable through vgpu_unlock with driver version $driver_version"
            ;;
        "No")
            echo "is not vGPU capable"
            ;;
        "Unknown")
            echo "has unknown vGPU capability"
            ;;
        *)
            echo "has unrecognized vGPU status: $vgpu_support"
            ;;
    esac
}

# Prompt user for manual override when GPU is unsupported or missing from database
prompt_gpu_override() {
    local device_id="$1"
    local desc="${2:-NVIDIA GPU [10de:$device_id]}"
    local is_missing_from_db="$3"

    echo ""
    echo -e "${YELLOW}[!] WARNING: Card [10de:$device_id] - $desc${NC}"
    if [ "$is_missing_from_db" = "true" ]; then
        echo -e "${YELLOW}[!] This card is NOT registered in gpu_info.db.${NC}"
    else
        echo -e "${YELLOW}[!] This card is currently marked as unsupported ('No') in gpu_info.db.${NC}"
    fi
    echo -e "${YELLOW}[!] Note: vgpu_unlock uses runtime PCI ID range spoofing (Maxwell, Pascal, Turing, Ampere, etc.).${NC}"
    echo -e "${YELLOW}[!] Even if not registered or marked unsupported, cards sharing a chip family with supported cards may still work!${NC}"
    echo ""

    if confirm_action "Do you want to force enable vgpu_unlock mode for this card (at your own risk)?"; then
        export GPU_VENDOR_ID="10de"
        export GPU_DEVICE_ID="$device_id"
        export GPU_DESCRIPTION="$desc (Manual Override)"
        export GPU_VGPU_SUPPORT="Yes"
        export GPU_DRIVER_VERSION="${GPU_DRIVER_VERSION:-17,16,15}"
        export GPU_CHIP="${GPU_CHIP:-Unknown}"

        export VGPU_SUPPORT="Yes"
        export DRIVER_VERSION="$GPU_DRIVER_VERSION"
        log_info "Manual override enabled: vgpu_unlock set to Yes for device 10de:$device_id"
        return 0
    else
        log_warn "Manual override declined. Setting vGPU support to No."
        export VGPU_SUPPORT="No"
        export DRIVER_VERSION="${GPU_DRIVER_VERSION:-17,16,15}"
        return 0
    fi
}

# Detect single GPU and set global variables
detect_single_gpu() {
    local gpu_info
    gpu_info=$(detect_nvidia_gpus)
    
    if [ -z "$gpu_info" ]; then
        log_error "No NVIDIA GPU found in system"
        return 1
    fi
    
    if [ $(echo "$gpu_info" | wc -l) -ne 1 ]; then
        log_error "Multiple GPUs detected, use detect_multiple_gpus instead"
        return 1
    fi
    
    # Extract device ID
    local gpu_device_id
    gpu_device_id=$(extract_device_id "$gpu_info")
    
    # Query database
    local query_result
    query_result=$(query_gpu_info "$gpu_device_id")
    
    if [ -z "$query_result" ]; then
        log_warn "Device ID 10de:$gpu_device_id not found in gpu_info.db"
        local extracted_desc
        extracted_desc=$(echo "$gpu_info" | sed -E 's/.*Controller \[[0-9a-fA-F]{4}\]: NVIDIA Corporation (.*) \[10de:[0-9a-fA-F]{2,4}\].*/\1/' || true)
        if [ -z "$extracted_desc" ]; then
            extracted_desc="NVIDIA GPU [10de:$gpu_device_id]"
        fi
        
        prompt_gpu_override "$gpu_device_id" "$extracted_desc" "true"
        return $?
    fi
    
    # Parse GPU info
    parse_gpu_info "$query_result"
    
    # Display GPU info
    log_info "Found one NVIDIA GPU in your system"
    echo ""
    echo "GPU: $GPU_DESCRIPTION"
    echo "Chip: $GPU_CHIP"
    echo "Status: $(get_vgpu_support_description "$GPU_VGPU_SUPPORT" "$GPU_DRIVER_VERSION")"
    echo ""
    if [[ "$GPU_VGPU_SUPPORT" == "Yes" ]]; then
        echo -e "${YELLOW}[!] Your card should be vGPU Unlock Capable, but it does not guarantee a successful installation. Please use at your own risk.${NC}"
        echo -e "${YELLOW}[!] We hope users will provide feedback to help make the gpu_info.db database more complete.${NC}"
        export VGPU_SUPPORT="$GPU_VGPU_SUPPORT"
        export DRIVER_VERSION="$GPU_DRIVER_VERSION"
    elif [[ "$GPU_VGPU_SUPPORT" == "No" || "$GPU_VGPU_SUPPORT" == "Unknown" ]]; then
        prompt_gpu_override "$gpu_device_id" "$GPU_DESCRIPTION" "false"
    else
        export VGPU_SUPPORT="$GPU_VGPU_SUPPORT"
        export DRIVER_VERSION="$GPU_DRIVER_VERSION"
    fi
    
    return 0
}

# Detect multiple GPUs and prompt for selection
detect_multiple_gpus() {
    local gpu_devices
    gpu_devices=$(lspci -nn | grep -Ei '(VGA compatible controller|3D controller).*NVIDIA Corporation' || true)
    
    if [ -z "$gpu_devices" ]; then
        log_error "No NVIDIA GPUs found"
        return 1
    fi
    
    # Declare associative array for GPU PCI groups
    declare -A gpu_pci_groups
    
    # Parse GPU devices
    while read -r device; do
        local pci_id=$(extract_pci_id "$device")
        local device_id=$(extract_device_id "$device")
        gpu_pci_groups["$pci_id"]="$device_id"
    done <<< "$gpu_devices"
    
    # Display GPU list
    log_info "Found multiple NVIDIA GPUs in your system"
    echo ""
    
    local index=1
    local best_vgpu_support="Unknown"
    
    for pci_id in "${!gpu_pci_groups[@]}"; do
        local gpu_device_id=${gpu_pci_groups[$pci_id]}
        local query_result=$(query_gpu_info "$gpu_device_id")
        
        if [ -n "$query_result" ]; then
            parse_gpu_info "$query_result"
            
            # Update best vGPU support level
            case "$GPU_VGPU_SUPPORT" in
                "Native")
                    best_vgpu_support="Native"
                    ;;
                "Yes")
                    if [ "$best_vgpu_support" != "Native" ]; then
                        best_vgpu_support="Yes"
                    fi
                    ;;
                "No")
                    if [ "$best_vgpu_support" = "Unknown" ]; then
                        best_vgpu_support="No"
                    fi
                    ;;
            esac
            
            # Display GPU info
            echo "$index: $GPU_DESCRIPTION - $(get_vgpu_support_description "$GPU_VGPU_SUPPORT" "$GPU_DRIVER_VERSION")"
        else
            echo "$index: GPU Device ID: $gpu_device_id on PCI bus 0000:$pci_id (not found in database)"
        fi
        
        ((index++))
    done
    
    echo ""
    
    # Prompt for selection
    log_question "Select the GPU you want to enable vGPU for. All other GPUs will be passed through."
    read -p "$(log_question "Enter the corresponding number: ")" selected_index
    echo ""
    
    # Validate input
    if [[ ! "$selected_index" =~ ^[1-9][0-9]*$ ]] || [ "$selected_index" -ge "$index" ]; then
        log_error "Invalid input. Please enter a number between 1 and $((index-1))."
        return 1
    fi
    
    # Get selected GPU
    index=1
    local selected_pci_id=""
    for pci_id in "${!gpu_pci_groups[@]}"; do
        if [ $index -eq $selected_index ]; then
            selected_pci_id=$pci_id
            break
        fi
        ((index++))
    done
    
    # Query selected GPU
    local gpu_device_id=${gpu_pci_groups[$selected_pci_id]}
    local query_result=$(query_gpu_info "$gpu_device_id")
    
    # Store selected PCI ID and other GPUs for passthrough
    export SELECTED_PCI_ID="$selected_pci_id"
    export -a OTHER_GPU_PCI_IDS=()
    for pci_id in "${!gpu_pci_groups[@]}"; do
        if [ "$pci_id" != "$selected_pci_id" ]; then
            OTHER_GPU_PCI_IDS+=("$pci_id")
        fi
    done

    if [ -z "$query_result" ]; then
        log_warn "Selected GPU Device ID: 10de:$gpu_device_id on PCI bus 0000:$selected_pci_id not found in gpu_info.db"
        local raw_line
        raw_line=$(echo "$gpu_devices" | grep "^$selected_pci_id" || true)
        local extracted_desc
        extracted_desc=$(echo "$raw_line" | sed -E 's/.*Controller \[[0-9a-fA-F]{4}\]: NVIDIA Corporation (.*) \[10de:[0-9a-fA-F]{2,4}\].*/\1/' || true)
        if [ -z "$extracted_desc" ]; then
            extracted_desc="NVIDIA GPU [10de:$gpu_device_id]"
        fi
        
        prompt_gpu_override "$gpu_device_id" "$extracted_desc" "true"
        return $?
    fi
    
    parse_gpu_info "$query_result"
    log_info "You selected GPU: $GPU_DESCRIPTION with Device ID: $gpu_device_id on PCI bus 0000:$selected_pci_id"
    if [[ "$GPU_VGPU_SUPPORT" == "Yes" ]]; then
        echo -e "${YELLOW}[!] Your card should be vGPU Unlock Capable, but it does not guarantee a successful installation. Please use at your own risk.${NC}"
        echo -e "${YELLOW}[!] We hope users will provide feedback to help make the gpu_info.db database more complete.${NC}"
        export VGPU_SUPPORT="$GPU_VGPU_SUPPORT"
        export DRIVER_VERSION="$GPU_DRIVER_VERSION"
    elif [[ "$GPU_VGPU_SUPPORT" == "No" || "$GPU_VGPU_SUPPORT" == "Unknown" ]]; then
        prompt_gpu_override "$gpu_device_id" "$GPU_DESCRIPTION" "false"
    else
        export VGPU_SUPPORT="$GPU_VGPU_SUPPORT"
        export DRIVER_VERSION="$GPU_DRIVER_VERSION"
    fi

    return 0
}

# Main GPU detection function
detect_gpus() {
    local gpu_count
    gpu_count=$(count_nvidia_gpus)
    
    if [ "$gpu_count" -eq 0 ]; then
        log_warn "No NVIDIA GPU found in system"
        if confirm_action "Continue anyway?"; then
            export VGPU_SUPPORT="Unknown"
            return 0
        else
            log_info "Exiting script"
            exit 0
        fi
    elif [ "$gpu_count" -eq 1 ]; then
        detect_single_gpu
    else
        detect_multiple_gpus
    fi
}

# Check if GPU database exists
check_gpu_database() {
    if [ ! -f "gpu_info.db" ]; then
        log_error "GPU database not found: gpu_info.db"
        log_error "Please ensure gpu_info.db is in the same directory as this script"
        return 1
    fi
    
    # Verify it's a valid SQLite database using sqlite3 or python3 fallback
    if command -v sqlite3 >/dev/null 2>&1; then
        if ! sqlite3 gpu_info.db "SELECT COUNT(*) FROM gpu_info;" >/dev/null 2>&1; then
            log_error "GPU database is corrupted or invalid"
            return 1
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import sqlite3; conn = sqlite3.connect('gpu_info.db'); cur = conn.cursor(); cur.execute('SELECT COUNT(*) FROM gpu_info;');" >/dev/null 2>&1; then
            log_error "GPU database is corrupted or invalid"
            return 1
        fi
    else
        log_warn "Neither 'sqlite3' nor 'python3' is available to verify the database structure."
    fi
    
    log_debug "GPU database verified"
    return 0
}

# Module loaded indicator
module_init "gpu-detect.sh"
