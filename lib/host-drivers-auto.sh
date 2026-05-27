# lib/host-drivers-auto.sh - Auto-discover and download host drivers from alist
#
# Base path on mirror: /foxipan/vGPU/{branch}/  (branch = menu version, e.g. 16.9, 17.5)
# Discovery uses alist JSON API (not HTML scraping):
#   GET https://alist.homelabproject.cc/api/fs/list?path=/foxipan/vGPU/{branch}
# Download base:
#   https://alist.homelabproject.cc/d/foxipan/vGPU/{branch}/...
#
# Search order in find_host_driver():
#   1) {branch}/*-vgpu-kvm.run
#   2) {branch}/Host_Drivers/*-vgpu-kvm.run
#   3) {branch}/NVIDIA-GRID-Linux-KVM-*/Host_Drivers/*-vgpu-kvm.run  (excludes .zip names)
#   4) {branch}/NVIDIA-GRID-Linux-KVM-*.zip  (returns URL with |zip suffix for extraction)

_ALIST_API_BASE="https://alist.homelabproject.cc/api/fs/list?path=/foxipan/vGPU"
_ALIST_DL_BASE="https://alist.homelabproject.cc/d/foxipan/vGPU"

# True when alist API JSON indicates list failure.
_alist_list_failed() {
    echo "$1" | grep -qE '"code":(401|403|404|500)'
}

# Extract first JSON "name" field matching a regex (names only, no path).
_alist_first_name() {
    local json="$1"
    local pattern="$2"
    echo "$json" | grep -oP "$pattern" | sed 's/"name":"//;s/"$//' | head -1
}

# Find host driver in alist directory using API
find_host_driver() {
    local version="$1"
    local api_url="${_ALIST_API_BASE}/${version}"

    local main_response
    if ! main_response=$(curl -s "$api_url" 2>/dev/null); then
        return 1
    fi
    if _alist_list_failed "$main_response"; then
        return 1
    fi

    local driver_file zip_file grid_dir response

    # Pre-patched *-vgpu-kvm-custom.run in version root (e.g. 16.9 on alist; skips --apply-patch)
    driver_file=$(echo "$main_response" | grep -oP '"name":"[^"]*NVIDIA-Linux-x86_64-[^"]*-vgpu-kvm-custom\.run"' | sed 's/"name":"//;s/"$//' | grep -vE 'custom_kerl|custom_kernel' | head -1)
    if [ -n "$driver_file" ]; then
        echo "${_ALIST_DL_BASE}/${version}/${driver_file}"
        return 0
    fi

    # .run in version root (uncommon)
    driver_file=$(_alist_first_name "$main_response" '"name":"[^"]*NVIDIA-Linux-x86_64-[^"]*-vgpu-kvm\.run"')
    if [ -n "$driver_file" ]; then
        echo "${_ALIST_DL_BASE}/${version}/${driver_file}"
        return 0
    fi

    # Flat Host_Drivers/ subdirectory
    local host_drivers_url="${_ALIST_API_BASE}/${version}/Host_Drivers"
    if response=$(curl -s "$host_drivers_url" 2>/dev/null) && ! _alist_list_failed "$response"; then
        driver_file=$(_alist_first_name "$response" '"name":"[^"]*NVIDIA-Linux-x86_64-[^"]*-vgpu-kvm\.run"')
        if [ -n "$driver_file" ]; then
            echo "${_ALIST_DL_BASE}/${version}/Host_Drivers/${driver_file}"
            return 0
        fi
    fi

    # Nested NVIDIA-GRID-* directory (must be a folder, not a .zip filename)
    grid_dir=$(echo "$main_response" | grep -oP '"name":"NVIDIA-GRID-Linux-KVM-[^"]+"' | sed 's/"name":"//;s/"$//' | grep -v '\.zip$' | head -1)
    if [ -n "$grid_dir" ]; then
        local nested_url="${_ALIST_API_BASE}/${version}/${grid_dir}/Host_Drivers"
        if response=$(curl -s "$nested_url" 2>/dev/null) && ! _alist_list_failed "$response"; then
            driver_file=$(_alist_first_name "$response" '"name":"[^"]*NVIDIA-Linux-x86_64-[^"]*-vgpu-kvm\.run"')
            if [ -n "$driver_file" ]; then
                echo "${_ALIST_DL_BASE}/${version}/${grid_dir}/Host_Drivers/${driver_file}"
                return 0
            fi
        fi
    fi

    # ZIP-only layouts (16.13, 16.14, 20.1, etc.) — after .run / nested checks
    zip_file=$(_alist_first_name "$main_response" '"name":"[^"]*NVIDIA-GRID-Linux-KVM-[^"]*\.zip"')
    if [ -n "$zip_file" ]; then
        echo "${_ALIST_DL_BASE}/${version}/${zip_file}|zip"
        return 0
    fi

    return 1
}

# Download from alist (direct .run or |zip) and rename to the catalog filename.
install_host_driver_download() {
    local url="$1"
    local expected_filename="$2"
    local output_dir="${3:-.}"
    local downloaded_file=""

    if ! downloaded_file=$(download_host_driver "$url" "$output_dir"); then
        return 1
    fi
    # Keep pre-patched *-custom.run filename; do not rename to the catalog .run name
    if [[ "$(basename "$downloaded_file")" == *-vgpu-kvm-custom.run ]]; then
        chmod +x "$downloaded_file" 2>/dev/null || true
        return 0
    fi
    if [ "$(basename "$downloaded_file")" != "$expected_filename" ]; then
        mv "$downloaded_file" "$output_dir/$expected_filename"
    fi
    chmod +x "$output_dir/$expected_filename" 2>/dev/null || true
    return 0
}

# Resolve catalog URL: pass through real URLs; discover from alist when empty or "auto".
resolve_host_driver_url() {
    local version="$1"
    local url="${2:-}"

    if [ -n "$url" ] && [ "$url" != "auto" ]; then
        echo "$url"
        return 0
    fi

    find_host_driver "$version"
}

# Download and extract host driver
# Status messages go to stderr; only the final path is printed on stdout (for $(...) callers).
download_host_driver() {
    local url="$1"
    local output_dir="${2:-.}"
    
    # Check if URL is ZIP format
    if [[ "$url" == *"|zip" ]]; then
        url="${url%|zip}"
        local zip_file="${url##*/}"
        local driver_file
        
        # Check if ZIP already exists and is valid
        if [ -f "$output_dir/$zip_file" ]; then
            echo -e "${YELLOW}[-]${NC} ZIP file already exists, checking validity..." >&2
            if unzip -t "$output_dir/$zip_file" >/dev/null 2>&1; then
                echo -e "${GREEN}[+]${NC} ZIP file is valid, skipping download" >&2
                # Extract if not already extracted
                driver_file=$(find "$output_dir" -name "*-vgpu-kvm.run" -type f 2>/dev/null | head -1)
                if [ -n "$driver_file" ]; then
                    echo "${output_dir}/$(basename "$driver_file")"
                    return 0
                fi
                # Extract if needed
                unzip -q -o "$output_dir/$zip_file" -d "$output_dir" 2>/dev/null
                driver_file=$(find "$output_dir" -name "*-vgpu-kvm.run" -type f 2>/dev/null | head -1)
                if [ -n "$driver_file" ] && [ "$(dirname "$driver_file")" != "$output_dir" ]; then
                    mv "$driver_file" "$output_dir/"
                fi
                echo "${output_dir}/$(basename "$driver_file")"
                return 0
            else
                echo -e "${YELLOW}[-]${NC} ZIP file is corrupted, re-downloading..." >&2
                rm -f "$output_dir/$zip_file"
            fi
        fi
        
        echo -e "${YELLOW}[-]${NC} This will take a while, downloading ZIP: $zip_file" >&2
        
        if ! wget -O "$output_dir/$zip_file" "$url"; then
            echo -e "${RED}[!]${NC} Failed to download $zip_file" >&2
            return 1
        fi
        
        echo -e "${YELLOW}[-]${NC} Extracting vgpu-kvm.run from ZIP..." >&2
        if ! unzip -q -o "$output_dir/$zip_file" -d "$output_dir" 2>/dev/null; then
            echo -e "${RED}[!]${NC} Failed to extract ZIP" >&2
            rm -f "$output_dir/$zip_file"
            return 1
        fi
        
        # Find extracted vgpu-kvm.run in Host_Drivers subdirectory
        driver_file=$(find "$output_dir" -name "*-vgpu-kvm.run" -type f 2>/dev/null | head -1)
        if [ -z "$driver_file" ]; then
            echo -e "${RED}[!]${NC} vgpu-kvm.run not found in ZIP" >&2
            rm -f "$output_dir/$zip_file"
            return 1
        fi
        
        # Move to output directory root if in subdirectory
        if [ "$(dirname "$driver_file")" != "$output_dir" ]; then
            mv "$driver_file" "$output_dir/"
        fi
        rm -f "$output_dir/$zip_file"
        
        echo "${output_dir}/$(basename "$driver_file")"
        return 0
    else
        # Direct download
        local driver_file="${url##*/}"
        
        # Check if file already exists and is executable
        if [ -f "$output_dir/$driver_file" ]; then
            echo -e "${YELLOW}[-]${NC} Driver file already exists, checking validity..." >&2
            if [ -x "$output_dir/$driver_file" ]; then
                echo -e "${GREEN}[+]${NC} Driver file is valid, skipping download" >&2
                echo "$output_dir/$driver_file"
                return 0
            else
                echo -e "${YELLOW}[-]${NC} Driver file exists but not executable, re-downloading..." >&2
                rm -f "$output_dir/$driver_file"
            fi
        fi
        
        echo -e "${YELLOW}[-]${NC} Downloading: $driver_file" >&2
        
        if ! wget -O "$output_dir/$driver_file" "$url"; then
            echo -e "${RED}[!]${NC} Failed to download $driver_file" >&2
            return 1
        fi
        
        echo "$output_dir/$driver_file"
        return 0
    fi
}

# Module loaded indicator
module_init "host-drivers-auto.sh"
