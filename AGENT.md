# AGENT.md - Development Handoff & Context

This file provides comprehensive guidance for AI agents (Kiro, Claude, etc.) working on this repository.

## Quick Context

**Project**: Proxmox vGPU Installer v1.82  
**Status**: Stable release (main branch)  
**Key Features**: Auto-discovery host drivers, auto-generated guest drivers, kernel 7.x support, kernel 6.8+ compatibility fixes, Proxmox 9 + Pascal guards  
**Key Files**: `proxmox-installer.sh`, `lib/*.sh`, `driver_patches.json`, `gpu_info.db`

---

## Development History & Architecture

### Project Overview
This repository contains a comprehensive Bash script that automates the installation and configuration of NVIDIA vGPU drivers on Proxmox VE 7, 8, and 9 hypervisors. The project handles the complex process of setting up vGPU support including driver installation, patching, licensing, and system configuration with support for both native vGPU and vgpu_unlock capabilities.

### Main Components
- **proxmox-installer.sh** - Main installer (v1.82, supports driver 16.x-20.1)
- **lib/*.sh** - Modular components (repo, kernel, driver, GPU detection, etc.)
- **config.txt** - Runtime configuration (step, driver version, vGPU support)
- **gpu_info.db** - SQLite database with GPU compatibility info
- **driver_patches.json** - Patch-to-driver mapping

### Installation Process
1. **Step 1**: System preparation (repos, GPU detection, IOMMU, kernel modules)
2. **Reboot**: Apply kernel changes
3. **Step 2**: Driver installation, patching, SR-IOV, guest drivers, licensing

### Key Features
- **Smart Download**: File existence check + MD5 verification
- **Repository Format Support**: Auto-detect `*.list` (Proxmox 7/8) vs `*.sources` (Proxmox 9)
- **Kernel Compatibility**: Auto-detect kernel 7.x and suggest vGPU 20.0 or kernel downgrade
- **Secure Boot**: Custom module signing with MOK enrollment
- **Multi-GPU**: Intelligent GPU selection with passthrough for others
- **Guest Drivers**: Built-in catalog with Linux & Windows drivers

---

## v1.8 & v1.81 & v1.82 Features & Improvements

### v1.82 Hotfixes & Compatibility Updates (Latest)
- **Proxmox VE 9 + Pascal GPU Compatibility Guard (Issue #23)**: Proxmox VE 9 (running kernel 6.14/7.x) does not support kernel 6.5.x, which is required for driver versions older than 17.6 (like vGPU 16.x). If a user attempts to install vGPU 16.x on Proxmox VE 9, the script now cleanly aborts with a clear message instead of attempting an impossible kernel downgrade on Proxmox 9. It advises installing Proxmox VE 8 instead. Note: This check only applies to consumer/GeForce cards using vGPU Unlock (`VGPU_SUPPORT="Yes"`). Native enterprise Pascal cards (Tesla P4/P40/P100, `VGPU_SUPPORT="Native"`) are fully compatible with PVE 9 using native vGPU 16.x (e.g. 16.14) without unlock.
  * **Why Pascal vGPU Unlock requires Kernel <= 6.5.x**:
    1. **NVIDIA Driver Lock-in**: NVIDIA dropped Pascal architecture support starting with vGPU 17.0. Thus, Pascal consumer cards are restricted to vGPU 16.x (NVIDIA 535.x).
    2. **KVM `enable_apicv` Dependency**: The community `vgpu_unlock` patch relies on the KVM module exporting the `enable_apicv` symbol to bypass NVIDIA's GeForce virtualization block. Linux Kernel 6.8+ (shipped in PVE 8.2+ and 9.x) stopped exporting this symbol, causing patched modules to fail to load at runtime with `Unknown symbol enable_apicv` errors.
    3. **Compilation Failures**: The 535.x driver codebase is built for older kernels; attempting compilation on newer kernels (like 6.8+ or 6.14+) fails due to significant Linux kernel API changes.
    4. **Conclusion**: PVE 8 running a pinned kernel 6.5.x is the only viable configuration for Pascal vGPU Unlock. Pinning to 6.14+ is impossible.
- **Secure Boot UEFI Variable Detection & Prerequisite Automation**: Replaced the fragile `mokutil`-only check with a robust kernel UEFI variables check (`/sys/firmware/efi/efivars/SecureBoot-*`), permitting Secure Boot status query prior to `mokutil` package installation. If Secure Boot is active, the script automatically installs the necessary signing dependencies (`shim-signed`, `grub-efi-amd64-signed`, and `mokutil`) before generating keys and enrolling them.
- **DKMS Auto-Signing Framework Integration**: Configures the DKMS framework (via `/etc/dkms/framework.conf.d/nvidia-vgpu.conf` or `/etc/dkms/framework.conf`) to use the generated custom Secure Boot keys. This guarantees that when DKMS rebuilds the NVIDIA modules in the future (e.g. after a Proxmox kernel upgrade), it automatically signs the compiled `.ko` files, preventing signature verification loading failures.
- **IOMMU & VM Startup Cleanup Documentation (Issue #22, #17)**: Addressed issues with mediated device allocation/cleanup under vGPU Unlock by updating documentation. VM startup failures with `waited 10 seconds for mediated device driver finishing clean up` can be minimized by upgrading to the newer driver 16.14 (NVIDIA 535.246.02+) which resolves cleanup timing issues.

### v1.81 Hotfixes & Compatibility Updates
- **Local Variable Scope Error Fix (Issue #20)**: Removed invalid `local` variable declarations executed outside bash function contexts inside `proxmox-installer.sh`, correcting fatal syntax errors.
- **SQLite Python 3 Fallback (Issue #19)**: Added a robust `python3` sqlite module fallback inside `lib/gpu-detect.sh` to allow database querying and verification when the target node does not have the `sqlite3` CLI package installed, preventing silent classification failures.
- **Kernel 6.8+ Incompatibility Guard & PVE 8 Downgrade (Issue #21)**: Integrated checks to recognize that Kernel 6.8+ (Proxmox VE 8.2+) no longer exports the KVM `enable_apicv` symbol, rendering older unpatched driver modules (like 17.3 or 16.x) un-loadable. The script now alerts users and offers an automated kernel downgrade and pinning to `6.5.x` on Proxmox 8.
- **Strict Menu Filtering for Unsupported 16.x Versions**: Correctly filtered out `16.10`–`16.14` branches from the selection menu for consumer GPUs (vGPU-Unlock), keeping `16.9` as the highest supported version since higher 16.x branches lack community patches. Added a guard to prevent empty patch folder path resolution.

### 1. Auto-Discovery Host Drivers
**File**: `lib/host-drivers-auto.sh`  
**Feature**: Host drivers auto-discovered from alist.homelabproject.cc
- **v1.8 registry**: all menu branches `16.0`–`20.1` use `register_driver … "auto"` (no Mega.nz / hard-coded alist URLs)
- Crawls vGPU directory for available versions via API (`/api/fs/list?path=/foxipan/vGPU/{branch}`)
- Search order: root `*.run` → `Host_Drivers/` → `NVIDIA-GRID-Linux-KVM-*/Host_Drivers/` (dirs only, not `.zip` names) → root `*.zip` (`|zip` suffix for extractor)
- No MD5 checks needed - completely future-proof
- Smart caching: skips re-download if file already exists and is valid

**Manual override** (`proxmox-installer.sh` step-2 path): if `URL` or `FILE` is set (CLI or `config.txt`), auto-discovery and the driver menu are skipped.

| CLI | Config key | Behavior |
|-----|------------|----------|
| `--url <https://…>` | `URL=…` | `wget` download; supports `.run` or `.zip` (unzip + find `*.run`); `map_filename_to_version` must recognize the `.run` name |
| `--file <name.run>` | `FILE=…` | Use local file in installer cwd; no download |

`--url` uses **wget only** (not `megadl`). Mega.nz → user downloads manually, then `--file`.  
`--url` alist examples:

```text
# .run (nested Host_Drivers)
https://alist.homelabproject.cc/d/foxipan/vGPU/16.9/NVIDIA-GRID-Linux-KVM-535.230.02-539.19/Host_Drivers/NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run

# .zip (ZIP-only branch)
https://alist.homelabproject.cc/d/foxipan/vGPU/16.13/NVIDIA-GRID-Linux-KVM-535.288.01-539.64.zip
```

To reset to auto-discovery: remove `URL` / `FILE` from `config.txt`.

### 2. Alist Guest Driver Catalog & Local Fallback
**File**: `lib/guest-drivers.sh`  
**Feature**: Guest driver URLs shifted to Alist with local ZIP extraction fallback
- Migrated guest driver catalog download links to Alist direct links (`alist.homelabproject.cc`) for branches 16.x through 20.x. This avoids Google Cloud Storage's new requirement for `gcloud` CLI authorization/interactive logins, which broke headless automated downloads.
- Implemented automatic local ZIP discovery and extraction fallback (e.g. for vGPU 20.1), checking for host driver archives and copying guest drivers directly to bypass downloading.

### 3. Kernel 7.x Support
**File**: `proxmox-installer.sh`, `lib/kernel-manager.sh`  
**Feature**: Added vGPU 20.0 and 20.1 drivers for Proxmox VE 9.2+ with kernel 7.x
- Support for kernel 7.0.2-6-pve and later versions
- Removed unnecessary kernel compatibility checks

### 4. Extended 16.x Driver Support (16.10-16.14)
**File**: `proxmox-installer.sh`, `lib/host-drivers-auto.sh`  
**Feature**: Extended vGPU 16.x support from 16.0 to 16.14 with auto-discovery
- Added vGPU 16.10, 16.11, 16.12, 16.13, 16.14 support
- Driver versions: 535.247.01-535.309.01
- 16.14 marked as recommended for Pascal/older GPUs
- Auto-discovery from alist.homelabproject.cc

### 5. Repository Manager Fix
**File**: `lib/repo-manager.sh`  
**Fix**: Removed duplicate inline repository helper functions from `proxmox-installer.sh` that were overriding modular functionality.
- Updated repository configuration logic to support modifying PVE 8/9's default `proxmox.sources` file directly.
- Handles Ceph URIs dynamically based on Debian codename (bullseye/bookworm/trixie).
- Automatically removes standalone duplicate repository files (`pve-no-subscription.sources` / `.list` and `ceph-no-subscription.sources` / `.list`) to prevent `apt update` warning prompts.

### 6. SR-IOV Service
**File**: `proxmox-installer.sh`  
**Feature**: Automatic SR-IOV enablement for native vGPU cards
- Installs pve-nvidia-vgpu-helper package
- Enables pve-nvidia-sriov@ALL.service automatically
- Shows vGPU virtual functions after installation

### 7. Smart Download Management
**Files**: `lib/host-drivers-auto.sh`, `proxmox-installer.sh`  
**Feature**: All drivers now skip re-download if file already exists
- Host drivers: checks if .run file is executable
- ZIP files: validates with unzip -t before extraction
- Guest drivers: skips if file already present

### 8. Better Download Tools
**Feature**: Switched to wget for all downloads
- Better progress display with time and speed estimates
- More reliable than curl for large files

### 9. Secure Boot Signed Kernel (Issue #14)
**File**: `proxmox-installer.sh`  
**Feature**: Automatic signed kernel installation when Secure Boot is enabled
- Detects Secure Boot status via `mokutil`
- Installs `proxmox-kernel-*-signed` if available
- Falls back to unsigned kernel with warning if signed variant unavailable
- Prevents "bad shim signature" boot failures

### 10. Pre-Patched Driver Fallback & Compatibility Enhancements (v1.8)
**Files**: `proxmox-installer.sh`, `driver_patches.json`  
**Feature**: Robust support for vGPU-unlock pre-patched drivers and corrected mappings:
- **17.6 vGPU Patch Fix**: Corrected driver patch mapping for 17.6 in `driver_patches.json` to `550.163.02.patch` to match the actual host driver version and restore vGPU-unlock functionality.
- **Pre-Patched Driver Fallback**: Automatically detects and falls back to using pre-patched `*-custom.run` installers downloaded from auto-discovery mirrors, avoiding `chmod` and pathing failures.
- **Interactive Downgrade Prompts**: Instead of silently forcing a kernel downgrade on Proxmox 9.2 with kernel 7.x, the script now prompts the user with an interactive `(y/n)` choice and gracefully aborts with warnings if declined.
- **UI Label Clarifications**: Cleansed the redundant `"Select this for most situations."` text from selection menus and resolved contradictory `"Native GPUs only"` notes for patchable vGPU unlock drivers. Classified 17.6 correctly as `"Turing GPUs"`.
- **Nvidia Driver Status False-Alarm Fix**: Fixed a false-alarm red message during Step 2. Since consumer cards in vGPU-unlock mode do not natively support vGPU commands directly in the shell without preloading, they always say "No supported devices in vGPU mode". The installer now falls back to standard `nvidia-smi` to verify driver health for consumer cards, displaying a green success message instead. Also corrected visual indicators for actual failures from a red `[+]` to `[!]`.
- **Modern VM Setup Instructions**: Replaced the legacy PCI passthrough guide with modern PVE 8/9 instructions utilising Datacenter Resource Mappings to define and map mediated devices, with instructions updated to guide checking the 'Advanced' and 'PCI-Express' toggles.
- **Proprietary Kernel Module Enforcement**: Fixed a critical driver compilation bug where driver version 17.6+ (550.x and newer) defaulted to building open-source (`nvidia-open`) kernel modules. Open-source modules do not support virtual GPUs (vGPU) on any card flavor and cause VM startup crash with `HOST_VGPU_DEVICE` construct failure. The installer now distinguishes between setup configurations and conditionally passes the `-m=kernel` flag to strictly force compiling closed-source proprietary modules for consumer cards (`VGPU_SUPPORT="Yes"`), while native enterprise vGPU cards (`VGPU_SUPPORT="Native"`) skip this flag since the enterprise `vgpu-kvm.run` driver installer does not support or require the `-m` option.
- **Step 2 Auto GPU Detection Fallback**: Added an automatic GPU detection fallback at the start of Step 2. If the user runs Step 2 directly or from a clean state where `config.txt` has been removed, the script will dynamically detect the system's GPU and restore the appropriate vGPU compatibility flags, preventing the "Unknown or unsupported GPU" crash.
- **Secure Boot Kernel Downgrade Support**: Extended Secure Boot compatibility to the kernel downgrade module. When downgrading the host to kernel `6.14.11-x-pve` (dynamically discovered latest version, e.g. `6.14.11-9-pve`) on systems with Secure Boot enabled, the installer now automatically checks Secure Boot status and downloads the signed variant (`proxmox-kernel-6.14.11-x-pve-signed`), eliminating UEFI boot failures caused by "bad shim signature".
- **MOK Certificate DER Format Fix**: Fixed an enrollment abort error where `mokutil --import` rejected the generated PEM-encoded MOK certificate as "not a valid x509 certificate in DER format". The script now automatically generates/converts the certificate into both PEM (`module-signing.crt` for the NVIDIA driver installer) and DER (`module-signing.der` for `mokutil`) formats, enabling seamless MOK enrollment.
- **Duplicate Secure Boot Function Removal**: Removed duplicate inline definitions of all six Secure Boot helper functions (`secure_boot_enabled`, `secure_boot_key_enrolled`, `generate_secure_boot_keys`, `prepare_secure_boot_enrollment`, `secure_boot_precheck`, `build_secure_boot_flags`) that were redeclared in `proxmox-installer.sh` after sourcing `lib/secure-boot.sh`. These late declarations overrode the corrected library functions, silently bypassing the DER format fix.
- **MOK Enrollment Self-Healing Re-queue**: Fixed an infinite loop where `SECURE_BOOT_PENDING=1` persisted in `config.txt` after the user dismissed the MOK Management screen (chose "Continue" instead of "Enroll MOK"). The installer now detects whether a pending import actually exists in firmware via `mokutil --list-new` and automatically re-queues enrollment when the request has been cleared, instead of looping on "please reboot".
- **MOK Password Policy Reminder**: Added an informational notice immediately before the `mokutil` password prompt reminding the user that the password must be at least 8 characters, ASCII only, and should avoid UEFI-problematic special characters (`@`, `#`, `$`) that may not type correctly on firmware keyboards.
- **Secure Boot Signing Flags Not Passed to NVIDIA Installer (Critical)**: Fixed a critical bug where `SECURE_BOOT_READY` was correctly written to `config.txt` by `set_config_value` after a successful MOK enrollment check, but the in-memory bash variable was never updated. As a result, `build_secure_boot_flags()` always saw `SECURE_BOOT_READY=0` and emitted no signing flags, causing the NVIDIA installer to compile unsigned kernel modules that Secure Boot refused to load with `ERROR: The kernel module failed to load`. The fix adds `SECURE_BOOT_READY="1"` and `SECURE_BOOT_PENDING="0"` inline assignments immediately after the `set_config_value` calls.
- **Unsupported Driver Filtering for vGPU-Unlock (Yes) Cards**: Filters out driver versions (like 16.10-16.14) that do not have `vgpu_unlock` patches available in `driver_patches.json` during the menu selection step and during driver version mapping, preventing runtime compilation failures like 'patch is missing' or 'Patch metadata missing'.

---

## Known Limitations & Future Considerations

### Issue #10: vGPU-Unlock-Patcher Integration
**Status**: Evaluated, not integrated

**Analysis:**
- vGPU-Unlock-Patcher only supports patches up to 580.126 (vGPU 19.1)
- We already support up to 595.71.03 (vGPU 20.1)
- No patches available for 19.2+, 20.x versions
- Community project not actively maintained for new releases

**Decision:**
- Cannot directly integrate due to version gap
- Our `lib/vgpu-unlock.sh` module already supports vgpu_unlock
- Maintaining patches independently provides better control and future-proofing
- Would need to create patches for 19.2+, 20.x if vgpu_unlock support needed for those versions
- No behavior change when Secure Boot is disabled

---

## Current Driver Support

| Version | Host Driver | Linux Guest | Windows Guest | Notes |
|---------|-------------|-------------|---------------|-------|
| 20.1 | 595.71.03 | 595.71.05 | 596.36 | Kernel 7.x, ZIP format |
| 20.0 | 595.58.02 | 595.58.03 | 595.97 | Kernel 7.x ✓ |
| 19.5 | 580.159.01 | 580.159.03 | 582.53 | ✓ |
| 19.4 | 580.126.08 | 580.126.09 | 582.16 | ✓ |
| 19.3 | 580.105.06 | 580.105.08 | 581.80 | ✓ |
| 19.2 | 580.95.02 | 580.95.05 | 581.42 | ✓ |
| 19.1 | 580.82.02 | 580.82.07 | 581.15 | ✓ |
| 19.0 | 580.65.05 | 580.65.06 | 580.88 | ✓ |
| 18.4 | 570.172.07 | 570.172.08 | 573.48 | ✓ |
| 18.3 | 570.158.02 | 570.158.01 | 573.39 | ✓ |
| 18.2 | 570.148.06 | 570.148.08 | 573.07 | ✓ |
| 18.1 | 570.133.10 | 570.133.20 | 572.83 | ✓ |
| 18.0 | 570.124.03 | 570.124.06 | 572.60 | ✓ |
| 17.6 | 550.163.02 | 550.163.01 | 553.74 | ✓ |
| 17.5 | 550.144.02 | 550.144.03 | 553.62 | ✓ |
| 17.4 | 550.127.06 | 550.127.05 | 553.24 | ✓ |
| 17.3 | 550.90.05 | 550.90.07 | 552.74 | ✓ |
| 17.1 | 550.54.16 | 550.54.15 | 551.78 | ✓ |
| 17.0 | 550.54.10 | 550.54.14 | 551.61 | ✓ |
| 16.14 | 535.309.01 | 535.309.01 | 539.72 | ✓ |
| 16.13 | 535.288.01 | 535.288.01 | 539.64 | ✓ |
| 16.12 | 535.274.03 | 535.274.03 | 539.56 | ✓ |
| 16.11 | 535.261.03 | 535.261.03 | 539.41 | ✓ |
| 16.10 | 535.247.01 | 535.247.01 | 539.28 | ✓ |
| 16.9 | 535.230.02 | 535.230.02 | 539.19 | ✓ |
| 16.8 | 535.216.01 | 535.216.01 | 538.95 | ✓ |
| 16.7 | 535.183.04 | 535.183.06 | 538.78 | ✓ |
| 16.5 | 535.161.05 | 535.161.08 | 538.46 | ✓ |
| 16.2 | 535.129.03 | 535.129.03 | 537.70 | ✓ |
| 16.1 | 535.104.06 | 535.104.06 | 537.24 | ✓ |
| 16.0 | 535.54.06 | 535.54.06 | 536.40 | ✓ |

---

## Key Implementation Details

### Repository Format Support
- **Proxmox 7/8** (Debian 11/12): Uses `*.list` format
- **Proxmox 9** (Debian 13/trixie): Uses `*.sources` format
- **Auto-detection**: Script detects OS codename and chooses format
- **Enterprise handling**: Properly disables enterprise repos in both formats

### Smart Download Features
- **File existence check**: Skips download if file exists
- **MD5 verification**: Validates existing files
- **Backup mechanism**: Backs up old files before re-downloading
- **User feedback**: Clear notifications about download decisions

### Kernel Compatibility
- **Kernel 7.x**: Requires vGPU 20.0+ (595.58.02+)
- **Kernel 6.14-6.16**: Works with vGPU 19.x
- **Kernel 6.17+**: Requires downgrade to 6.14 for vGPU 19.x

## Guest Driver Alist Resolution & Fallback

Guest drivers are resolved via direct download URLs hosted on `alist.homelabproject.cc`.

**URL Structure**:
```text
https://alist.homelabproject.cc/d/foxipan/vGPU/{BRANCH}/{KVM_FOLDER}/Guest_Drivers/{FILENAME}
```

**Example (vGPU 19.5)**:
- Linux: `https://alist.homelabproject.cc/d/foxipan/vGPU/19.5/NVIDIA-GRID-Linux-KVM-580.159.01-580.159.03-582.53/Guest_Drivers/NVIDIA-Linux-x86_64-580.159.03-grid.run`
- Windows: `https://alist.homelabproject.cc/d/foxipan/vGPU/19.5/NVIDIA-GRID-Linux-KVM-580.159.01-580.159.03-582.53/Guest_Drivers/582.53_grid_win10_win11_server2022_server_2025_dch_64bit_international.exe`

**Local ZIP Fallback (e.g., vGPU 20.1)**:
For branches that do not have direct folders under the vGPU directory on Alist, the URLs are left blank in the static catalog. In this case, the installer automatically:
1. Searches for any downloaded KVM host driver ZIP matching `NVIDIA-GRID-Linux-KVM-*.zip` or `NVIDIA-GRID-vGPU-*.zip` in the installation directory.
2. Extracts it locally.
3. Locates the nested `Guest_Drivers` or `guest_drivers` folder.
4. Copies the guest Linux `.run` and Windows `.exe` driver installers to the destination directory.

**To Update Guest Drivers**:
1. Check Alist `https://alist.homelabproject.cc/foxipan/vGPU/` for new versions.
2. Identify the guest driver filename under `Guest_Drivers/`.
3. Update the static catalog inside `load_auto_guest_driver_catalog` in `proxmox-installer.sh` with the direct Alist URLs.
4. If a branch only has a `.zip` archive on Alist and no nested folders, leave the catalog entries empty so that the local extraction fallback is automatically triggered.

---

When testing new features:

1. **Repository Configuration**
   - [ ] Check `/etc/apt/sources.list.d/` for duplicates
   - [ ] Verify `apt update` has no warnings
   - [ ] Test on both Proxmox 8 and 9

2. **Driver Installation**
   - [ ] Test with vGPU 20.0 on kernel 7.x
   - [ ] Test with vGPU 19.x on kernel 6.14
   - [ ] Verify MD5 checksums match
   - [ ] Check `nvidia-smi vgpu` output

3. **Guest Drivers**
   - [ ] Verify Linux guest driver URLs work
   - [ ] Verify Windows guest driver URLs work
   - [ ] Check file names match exactly

4. **Kernel Management**
   - [ ] Test kernel downgrade prompt on kernel 7.x
   - [ ] Verify kernel pinning works
   - [ ] Check reboot process

---

## Common Commands

```bash
# Run installer (host driver: alist auto-discovery)
sudo bash proxmox-installer.sh

# Debug mode
sudo bash proxmox-installer.sh --debug

# Manual host driver URL (skips menu + auto-discovery; saved to config.txt)
sudo bash proxmox-installer.sh --url "https://alist.homelabproject.cc/d/foxipan/vGPU/17.5/NVIDIA-GRID-Linux-KVM-550.144.02-550.144.03-553.62/Host_Drivers/NVIDIA-Linux-x86_64-550.144.02-vgpu-kvm.run"

# Local .run already downloaded (offline / Mega via megadl)
sudo bash proxmox-installer.sh --file NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run

# Resume step 2 after reboot
sudo bash proxmox-installer.sh --step 2

# Check logs
tail -f debug.log

# Verify GPU support
nvidia-smi vgpu
mdevctl types

# Check repositories
apt update 2>&1 | grep -i "configured multiple times"

# Check kernel
uname -r
```

---

## File Structure

```
proxmox-vgpu-installer/
├── proxmox-installer.sh          # Main installer script
├── lib/
│   ├── common.sh                 # Common functions & logging
│   ├── config.sh                 # Configuration management
│   ├── driver-manager.sh         # Driver handling & downloads
│   ├── kernel-manager.sh         # Kernel management & downgrade
│   ├── secure-boot.sh            # Secure Boot integration
│   ├── gpu-detect.sh             # GPU detection & compatibility
│   ├── repo-manager.sh           # Repository management (*.list & *.sources)
│   ├── guest-drivers.sh          # Guest driver catalog
│   ├── vgpu-unlock.sh            # vGPU unlock support
│   └── fastapi-dls.sh            # Licensing server
├── driver_patches.json           # Patch-to-driver mapping
├── gpu_info.db                   # GPU compatibility database
├── README.md                     # Main documentation
├── CHANGELOG.md                  # Version history
├── AGENT.md                      # This file
├── old/                          # Historical versions
└── pic/                          # Documentation images
```

### Module Overview

**Week 1 (Foundation)**:
- `common.sh` - Color definitions, logging, system detection
- `config.sh` - Configuration file management

**Week 2 (Core)**:
- `driver-manager.sh` - Smart download with MD5 verification
- `kernel-manager.sh` - Kernel detection & downgrade for vGPU compatibility
- `secure-boot.sh` - Secure Boot key generation & MOK enrollment
- `gpu-detect.sh` - GPU detection via lspci & SQLite queries

**Week 3 (Advanced)**:
- `repo-manager.sh` - APT repository configuration (*.list & *.sources)
- `guest-drivers.sh` - Guest driver catalog & downloads
- `vgpu-unlock.sh` - vGPU unlock setup for consumer GPUs
- `fastapi-dls.sh` - FastAPI-DLS licensing server deployment

### Module Dependencies
```
common.sh (foundation)
    ├── config.sh
    ├── driver-manager.sh
    ├── kernel-manager.sh
    ├── secure-boot.sh
    ├── gpu-detect.sh
    ├── repo-manager.sh
    ├── guest-drivers.sh
    ├── vgpu-unlock.sh
    └── fastapi-dls.sh
```

---

## Next Steps for Development

1. **Add vGPU 20.1 support**
   - Handle ZIP format extraction
   - Add MD5 checksum verification

2. **Improve error handling**
   - Better network error messages
   - Retry logic for downloads

3. **Enhanced logging**
   - Structured log output
   - Better debug information

4. **Testing automation**
   - Unit tests for functions
   - Integration tests for workflows

---

## References

- [Official Proxmox vGPU Documentation](https://pve.proxmox.com/wiki/NVIDIA_vGPU_on_Proxmox_VE)
- [NVIDIA vGPU Documentation](https://docs.nvidia.com/vgpu/)
- [vgpu-proxmox Repository](https://github.com/vgpu-proxmox/vgpu-proxmox)
- [vgpu_unlock-rs Repository](https://github.com/vgpu-proxmox/vgpu_unlock-rs)
- [FastAPI-DLS](https://git.collinwebdesigns.de/vgpu/nvlts)

---

## Contact & Attribution

**Original Author**: wvthoog.nl  
**Major Contributors**: RocketRammer, LeonardSEO, Anomixer  
**Current Maintainer**: Community

For issues and questions, refer to the GitHub repository and official documentation.
