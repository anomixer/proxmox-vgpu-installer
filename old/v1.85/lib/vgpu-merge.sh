#!/bin/bash
# lib/vgpu-merge.sh - Merged driver builder (vGPU-Unlock-Patcher integration)
# Part of proxmox-vgpu-installer v1.85 (experimental, Issue #10)
#
# Backend: https://github.com/greglechin/vGPU-Unlock-Patcher (fork of
# benjamindoron/vGPU-Unlock-Patcher, itself from VGPU-Community-Drivers).
# Each host version needs its own patcher branch + blob diff, so only the
# branches below are supported. This does NOT replace the default
# vgpu-proxmox + vgpu_unlock-rs path (options 1-2); it is an opt-in
# experimental path (menu option 7) for users who need a merged driver
# (host CUDA/OpenGL + vGPU) or unlock on 18.0/19.4/19.5.
#
# Supported matrix (patcher branch -> vGPU branch):
#   550.90  -> 17.3 (legacy / older kernel, per Issue #10 request)
#   570.124 -> 18.0
#   580.126 -> 19.4
#   580.159 -> 19.5 (latest, greglechin)
#
# Modes (passed through to patch.sh):
#   vgpu-kvm     - Proxmox default: no host display needed / secondary GPU
#   general-merge- merged GNRL + VGPU: host CUDA/OpenGL + vGPU (Issue #10)

MERGE_REPO_URL="${MERGE_REPO_URL:-https://github.com/greglechin/vGPU-Unlock-Patcher.git}"
MERGE_FALLBACK_URL="https://github.com/benjamindoron/vGPU-Unlock-Patcher.git"

# Ordered list for menu display
MERGE_ORDER=("550.90" "570.124" "580.126" "580.159")

# Declare catalog maps (global, populated once)
declare -gA MERGE_VGPU_BRANCH=()
declare -gA MERGE_VGPU_RUN=()
declare -gA MERGE_GNRL_RUN=()
declare -gA MERGE_GRID_RUN=()
declare -gA MERGE_LABEL=()

_merge_catalog_loaded=0

merge_load_catalog() {
    if [ "$_merge_catalog_loaded" = "1" ]; then
        return 0
    fi
    MERGE_VGPU_BRANCH["550.90"]="17.3"
    MERGE_VGPU_RUN["550.90"]="NVIDIA-Linux-x86_64-550.90.05-vgpu-kvm.run"
    MERGE_GNRL_RUN["550.90"]="NVIDIA-Linux-x86_64-550.90.07.run"
    MERGE_GRID_RUN["550.90"]="NVIDIA-Linux-x86_64-550.90.07-grid.run"
    MERGE_LABEL["550.90"]="17.3-legacy (550.90.05, older kernel per Issue #10)"

    MERGE_VGPU_BRANCH["570.124"]="18.0"
    MERGE_VGPU_RUN["570.124"]="NVIDIA-Linux-x86_64-570.124.03-vgpu-kvm.run"
    MERGE_GNRL_RUN["570.124"]="NVIDIA-Linux-x86_64-570.124.04.run"
    MERGE_GRID_RUN["570.124"]="NVIDIA-Linux-x86_64-570.124.06-grid.run"
    MERGE_LABEL["570.124"]="18.0 (570.124.03, unlock beyond 17.6)"

    MERGE_VGPU_BRANCH["580.126"]="19.4"
    MERGE_VGPU_RUN["580.126"]="NVIDIA-Linux-x86_64-580.126.08-vgpu-kvm.run"
    MERGE_GNRL_RUN["580.126"]="NVIDIA-Linux-x86_64-580.126.09.run"
    MERGE_GRID_RUN["580.126"]="NVIDIA-Linux-x86_64-580.126.09-grid.run"
    MERGE_LABEL["580.126"]="19.4 (580.126.08)"

    MERGE_VGPU_BRANCH["580.159"]="19.5"
    MERGE_VGPU_RUN["580.159"]="NVIDIA-Linux-x86_64-580.159.01-vgpu-kvm.run"
    MERGE_GNRL_RUN["580.159"]="NVIDIA-Linux-x86_64-580.159.03.run"
    MERGE_GRID_RUN["580.159"]="NVIDIA-Linux-x86_64-580.159.03-grid.run"
    MERGE_LABEL["580.159"]="19.5 (580.159.01, latest greglechin)"

    _merge_catalog_loaded=1
}

merge_workdir() {
    local patch_branch="$1"
    printf '%s/vgpu-unlock-patcher-%s' "$VGPU_DIR" "$patch_branch"
}

merge_ensure_deps() {
    local missing=()
    for cmd in git gcc make patch patchelf; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi
    log_warn "Merged build needs missing tools: ${missing[*]}"
    log_info "Installing: patchelf + build deps (gcc/make/patch already in Step 1 base)"
    if ! run_command "Installing merged-build deps" "info" "apt-get update && apt-get install -y patchelf gcc make patch git"; then
        log_error "Failed to install merged-build dependencies."
        return 1
    fi
    return 0
}

merge_clone_patcher() {
    local patch_branch="$1"
    local dest
    dest=$(merge_workdir "$patch_branch")

    if [ -d "$dest/.git" ]; then
        log_info "Patcher checkout exists: $dest (branch $patch_branch)"
        if ! run_command "Updating patcher branch $patch_branch" "info" "git -C \"$dest\" fetch --depth 1 origin \"$patch_branch\" && git -C \"$dest\" checkout \"$patch_branch\" && git -C \"$dest\" submodule update --init --recursive"; then
            log_warn "Patcher update failed, reusing existing checkout."
        fi
        return 0
    fi

    rm -rf "$dest"
    if run_command "Cloning vGPU-Unlock-Patcher ($patch_branch)" "info" "git clone --depth 1 --recursive --branch \"$patch_branch\" \"$MERGE_REPO_URL\" \"$dest\""; then
        return 0
    fi
    log_warn "Primary repo failed, trying fallback: $MERGE_FALLBACK_URL"
    if ! run_command "Cloning fallback patcher ($patch_branch)" "info" "git clone --depth 1 --recursive --branch \"$patch_branch\" \"$MERGE_FALLBACK_URL\" \"$dest\""; then
        log_error "Failed to clone patcher branch $patch_branch from both remotes."
        return 1
    fi
    return 0
}

# Stage a .run file into the patcher dir: prefer installer cwd, then VGPU_DIR.
merge_stage_run() {
    local filename="$1"
    local dest_dir="$2"
    local src=""

    if [ -f "$dest_dir/$filename" ]; then
        echo "$dest_dir/$filename"
        return 0
    fi
    if [ -f "$VGPU_DIR/$filename" ]; then
        src="$VGPU_DIR/$filename"
    elif [ -f "./$filename" ]; then
        src="./$filename"
    fi
    if [ -n "$src" ]; then
        cp -f "$src" "$dest_dir/$filename"
        echo "$dest_dir/$filename"
        return 0
    fi
    return 1
}

merge_prepare_inputs() {
    local patch_branch="$1"
    local mode="$2"
    local dest
    dest=$(merge_workdir "$patch_branch")

    merge_load_catalog
    local vgpu_run="${MERGE_VGPU_RUN[$patch_branch]:-}"
    local gnrl_run="${MERGE_GNRL_RUN[$patch_branch]:-}"

    if [ -z "$vgpu_run" ] || [ -z "$gnrl_run" ]; then
        log_error "Unknown patcher branch: $patch_branch"
        return 1
    fi

    mkdir -p "$dest"

    # VGPU .run: try local first, else auto-discover from alist via existing module
    if ! merge_stage_run "$vgpu_run" "$dest" >/dev/null; then
        local vgpu_branch="${MERGE_VGPU_BRANCH[$patch_branch]}"
        log_warn "VGPU input missing: $vgpu_run — trying alist auto-discovery (branch $vgpu_branch)..."
        if declare -F resolve_host_driver_url >/dev/null 2>&1; then
            local discovered=""
            discovered=$(resolve_host_driver_url "$vgpu_branch" "auto" 2>/dev/null) || discovered=""
            if [ -n "$discovered" ] && [ "$discovered" != "auto" ]; then
                if declare -F install_host_driver_download >/dev/null 2>&1; then
                    if install_host_driver_download "$discovered" "$vgpu_run" "$dest"; then
                        log_info "Fetched VGPU input via alist."
                    fi
                fi
            fi
        fi
    fi

    if [ ! -f "$dest/$vgpu_run" ]; then
        log_error "Missing VGPU input: $vgpu_run"
        echo -e "${YELLOW}[-]${NC} Place $vgpu_run into $dest (or installer dir),"
        echo -e "${YELLOW}[-]${NC} or download the GRID zip from NVIDIA licensing portal / alist branch ${MERGE_VGPU_BRANCH[$patch_branch]} and extract Host_Drivers/."
        return 1
    fi

    if [ "$mode" = "general-merge" ]; then
        if ! merge_stage_run "$gnrl_run" "$dest" >/dev/null; then
            log_error "Missing GNRL input for general-merge: $gnrl_run"
            echo -e "${YELLOW}[-]${NC} Download the matching consumer/desktop .run ($gnrl_run, e.g. from NVIDIA driver archive)"
            echo -e "${YELLOW}[-]${NC} and place it into $dest (or installer dir), then rerun option 7."
            echo -e "${YELLOW}[-]${NC} Tip: run './patch.sh vgpu-kvm' instead if you don't need host CUDA/OpenGL."
            return 1
        fi
    fi
    return 0
}

merge_select_branch() {
    merge_load_catalog
    echo ""
    echo "Select merged-driver patcher branch (experimental, Issue #10):"
    echo ""
    local i=1
    declare -A _map=()
    local b
    for b in "${MERGE_ORDER[@]}"; do
        printf "%d: %s [%s]\n" "$i" "$b" "${MERGE_LABEL[$b]}"
        _map["$i"]="$b"
        i=$((i + 1))
    done
    echo ""
    local choice=""
    read -r -p "Enter your choice: " choice || choice=""
    choice=$(strip_trailing_carriage_return "$choice")
    MERGE_BRANCH="${_map[$choice]:-}"
    if [ -z "$MERGE_BRANCH" ]; then
        echo -e "${RED}[!]${NC} Invalid choice."
        return 1
    fi
    return 0
}

merge_select_mode() {
    echo ""
    echo "Select patcher target:"
    echo ""
    echo "1: vgpu-kvm (Recommended for Proxmox - no host display needed)"
    echo "2: general-merge (Host CUDA/OpenGL + vGPU, needs extra GNRL .run - Issue #10 request)"
    echo ""
    local choice=""
    read -r -p "Enter your choice [1]: " choice || choice=""
    choice=$(strip_trailing_carriage_return "$choice")
    if [ -z "$choice" ]; then
        choice="1"
    fi
    case "$choice" in
        1) MERGE_MODE="vgpu-kvm" ;;
        2) MERGE_MODE="general-merge" ;;
        *) echo -e "${RED}[!]${NC} Invalid choice."; return 1 ;;
    esac
    return 0
}

merge_run_patch() {
    local patch_branch="$1"
    local mode="$2"
    local dest
    dest=$(merge_workdir "$patch_branch")

    MERGE_PRODUCED=""

    if [ ! -x "$dest/patch.sh" ]; then
        log_error "patch.sh not found/executable in $dest"
        return 1
    fi

    log_warn "Running upstream patch.sh ($mode) — this takes several minutes and logs to $LOG_FILE."
    if ! run_command "Patching merged driver ($patch_branch $mode)" "info" "bash -c 'cd \"$dest\" && ./patch.sh --repack $mode'"; then
        log_error "patch.sh failed."
        show_debug_log_tail 60
        return 1
    fi

    # Locate output: prefer freshly repacked .run, else patched dir with nvidia-installer.
    # NOTE: result is returned via $MERGE_PRODUCED (not stdout) because
    # run_command status lines go to stdout and must not pollute captures.
    local produced=""
    produced=$(find "$dest" -maxdepth 1 -name '*-patched.run' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)
    if [ -n "$produced" ]; then
        MERGE_PRODUCED="$produced"
        return 0
    fi
    # Fallback: patched dir (no --repack output?) -> install from dir
    local target_dir=""
    if [ "$mode" = "general-merge" ]; then
        merge_load_catalog
        local gnrl="${MERGE_GNRL_RUN[$patch_branch]:-}"
        gnrl="${gnrl%.run}"
        target_dir="$dest/${gnrl}-merged-vgpu-kvm-patched"
    else
        merge_load_catalog
        local vgpu="${MERGE_VGPU_RUN[$patch_branch]:-}"
        vgpu="${vgpu%.run}"
        target_dir="$dest/${vgpu}-patched"
    fi
    if [ -x "$target_dir/nvidia-installer" ]; then
        MERGE_PRODUCED="DIR:$target_dir"
        return 0
    fi
    log_error "No patched output found (*-patched.run or $target_dir/nvidia-installer)."
    return 1
}

merge_install_output() {
    local produced="$1"
    local patch_branch="$2"

    local sb_flags=""
    if declare -F build_secure_boot_flags >/dev/null 2>&1; then
        sb_flags=$(build_secure_boot_flags)
    fi
    # Merged/unlock builds must use proprietary modules (same rule as VGPU_SUPPORT=Yes)
    local flags="--dkms -m=kernel -s"
    if [ -n "$sb_flags" ]; then
        flags="$flags $sb_flags"
        echo -e "${GREEN}[+]${NC} Secure Boot signing parameters will be applied."
    fi

    if [[ "$produced" == DIR:* ]]; then
        local d="${produced#DIR:}"
        log_info "Installing from patched directory: $d"
        if ! run_command "Installing merged driver (dir)" "info" "bash -c 'cd \"$d\" && ./nvidia-installer $flags'"; then
            log_error "Merged driver directory install failed."
            show_debug_log_tail 40
            return 1
        fi
    else
        chmod +x "$produced" 2>/dev/null || true
        log_info "Installing repacked driver: $(basename "$produced")"
        if ! run_command "Installing merged driver (run)" "info" "\"$produced\" $flags"; then
            log_error "Merged driver .run install failed (often kernel/DKMS mismatch)."
            show_debug_log_tail 40
            return 1
        fi
        # Keep a copy next to installer for reuse
        cp -f "$produced" "$VGPU_DIR/$(basename "$produced")" 2>/dev/null || true
    fi

    # Persist branch choice for guest-driver lookup + licensing hints
    merge_load_catalog
    set_config_value "DRIVER_VERSION" "${MERGE_VGPU_BRANCH[$patch_branch]:-}" 2>/dev/null || true
    set_config_value "MERGE_BRANCH" "$patch_branch" 2>/dev/null || true
    driver_version="${MERGE_VGPU_BRANCH[$patch_branch]:-}"
    driver_filename="$(basename "$produced")"
    sync_fastapi_flag 2>/dev/null || true
    return 0
}

merge_post_install() {
    # Mirror the tail of perform_step_two: services, nvidia-smi check, guests, licensing, summary
    if systemctl list-unit-files nvidia-vgpud.service >/dev/null 2>&1; then
        run_command "Enable nvidia-vgpud.service" "info" "systemctl enable --now nvidia-vgpud.service" || true
    fi
    if systemctl list-unit-files nvidia-vgpu-mgr.service >/dev/null 2>&1; then
        run_command "Enable nvidia-vgpu-mgr.service" "info" "systemctl enable --now nvidia-vgpu-mgr.service" || true
    fi
    sleep 3
    if command -v nvidia-smi >/dev/null 2>&1; then
        local out=""
        out=$(nvidia-smi 2>&1) || out="nvidia-smi failed"
        if [[ "$out" == *"NVIDIA-SMI has failed"* ]]; then
            echo -e "${RED}[!]${NC} Nvidia driver not properly loaded"
        else
            echo -e "${GREEN}[+]${NC} Nvidia driver properly loaded (merged build)"
        fi
    fi
    if declare -F prompt_guest_driver_downloads >/dev/null 2>&1; then
        prompt_guest_driver_downloads "${driver_version:-}" "${driver_filename:-}" || true
    fi
    if declare -F print_guest_driver_guidance >/dev/null 2>&1; then
        print_guest_driver_guidance "${driver_version:-}" "${driver_filename:-}" || true
    fi
    if declare -F configure_fastapi_dls >/dev/null 2>&1; then
        configure_fastapi_dls || true
    fi
    if declare -F print_installation_summary >/dev/null 2>&1; then
        print_installation_summary "${driver_version:-merged}" "${driver_filename:-merged}" || true
    fi
    return 0
}

build_merged_driver_interactive() {
    merge_load_catalog
    echo ""
    echo -e "${YELLOW}=== Experimental merged driver builder (v1.85, Issue #10) ===${NC}"
    echo -e "${YELLOW}Backend: greglechin/vGPU-Unlock-Patcher. Only 4 branches supported.${NC}"
    echo -e "${YELLOW}Prereq: finish option 1 (Step 1) + reboot FIRST. This REPLACES Step 2 — do NOT run option 2 before/after.${NC}"
    echo -e "${YELLOW}Default unlock path (options 1-2) is unchanged.${NC}"
    echo ""

    if is_kernel_617_or_higher 2>/dev/null; then
        local target_k=""
        if declare -F discover_target_kernel_version >/dev/null 2>&1; then
            target_k=$(discover_target_kernel_version)
        fi
        echo -e "${YELLOW}[-]${NC} Kernel $(uname -r) is 6.17+ / 7.x. Merged 550~580 builds target kernel <= 6.14."
        echo -e "${YELLOW}[-]${NC} Complete Step 1 downgrade/pin (${target_k:-6.14.11-x-pve}) + reboot first, or use native 20.x."
        echo ""
    fi

    if ! merge_select_branch; then
        return 1
    fi
    if ! merge_select_mode; then
        return 1
    fi

    echo ""
    echo -e "${GREEN}[+]${NC} Selected: patcher branch $MERGE_BRANCH (${MERGE_LABEL[$MERGE_BRANCH]:-}), target $MERGE_MODE"
    if ! confirm_action "Proceed with merged build?"; then
        echo -e "${YELLOW}[-]${NC} Cancelled."
        return 0
    fi

    if ! merge_ensure_deps; then
        return 1
    fi
    ensure_patch_compat 2>/dev/null || true
    if ! merge_clone_patcher "$MERGE_BRANCH"; then
        return 1
    fi
    if ! merge_prepare_inputs "$MERGE_BRANCH" "$MERGE_MODE"; then
        return 1
    fi

    local produced=""
    if ! merge_run_patch "$MERGE_BRANCH" "$MERGE_MODE"; then
        return 1
    fi
    produced="$MERGE_PRODUCED"
    if [ -z "$produced" ]; then
        log_error "Merged build produced no output."
        return 1
    fi
    echo -e "${GREEN}[+]${NC} Merged output ready: $produced"

    if ! confirm_action "Install the merged driver now (--dkms -m=kernel -s)?"; then
        echo -e "${YELLOW}[-]${NC} Build kept at: $produced (rerun option 7 to install later)"
        return 0
    fi
    if ! merge_install_output "$produced" "$MERGE_BRANCH"; then
        return 1
    fi
    echo -e "${GREEN}[+]${NC} Merged driver installed successfully."
    merge_post_install
    return 0
}

remove_merged_patcher() {
    log_info "Removing merged patcher checkouts"
    rm -rf "$VGPU_DIR"/vgpu-unlock-patcher-* 2>/dev/null || true
    log_info "Merged patcher checkouts removed"
}

# Module loaded indicator
module_init "vgpu-merge.sh"
