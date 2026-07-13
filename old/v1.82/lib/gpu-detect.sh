#!/bin/bash
# lib/gpu-detect.sh - GPU detection and compatibility checking
# Part of proxmox-vgpu-installer v1.82
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
        log_error "Device ID $gpu_device_id not found in database"
        return 1
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
    
    # Set global VGPU_SUPPORT and DRIVER_VERSION
    export VGPU_SUPPORT="$GPU_VGPU_SUPPORT"
    export DRIVER_VERSION="$GPU_DRIVER_VERSION"
    
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
    
    if [ -n "$query_result" ]; then
        parse_gpu_info "$query_result"
        log_info "You selected GPU: $GPU_DESCRIPTION with Device ID: $gpu_device_id on PCI bus 0000:$selected_pci_id"
        
        # Set global variables
        export VGPU_SUPPORT="$GPU_VGPU_SUPPORT"
        export DRIVER_VERSION="$GPU_DRIVER_VERSION"
        export SELECTED_PCI_ID="$selected_pci_id"
        
        # Store other GPUs for passthrough
        export -a OTHER_GPU_PCI_IDS=()
        for pci_id in "${!gpu_pci_groups[@]}"; do
            if [ "$pci_id" != "$selected_pci_id" ]; then
                OTHER_GPU_PCI_IDS+=("$pci_id")
            fi
        done
        
        return 0
    else
        log_error "GPU Device ID: $gpu_device_id not found in the database"
        return 1
    fi
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
