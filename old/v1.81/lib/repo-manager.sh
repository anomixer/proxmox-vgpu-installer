#!/bin/bash
# lib/repo-manager.sh - APT repository management
# Part of proxmox-vgpu-installer v1.81
# Handles Proxmox repository configuration (*.list and *.sources formats)

# Detect OS codename
detect_os_codename() {
    local codename=""

    if [ -r /etc/os-release ]; then
        codename=$(awk -F= '$1 == "VERSION_CODENAME" {print $2}' /etc/os-release | tr -d '"')
    fi

    if [ -z "$codename" ]; then
        case "$major_version" in
            9) codename="trixie" ;;
            8) codename="bookworm" ;;
            7) codename="bullseye" ;;
        esac
    fi

    echo "$codename"
}

# Check if system is trixie or newer (supports *.sources format)
is_trixie_or_newer() {
    local codename="$1"
    
    case "$codename" in
        trixie)
            return 0
            ;;
        *)
            # If version cannot be identified, conservatively assume it's an older version
            return 1
            ;;
    esac
}

# Create traditional *.list format repository
create_legacy_list_repo() {
    local repo_name="$1"
    local repo_line="$2"
    
    log_info "Configuring ${repo_name} repository (legacy *.list format): ${repo_line}"
    printf '%s\n' "$repo_line" > "/etc/apt/sources.list.d/${repo_name}.list"
}

# Create new *.sources format repository
create_sources_repo() {
    local repo_name="$1"
    local uri="$2"
    local suite="$3"
    local components="$4"
    
    log_info "Configuring ${repo_name} repository (modern *.sources format)"
    
    local sources_file="/etc/apt/sources.list.d/${repo_name}.sources"
    
    cat > "$sources_file" <<EOF
Types: deb
URIs: ${uri}
Suites: ${suite}
Components: ${components}
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    
    chmod 644 "$sources_file"
}

# Modify existing *.sources file to change components (for Trixie)
modify_sources_components() {
    local sources_file="$1"
    local new_components="$2"
    
    if [ ! -f "$sources_file" ]; then
        log_warn "File $sources_file does not exist, cannot modify"
        return 1
    fi
    
    log_info "Modifying $(basename "$sources_file") to use components: ${new_components}"
    
    # Backup original file (suffix with .bak so apt silently ignores it)
    cp "$sources_file" "${sources_file}.$(date +%s).bak"
    
    # Replace Components line
    sed -i "s/^Components:.*/Components: ${new_components}/" "$sources_file"
    
    # Ensure Enabled is not set to false
    sed -i '/^Enabled: false/d' "$sources_file"
    
    log_info "Modified $(basename "$sources_file") successfully"
}

# Add no-subscription entry to existing *.sources file (for Trixie)
add_nosubscription_to_sources() {
    local sources_file="$1"
    local uri="$2"
    local suite="$3"
    local components="$4"
    
    if [ ! -f "$sources_file" ]; then
        log_warn "File $sources_file does not exist, cannot modify"
        return 1
    fi
    
    log_info "Adding no-subscription repository to $(basename "$sources_file")"
    
    # Backup original file (suffix with .bak so apt silently ignores it)
    cp "$sources_file" "${sources_file}.$(date +%s).bak"
    
    # Check if no-subscription entry already exists
    if grep -q "Components: ${components}" "$sources_file"; then
        log_info "No-subscription entry already exists in $(basename "$sources_file")"
        return 0
    fi
    
    # Disable enterprise entry by adding "Enabled: false" if not present
    if ! grep -q "^Enabled: false" "$sources_file"; then
        # Add Enabled: false after the first Signed-By line
        awk '/^Signed-By:/ && !done {print; print "Enabled: false"; done=1; next} 1' "$sources_file" > "${sources_file}.tmp"
        mv "${sources_file}.tmp" "$sources_file"
        log_info "Disabled enterprise repository in $(basename "$sources_file")"
    fi
    
    # Add no-subscription entry at the end
    cat >> "$sources_file" <<EOF

Types: deb
URIs: ${uri}
Suites: ${suite}
Components: ${components}
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    
    log_info "Added no-subscription repository to $(basename "$sources_file")"
}

# Disable enterprise repository
disable_enterprise_repo() {
    local repo_file="$1"
    
    if [ -f "$repo_file" ]; then
        log_warn "Disabling enterprise repository entries in $(basename "$repo_file")"
        
        # Check if it's a *.sources format file
        if [[ "$repo_file" == *.sources ]]; then
            # For *.sources format, add Enabled: false if not present
            if ! grep -q "^Enabled: false" "$repo_file"; then
                echo "Enabled: false" >> "$repo_file"
                log_info "Added 'Enabled: false' to $(basename "$repo_file")"
            else
                log_info "'Enabled: false' already present in $(basename "$repo_file")"
            fi
        else
            # For *.list format, comment out deb lines
            sed -i 's/^[[:space:]]*deb/# &/' "$repo_file"
            
            # If file becomes fully commented, consider deletion or renaming
            if grep -q '^[^#]' "$repo_file" 2>/dev/null; then
                return 0  # Still has uncommented entries, keep file
            else
                log_warn "Enterprise repository completely disabled, backing up to ${repo_file}.disabled"
                mv "$repo_file" "${repo_file}.disabled"
            fi
        fi
    fi
}

# Configure Proxmox repositories
configure_proxmox_repos() {
    local codename
    codename=$(detect_os_codename)

    if [ -z "$codename" ]; then
        log_error "Unable to determine Debian codename for this Proxmox host."
        exit 1
    fi

    log_info "Detected system codename: ${codename}"
    
    # Check if system supports *.sources format
    local use_sources_format=false
    if is_trixie_or_newer "$codename"; then
        use_sources_format=true
        log_info "System supports modern *.sources repository format"
    else
        log_warn "Using legacy *.list repository format for compatibility"
    fi

    # Handle PVE repository
    local pve_uri="http://download.proxmox.com/debian/pve"
    local pve_components="pve-no-subscription"
    
    if [ "$use_sources_format" = true ]; then
        # Check which default file exists: proxmox.sources or pve-enterprise.sources
        local pve_sources_file=""
        if [ -f "/etc/apt/sources.list.d/proxmox.sources" ]; then
            pve_sources_file="/etc/apt/sources.list.d/proxmox.sources"
        elif [ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ]; then
            pve_sources_file="/etc/apt/sources.list.d/pve-enterprise.sources"
        fi

        if [ -n "$pve_sources_file" ]; then
            log_info "Adding no-subscription repository to $pve_sources_file"
            add_nosubscription_to_sources "$pve_sources_file" "$pve_uri" "$codename" "$pve_components"
            
            # Remove standalone files/duplicates
            if [ -f "/etc/apt/sources.list.d/pve-no-subscription.sources" ]; then
                log_warn "Removing standalone pve-no-subscription.sources to prevent duplicates"
                rm -f "/etc/apt/sources.list.d/pve-no-subscription.sources"
            fi
            if [ "$pve_sources_file" = "/etc/apt/sources.list.d/pve-enterprise.sources" ] && [ -f "/etc/apt/sources.list.d/proxmox.sources" ]; then
                log_warn "Removing standalone proxmox.sources to prevent duplicates"
                rm -f "/etc/apt/sources.list.d/proxmox.sources"
            fi
            if [ "$pve_sources_file" = "/etc/apt/sources.list.d/proxmox.sources" ] && [ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ]; then
                log_warn "Removing standalone pve-enterprise.sources to prevent duplicates"
                rm -f "/etc/apt/sources.list.d/pve-enterprise.sources"
            fi
        else
            # If neither exists, create pve-no-subscription.sources
            log_warn "No default PVE sources file found, creating pve-no-subscription.sources"
            create_sources_repo "pve-no-subscription" "$pve_uri" "$codename" "$pve_components"
        fi
        
        # Clean up legacy list file if present
        if [ -f "/etc/apt/sources.list.d/pve-no-subscription.list" ]; then
            rm -f "/etc/apt/sources.list.d/pve-no-subscription.list"
        fi
    else
        # For older versions: Use traditional *.list format
        local pve_line="deb ${pve_uri} ${codename} ${pve_components}"
        create_legacy_list_repo "pve-no-subscription" "$pve_line"
        
        # Disable enterprise repository
        disable_enterprise_repo "/etc/apt/sources.list.d/pve-enterprise.list"
    fi

    # Handle Ceph repository
    local ceph_uri=""
    local ceph_components="no-subscription"
    
    case "$codename" in
        bullseye)
            ceph_uri="http://download.proxmox.com/debian/ceph-pacific"
            ;;
        bookworm)
            ceph_uri="http://download.proxmox.com/debian/ceph-quincy"
            ;;
        trixie)
            ceph_uri="http://download.proxmox.com/debian/ceph-squid"
            ;;
    esac
    
    if [ -n "$ceph_uri" ]; then
        if [ "$use_sources_format" = true ]; then
            # For Trixie: Add no-subscription to ceph.sources
            if [ -f "/etc/apt/sources.list.d/ceph.sources" ]; then
                log_info "Adding no-subscription repository to ceph.sources"
                add_nosubscription_to_sources "/etc/apt/sources.list.d/ceph.sources" "$ceph_uri" "$codename" "$ceph_components"
                
                # Remove standalone ceph-no-subscription.sources if it exists
                if [ -f "/etc/apt/sources.list.d/ceph-no-subscription.sources" ]; then
                    log_warn "Removing standalone ceph-no-subscription.sources to prevent duplicates"
                    rm -f "/etc/apt/sources.list.d/ceph-no-subscription.sources"
                fi
            else
                # If ceph.sources doesn't exist, create ceph-no-subscription.sources
                log_warn "ceph.sources not found, creating ceph-no-subscription.sources"
                create_sources_repo "ceph-no-subscription" "$ceph_uri" "$codename" "$ceph_components"
            fi
            
            # Clean up legacy list file if present
            if [ -f "/etc/apt/sources.list.d/ceph-no-subscription.list" ]; then
                rm -f "/etc/apt/sources.list.d/ceph-no-subscription.list"
            fi
        else
            # For older versions: Use traditional *.list format
            local ceph_line="deb ${ceph_uri} ${codename} no-subscription"
            create_legacy_list_repo "ceph-no-subscription" "$ceph_line"
            
            # Disable Ceph enterprise repository
            disable_enterprise_repo "/etc/apt/sources.list.d/ceph.list"
        fi
    else
        log_warn "No Ceph repository configuration found for codename ${codename}."
    fi

    # Clean up legacy backup files that have invalid extensions (e.g. *.bak.12345)
    # which cause apt update to emit annoying "Ignoring file" notices.
    if ls /etc/apt/sources.list.d/*.sources.bak.* /etc/apt/sources.list.d/*.list.bak.* >/dev/null 2>&1; then
        log_info "Cleaning up old repository backup files with invalid extensions..."
        rm -f /etc/apt/sources.list.d/*.sources.bak.* /etc/apt/sources.list.d/*.list.bak.*
    fi
}

# Check if repository file exists
repo_file_exists() {
    local repo_name="$1"
    [ -f "/etc/apt/sources.list.d/${repo_name}.list" ] || [ -f "/etc/apt/sources.list.d/${repo_name}.sources" ]
}

# Remove repository
remove_repo() {
    local repo_name="$1"
    
    if [ -f "/etc/apt/sources.list.d/${repo_name}.list" ]; then
        rm -f "/etc/apt/sources.list.d/${repo_name}.list"
        log_info "Removed ${repo_name}.list"
    fi
    
    if [ -f "/etc/apt/sources.list.d/${repo_name}.sources" ]; then
        rm -f "/etc/apt/sources.list.d/${repo_name}.sources"
        log_info "Removed ${repo_name}.sources"
    fi
}

# Module loaded indicator
module_init "repo-manager.sh"
