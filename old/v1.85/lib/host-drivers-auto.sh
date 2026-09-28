# lib/host-drivers-auto.sh - Auto-discover and download host drivers from alist
#
# Base path on mirror: /foxipan/vGPU/{branch}/  (branch = menu version, e.g. 16.9, 17.5)
# Discovery uses alist JSON API (not HTML scraping):
#   GET https://alist.homelabproject.cc/api/fs/list?path=/foxipan/vGPU/{branch}
# Download base (the /p/ proxy route streams the file; /d/ is the share page):
#   https://alist.homelabproject.cc/p/foxipan/vGPU/{branch}/...
#
# Search order in find_host_driver():
#   1) {branch}/*-vgpu-kvm.run
#   2) {branch}/Host_Drivers/*-vgpu-kvm.run
#   3) {branch}/NVIDIA-GRID-Linux-KVM-*/Host_Drivers/*-vgpu-kvm.run  (excludes .zip names)
#   4) {branch}/NVIDIA-GRID-Linux-KVM-*.zip  (returns URL with |zip suffix for extraction)

_ALIST_API_BASE="https://alist.homelabproject.cc/api/fs/list?path=/foxipan/vGPU"
_ALIST_DL_BASE="https://alist.homelabproject.cc/p/foxipan/vGPU"

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
host_driver_is_html() {
    local file="$1"
    [ -f "$file" ] || return 1
    LC_ALL=C head -c 8192 "$file" 2>/dev/null | grep -aEiq '<!doctype[[:space:]]+html|<html([[:space:]>])|CrowdSec Challenge'
}

validate_host_driver_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo -e "${RED}[!]${NC} Host driver file not found: $file" >&2
        return 1
    fi
    if host_driver_is_html "$file"; then
        echo -e "${RED}[!]${NC} $file contains an HTML page, not an NVIDIA driver." >&2
        echo -e "${YELLOW}[-]${NC} The download server may have returned a CrowdSec/security challenge page." >&2
        echo -e "${YELLOW}[-]${NC} Remove this file and download the driver from an accessible source, or ask the mirror owner to allow direct downloads." >&2
        return 1
    fi
    return 0
}

# Return the full-package ZIP URL for a branch (single file covering everything).
_find_branch_zip_url() {
    local branch="$1"
    [ -n "$branch" ] || return 1
    local response zip_name
    response=$(curl -s "${_ALIST_API_BASE}/${branch}" 2>/dev/null) || return 1
    zip_name=$(echo "$response" | grep -oP '"name":"NVIDIA-GRID-Linux-KVM-[^"]*\.zip"' | sed 's/"name":"//;s/"$//' | head -1)
    [ -n "$zip_name" ] || return 1
    echo "${_ALIST_DL_BASE}/${branch}/${zip_name}"
}

# Print step-by-step manual-download guidance when the mirror answered a
# CrowdSec challenge instead of the driver. Recommends the full branch ZIP
# (single file) for host drivers, and prints the exact SCP command to bring the
# file back to this Proxmox host. recommend_zip: auto|0|1.
print_manual_download_guidance() {
    local url="$1"
    local expected_filename="$2"
    local output_dir="${3:-.}"
    local recommend_zip="${4:-auto}"

    local host_ip
    host_ip=$(get_primary_ip)
    if [ -z "$host_ip" ]; then
        host_ip="<this-host-ip>"
    fi

    # Non-alist URLs: generic guidance only.
    if [[ "$url" != https://alist.homelabproject.cc/p/* ]]; then
        echo -e "" >&2
        echo -e "${YELLOW}[-]${NC} Download ${expected_filename} manually in a browser, then re-run with --file." >&2
        return 0
    fi

    local rec_url="$url"
    local rec_name="$(basename "$url")"
    local rec_kind="driver file"
    local is_zip=0

    if [[ "$url" == *"|zip" ]]; then
        rec_url="${url%|zip}"
        rec_name="$(basename "$rec_url")"
        is_zip=1
    elif [ "$recommend_zip" = "1" ] || { [ "$recommend_zip" = "auto" ] && [[ "$expected_filename" != *-vgpu-kvm-custom.run ]]; }; then
        # Pre-patched *-custom.run is already a single file; do not suggest the ZIP.
        local branch zip_url
        branch=$(echo "$url" | sed -E 's#.*/vGPU/([^/]+)/.*#\1#')
        if [ -n "$branch" ] && zip_url=$(_find_branch_zip_url "$branch"); then
            rec_url="$zip_url"
            rec_name="$(basename "$zip_url")"
            is_zip=1
        fi
    fi

    if [ "$is_zip" = "1" ]; then
        rec_kind="full driver package (ZIP)"
    fi

    local scp_user="${USER:-root}"
    local scp_dir="$output_dir"
    if [ "$scp_dir" = "." ]; then
        scp_dir="$(pwd)"
    fi
    echo -e "" >&2
    echo -e "${RED}[!]${NC} This download is protected by CrowdSec; the server returned an HTML challenge instead of the driver." >&2
    echo -e "${YELLOW}[-]${NC} Please download the ${rec_kind} manually in a browser:" >&2
    echo -e "${BLUE}[i]${NC}   ${rec_url}" >&2
    echo -e "" >&2
    echo -e "${YELLOW}[-]${NC} Then copy it back to this Proxmox host. Run this on the machine that downloaded it:" >&2
    echo -e "${BLUE}[i]${NC}   scp ${rec_name} ${scp_user}@${host_ip}:${scp_dir}/" >&2
    echo -e "" >&2
    echo -e "${YELLOW}[-]${NC} After copying, re-run the installer; it will detect the file and continue automatically." >&2
    if [ "$is_zip" = "1" ]; then
        echo -e "${YELLOW}[-]${NC} (For a ZIP, the installer will extract the host .run automatically.)" >&2
    fi
}

install_host_driver_download() {
    local url="$1"
    local expected_filename="$2"
    local output_dir="${3:-.}"
    local downloaded_file=""

    # If the expected .run is missing but the user placed a full-package ZIP
    # here (manual CrowdSec download flow), extract the host driver from it.
    if [ ! -f "$output_dir/$expected_filename" ] && [[ "$expected_filename" != *-vgpu-kvm-custom.run ]]; then
        local manual_zip extracted
        manual_zip=$(find "$output_dir" -maxdepth 1 -type f -name "NVIDIA-GRID-Linux-KVM-*.zip" -print -quit 2>/dev/null)
        if [ -n "$manual_zip" ] && unzip -t "$manual_zip" >/dev/null 2>&1; then
            unzip -q -o "$manual_zip" -d "$output_dir" 2>/dev/null || true
            extracted=$(find "$output_dir" -maxdepth 3 -name "*-vgpu-kvm.run" -type f -print -quit 2>/dev/null)
            if [ -n "$extracted" ]; then
                if [ "$(basename "$extracted")" != "$expected_filename" ]; then
                    mv "$extracted" "$output_dir/$expected_filename"
                fi
                rm -f "$manual_zip"
                chmod +x "$output_dir/$expected_filename" 2>/dev/null || true
                echo -e "${GREEN}[+]${NC} Extracted host driver from manually-downloaded ZIP: $output_dir/$expected_filename"
                return 0
            fi
        fi
    fi

    if ! downloaded_file=$(download_host_driver "$url" "$output_dir"); then
        print_manual_download_guidance "$url" "$expected_filename" "$output_dir" auto
        return 1
    fi
    if ! validate_host_driver_file "$downloaded_file"; then
        rm -f "$downloaded_file"
        print_manual_download_guidance "$url" "$expected_filename" "$output_dir" auto
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
                if validate_host_driver_file "$output_dir/$driver_file"; then
                    echo -e "${GREEN}[+]${NC} Driver file is valid, skipping download" >&2
                    echo "$output_dir/$driver_file"
                    return 0
                fi
                echo -e "${YELLOW}[-]${NC} Removing invalid cached driver file and retrying the download..." >&2
                rm -f "$output_dir/$driver_file"
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

        if ! validate_host_driver_file "$output_dir/$driver_file"; then
            rm -f "$output_dir/$driver_file"
            return 1
        fi
        
        echo "$output_dir/$driver_file"
        return 0
    fi
}

# Module loaded indicator
module_init "host-drivers-auto.sh"
