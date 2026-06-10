# Proxmox vGPU Installer v1.82

A comprehensive Bash script that automates the installation and configuration of NVIDIA vGPU drivers on Proxmox VE 7, 8, and 9 hypervisors. This tool supports multiple GPU types, driver versions, and provides both native vGPU and vgpu_unlock capabilities.

For detailed installation instructions, see the original author's blogpost at https://wvthoog.nl/proxmox-7-vgpu-v3/

For complete documentation on script architecture, features, and usage, visit https://deepwiki.com/anomixer/proxmox-vgpu-installer
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/anomixer/proxmox-vgpu-installer)

> [!IMPORTANT]
> **Pascal consumer GPUs (GTX 10-series) using `vgpu_unlock` are not supported on Proxmox VE 9+.**
> These cards depend on vGPU 16.x / NVIDIA 535.x and an unlock patch path that requires kernel 6.5.x or older.
> If you are using a GTX 1080 / 1070 / 1060 for vGPU unlock, install Proxmox VE 8 and pin the host kernel to 6.5.x.
> This warning does **not** apply to enterprise Pascal cards such as Tesla P4/P40/P100, which use native vGPU.

## Compatibility Matrix

| GPU Generation | Setup Type | Example Models | Max vGPU Driver | Compatible Host Kernel | Compatible PVE Version | Practical Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Maxwell** (GM20x) | **vGPU Unlock** (GeForce) | GTX 980, GTX 970 | vGPU 16.x (535.x) | **Kernel <= 6.5.x** | **PVE 8.x** (with 6.5 downgrade), PVE 7.x | Stay on PVE 7 or PVE 8 with kernel 6.5.x only. |
| **Maxwell** (GM20x) | **Native vGPU** (Enterprise) | Tesla M4, M10, M60 | vGPU 16.x (e.g. 16.14) | Kernel 6.2, 6.5, 6.8, 6.14+, 7.x | PVE 8.x, **PVE 9.x** | Can run on newer kernels and newer PVE branches natively. |
| **Pascal** (GP10x) | **vGPU Unlock** (GeForce) | GTX 1080, GTX 1070, GTX 1060 | vGPU 16.x (535.x) | **Kernel <= 6.5.x** | **PVE 8.x** (with 6.5 downgrade), PVE 7.x | Use PVE 8 with pinned 6.5.x; do not target PVE 9+. |
| **Pascal** (GP10x) | **Native vGPU** (Enterprise) | Tesla P4, Tesla P40, Tesla P100 | vGPU 16.x (e.g. 16.14) | Kernel 6.2, 6.5, 6.8, 6.14+, 7.x | PVE 8.x, **PVE 9.x** | Compatible with PVE 8 and PVE 9 using native vGPU. |
| **Turing** (TU10x/TU11x) | **vGPU Unlock** (GeForce) | RTX 2080, GTX 1660, etc. | vGPU 16.x (535.x), vGPU 17.6 (550.x) | Kernel 6.2, 6.5, 6.8, 6.14+, 7.x | PVE 8.x, **PVE 9.x** | Supported on PVE 9+ when using newer vGPU branches (17.6+). |
| **Turing** (TU10x) | **Native vGPU** (Enterprise) | Tesla T4, Quadro RTX 6000 | vGPU 16.x to 20.x | Kernel 6.2, 6.5, 6.8, 6.14+, 7.x | PVE 8.x, **PVE 9.x** | Compatible on PVE 8 and PVE 9. |
| **Ampere & Newer** (GA/AD/GB) | **vGPU Unlock** (GeForce) | RTX 3080, RTX 4090, RTX 5090 | **NOT SUPPORTED** | N/A | N/A | Not supported for unlock by this project. |
| **Ampere & Newer** (GA/AD/GB) | **Native vGPU** (Enterprise) | A10, A16, L4, RTX A6000 | vGPU 16.x to 20.x | Kernel 6.2, 6.5, 6.8, 6.14+, 7.x | PVE 8.x, **PVE 9.x** | Native vGPU path on current PVE branches. |

### Clear Rule of Thumb

Use the following decision rule before running the installer:
- **If your GPU is enterprise/native vGPU capable**: Newer PVE versions (PVE 9+) are generally fine within the driver/kernel support.
- **If your GPU is a consumer Maxwell or Pascal card (needs `vgpu_unlock`)**: Assume you must remain on PVE 8 and pin your host kernel to `6.5.x` (automated by Step 1 of this script). PVE 8 goes EOL on August 31, 2026.
- **If your GPU is consumer Turing (needs `vgpu_unlock`)**: You can use newer PVE versions (PVE 9+) because newer supported driver branches (vGPU 17.6+) avoid the `enable_apicv` dependency.
- **If your GPU is consumer Ampere or newer GeForce**: This project explicitly marks unlock as unsupported.

## Features

- **Multi-Version Support**: Comprehensive driver support from v16.x through v20.1 series
- **Smart Driver Downloads**: Intelligent download management with file existence checking and smart caching
- **Kernel Compatibility**: Support for kernel 7.x with vGPU 20.0/20.1, kernel 6.x with vGPU 16.x-19.x
- **Dual vGPU Modes**: Support for both native vGPU (Tesla/Quadro) and vgpu_unlock (consumer cards)
- **Auto Guest Drivers**: Guest driver catalog using direct download links from Alist, with automated local ZIP fallback extraction for branches (like 20.1) without direct folder endpoints.
- **Automated Licensing**: FastAPI-DLS licensing server deployment with Docker
- **Multi-GPU Handling**: Automatic detection and configuration for systems with multiple GPUs
- **Secure Boot Support**: Complete Secure Boot integration with module signing
- **Proxmox Integration**: Seamless integration with Proxmox VE's PCI passthrough system
- **Repository Format Support**: Automatic support for both legacy `*.list` and modern `*.sources` repository formats (Proxmox 9/trixie)

## Installation Requirements

- Proxmox VE 7.x, 8.x, or 9.x
- NVIDIA GPU with vGPU support (native or via vgpu_unlock)
- Internet connection for driver downloads
- Root access
- Minimum 8GB RAM recommended

## Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/anomixer/proxmox-vgpu-installer.git
   cd proxmox-vgpu-installer
   ```

2. **Run the installer:**
   ```bash
   sudo bash proxmox-installer.sh
   ```

3. **Follow the interactive menu:**
   - Select option 1 for new vGPU installation
   - Choose your NVIDIA driver version
   - Complete step 1 (system preparation)
   - Reboot when prompted
   - Run the script again to complete step 2 (driver installation)

4. **Verify installation:**
   ```bash
   nvidia-smi vgpu
   mdevctl types
   ```

## Version History

Changes in version 1.82 (latest release)
- **Proxmox VE 9 + Pascal GPU Compatibility Guard (Issue #23)**: Proxmox VE 9 (running kernel 6.14/7.x) does not support kernel 6.5.x, which is required for driver versions older than 17.6 (like vGPU 16.x). If a user attempts to install vGPU 16.x on Proxmox VE 9, the script now cleanly aborts with a clear warning instead of attempting an impossible kernel downgrade on Proxmox 9. It advises installing Proxmox VE 8 instead.
- **Turing GPU Kernel Downgrade Check Fix**: Refined kernel checking in Step 1 to bypass false kernel downgrade prompts for Turing and newer GeForce GPUs on newer PVE kernels (up to 6.16), correctly enabling them to run vGPU 17.6+ unlock builds on modern systems.
- **Docker-CE Installation & Conflict Fix**: Resolved package conflicts on Debian 13/Proxmox VE 9 where the official `docker-compose-plugin` clashed with pre-installed legacy `docker-compose` files. Implemented a robust `dpkg -s` check to purge conflicting packages individually.
- **Enhanced Installer Diagnostics**: Split monolithic Docker installations into 7 discrete `run_command` steps for precise error tracing. Improved `run_command` logging to capture all verbose `stdout` configuration output into `debug.log`, and added defensive database configurations (`dpkg --configure -a`) at the start to immediately surface DKMS build crashes.
- **Script Cleanliness**: Replaced unstable `apt` CLI commands with stable `apt-get` equivalents throughout all scripts to eliminate verbose shell warnings, and fixed invalid bare `local` variable declarations.
- **IOMMU & VM Startup Cleanup Updates (Issue #22, #17)**: Addressed issues with mediated device allocation/cleanup under vGPU Unlock. VM startup failures with `waited 10 seconds for mediated device driver finishing clean up` can be minimized by upgrading to the newer driver 16.14 (NVIDIA 535.246.02+) which resolves cleanup timing issues.

Changes in version 1.81 (previous release)
- **Local Variable Error Fix (Issue #20)**: Removed invalid `local` variable declarations outside function contexts inside `proxmox-installer.sh`, preventing fatal syntax errors during run.
- **SQLite python3 Fallback (Issue #19)**: Implemented an elegant `python3` sqlite module fallback inside `lib/gpu-detect.sh` to allow querying and verifying the database when the `sqlite3` CLI tool is not present, resolving unrecognized GPU status bugs. Proactively added `sqlite3` to Step 1 base packages.
- **Kernel 6.8+ Incompatibility Guard & PVE 8 Downgrade (Issue #21)**: Integrated detection for kernel versions 6.8 and higher which removed KVM's `enable_apicv` symbol export. If consumer GPU users select drivers older than 17.6 (like 17.3 or 16.x), the installer will alert them and offer an automated kernel downgrade and pinning to `6.5.x` on Proxmox 8.
- **Empty Patch Directory Verification Fix**: Guarded `ensure_vgpu_proxmox_patch` to cleanly reject empty patch names, and verified that unsupported 16.x versions (`16.10`-`16.14` which lack community patches in `vgpu-proxmox`) are correctly filtered out from consumer GPU menus.

Changes in version 1.8
- **Auto-Discovery Host Drivers**: Host drivers auto-discovered from alist.homelabproject.cc
  - Crawls vGPU directory for available versions via API
  - Finds Host_Drivers/NVIDIA-Linux-x86_64-*-vgpu-kvm.run files
  - Fallback: downloads and extracts ZIP format (e.g., 20.1)
  - No MD5 checks needed - completely future-proof
  - Smart caching: skips re-download if file already exists and is valid
- **Alist Guest Driver Catalog & Local Fallback**: Google Cloud has shifted its public guest driver downloads to require `gcloud` CLI authorization, requiring interactive user authentication and breaking automated installer downloads. To restore a convenient setup experience, we migrated the guest driver catalog to direct download links hosted on `alist.homelabproject.cc` for branches `16.x` through `20.x`, and implemented a local auto-discovery fallback that extracts host KVM driver ZIPs and copies guest drivers directly.
- **Kernel 7.x Support**: Added vGPU 20.0 and 20.1 drivers for Proxmox VE 9.2+ with kernel 7.x
  - Support for kernel 7.0.2-6-pve and later versions
- **Expanded Driver Support**: Added vGPU 19.4, 19.5, 20.0, 20.1 drivers and extended 16.x support to 16.14
  - 20.1: 595.71.03 (ZIP format)
  - 20.0: 595.58.02 (Kernel 7.x support)
  - 19.5: 580.159.01 (recommended for native vGPU)
  - 19.4: 580.126.08
  - 16.10-16.14: 535.247.01-535.309.01 (16.14 recommended for Pascal/older GPUs)
  - 16.x support now extends from 16.0 to 16.14 with auto-discovery
- **Repository Manager Fix**: Removed duplicate inline repository helper functions in `proxmox-installer.sh` that were overriding the modular implementation. Refactored repository setup to support PVE 8/9's default `proxmox.sources` file, dynamically fetch Ceph URIs by host codename, and automatically clean up duplicate standalone source files (`pve-no-subscription.sources` / `.list` and `ceph-no-subscription.sources` / `.list`) to prevent `apt update` warnings.
- **SR-IOV Service**: Automatic SR-IOV enablement for native vGPU cards
  - Installs pve-nvidia-vgpu-helper package
  - Enables pve-nvidia-sriov@ALL.service automatically
  - Shows vGPU virtual functions after installation
- **Smart Download Management**: All drivers now skip re-download if file already exists
  - Host drivers: checks if .run file is executable
  - ZIP files: validates with unzip -t before extraction
  - Guest drivers: skips if file already present
- **Better Download Tools**: Switched to wget for all downloads
  - Better progress display with time and speed estimates
  - More reliable than curl for large files
- **Secure Boot Support (Issue #14)**: Automatic signed kernel installation when Secure Boot is enabled
  - Detects Secure Boot status via `mokutil`
  - Installs `proxmox-kernel-*-signed` if available
  - Falls back to unsigned kernel with warning if signed variant unavailable
  - Prevents "bad shim signature" boot failures
- **Proxmox VE 9.2 Support**: Full compatibility with latest Proxmox VE 9.2.2
- **All host drivers use alist auto-discovery** (`"auto"` in registry): versions 16.0–20.1 no longer rely on Mega.nz or hard-coded URLs
- **Manual override**: `--url` and `--file` for mirrors, offline installs, or when auto-discovery fails (see [Advanced Usage](#advanced-usage))
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
- **MOK Enrollment Self-Healing Re-queue**: If the user dismissed the MOK screen without enrolling (chose "Continue" instead of "Enroll MOK"), the installer now detects this via `mokutil --list-new` and automatically re-queues the enrollment, eliminating the infinite "please reboot" loop.
- **MOK Password Policy Reminder**: A clear reminder of the MOK password requirements (minimum 8 characters, ASCII only, avoid special characters like `@`, `#`, `$` that may not type correctly in UEFI) is now shown before the password prompt.
- **Secure Boot Module Signing Fix (Critical)**: Fixed a critical bug where NVIDIA kernel modules were compiled without Secure Boot signing flags even after successful MOK enrollment, causing `ERROR: The kernel module failed to load`. The in-memory `SECURE_BOOT_READY` variable was not updated after the enrollment check, so signing flags were never passed to the NVIDIA installer.

Changes in version 1.75 (previous release)
- **Kernel Compatibility Management**: Automatic kernel downgrade for vGPU unlock compatibility
  - Detects when running Proxmox VE 9.1.1+ with kernel 6.17 or higher
  - Automatically downgrades and pins to the latest available kernel `6.14.11-x-pve` (e.g. `6.14.11-9-pve`) for vGPU patch compatibility
  - Only applies to vgpu_unlock scenarios (VGPU_SUPPORT="Yes")
- **Driver Updates**: Added vGPU 19.3 driver support (580.105.06)
- **Bug Fixes**: Corrected v16.8 driver MD5 checksum and various driver mapping corrections
- **Enhanced User Experience**: Improved messaging and notifications for kernel management

Changes in version 1.73
- Minor fix on pve-nvidia-vgpu-helper setup run_command

Changes in version 1.72
- This version focuses on stability improvements.
- Replaced the Host Driver note with supported GPUs for easier configuration.
- Switched to the new *.sources repository format introduced in Debian 13 / Proxmox VE 9 (Trixie) to prevent duplicate sources that may cause apt update errors.
- Ensured that nvidia-vgpu-helper automatically installs pve-headers and enables SR-IOV capabilities for native vGPU cards.
- Added file existence checks and MD5 verification to prevent unnecessary re-downloads of host drivers.
- ** Note **: Patch files have not been released since driver version 19.1 (580.82.02). vgpu_unlock support is limited to vGPU 16.x-19.1. For vGPU 19.2+, 20.x, only native vGPU (Tesla/Quadro) is supported. Please wait for updated patches if you plan to use vgpu_unlock with newer driver versions.

Changes in version 1.71
- This version is a minor update with newer driver download URL.
- Readme file rewritten with more details.
- Added host and guest drivers v19.2 and v16.3.

Changes in version 1.7 (contributed by [RocketRammer](https://github.com/RocketRammer/proxmox-vgpu-installer))
- Added a built-in guest driver catalog with curated Linux and Windows packages for every supported vGPU branch and prompts to fetch them automatically after host driver installs or from menu option 5.
- Hardened guest driver downloads with sanitized filenames, curl/wget fallbacks, and clearer success/error reporting.
- Improved patched driver discovery by tracking installer artifacts before and after patching to reliably capture renamed outputs.
- Externalized patch-to-driver mapping in `driver_patches.json` to simplify maintenance when NVIDIA releases new builds.
- Expanded the end-of-installation summary with next steps and quick commands so new deployments are easier to verify.
- Added 'Updated by' section to script for attribution of people updating the project
- Updated the generated FastAPI-DLS Docker Compose to favor the asyncio event loop, include init/healthcheck/grace period tuning, and document how to re-enable uvloop or TLS if required.

Changes in version 1.61
- This version is a minor update and fill with newer driver download URL.
- Support driver version 19.2

Changes in version 1.6 (contributed by [LeonardSEO](https://github.com/LeonardSEO/proxmox-vgpu-installer))
- This version is improved with new script structure including driver matrix, patch mechanism, and new workflow, etc.
- Replace the static driver matrix with a data-driven catalog that covers v16.0 through v19.1, including mirrors, checksums, and branch-specific install flags (--dkms -m=kernel -s for legacy ≤17.x, --dkms -s for v18.x+).
- Detect and offer to run pve-nvidia-vgpu-helper, backport GNU patch 2.7.6 automatically when Debian 13's patch 2.8 triggers the "NUL byte" error, and make Secure Boot enrollment part of the workflow.
- Emit branch-aware FastAPI-DLS warnings so users know vGPU ≥18.x needs gridd/nvlts unlock patches, and avoid surprise failures.
- Externalize patch metadata via driver_patches.json, preventing hard-coded patch names and making future releases data-driven.
- Refresh gpu_info.db (optional) with the latest RTX/Ada/Blackwell PCI IDs while preserving the legacy schema.
- Update the README to reflect the new workflow and highlight the helper, secure boot, and branch guidance changes.

Changes in version 1.51
- This version is a minor fix for driver source (megadl/wget) issue.
  - Split logic for legacy vs new drivers to fix download/patch issues introduced in v1.50.
  - v16.x–v17.x: use legacy mega.nz links with megadl and legacy install args `--dkms -m=kernel -s`.
  - v18.3+ : use alist.homelabproject.cc links with wget; v18.0 and v18.1 remain on mega.nz with megadl.
  - v18.x (all): use install args `--dkms -s` (patch/install flags are the same across v18.x and newer).
  - Auto-detects the correct download tool based on URL (mega.nz -> megadl; otherwise wget/curl) and installs megatools on demand.

Changes in version 1.5
- This is a major enhanced release for all users that integrated original author's functions and other forker's driver sources!
- **Expanded Driver Support**: Added support for driver versions from v1.1 and [PTHyperdrive fork](https://github.com/PTHyperdrive/proxmox-vgpu-installer):
  - v16.x series: 16.0, 16.1, 16.2, 16.5, 16.7, 16.8, 16.9 (Pascal/Older GPUs)
  - v17.x series: 17.0, 17.1, 17.3, 17.4, 17.5, 17.6 (Pascal/Newer GPUs, v17.6 Native vGPU only)
  - v18.x series: 18.0, 18.1, and 18.3, 18.4 (Newer GPUs, v18.1+ Native vGPU only)
  - v19.x series: 19.0, 19.1 (19.x Native vGPU only)
- **Proxmox 7 Support**: Re-added support for Proxmox 7 with legacy driver compatibility (v16.x, v17.0).
- **Legacy Mode**: Automatic detection and bypass of `pve-nvidia-vgpu-helper` for pre-v18.x drivers on Proxmox 7.
- **Enhanced Driver Menu**: Refined driver selection display with clear compatibility annotations indicating GPU requirements and vGPU support levels.
- **Mixed Source Downloads**: Integrated driver URLs from both alist.homelabproject.cc (current) and mega.nz (legacy/fork versions).
- **Kernel Pin Independence**: Confirmed kernel pinning is optional to support broader vGPU version compatibility.
- **FastAPI-DLS Compatibility**: Added compatibility warnings for vGPU licensing - works natively with v17.x and older, requires gridd-unlock-patcher for v18.0+.

Changes in version 1.4
- Fixed patch compatibility issue with Debian 13 (Proxmox 9) where patch v2.8 causes NUL byte errors during driver patching.
- Added automatic detection and installation of patch v2.7.6 when needed for NVIDIA driver patching.
- Improved error logging for the patching process.

Changes in version 1.3
- Added support for driver version 19.1 (580.82.02) - supports RTX PRO 6000 Blackwell Server Edition.
- Updated supported vGPU driver versions to 18.3, 18.4, 19.0, and 19.1.
- Reordered driver selection menu to show newest versions first (19.1, 19.0, 18.4, 18.3).
- Reverted licensing system to use FastAPI-DLS (from v1.1) instead of nvlts (v1.2) for better reliability.
- **RTX 5000 Series Database**: Added all RTX 5000 desktop GPUs (5090, 5090 D, 5080, 5070 Ti, 5070, 5060 Ti, 5060, 5050) to database with driver version 19 (vGPU unlock not supported on consumer GeForce cards).
- **Database Improvements**: Updated gpu_info.db with corrected native vGPU support for RTX A5000. Improved 17 GPU descriptions by replacing generic "Graphics Device" entries with proper names from PCI IDs database.
- All other v1.2 improvements maintained (Proxmox 8/9 support, pve-nvidia-vgpu-helper, wget downloads).

Changes in version 1.2 (forker anomixer's release)
- Added support for Proxmox 9
- Removed support for Proxmox 7
- Removed kernel pinning as it's no longer necessary
- Integrated `pve-nvidia-vgpu-helper` for a more robust setup
- Updated supported vGPU driver versions to 18.3, 18.4, and 19.0
- Removed support for older driver versions (16.x, 17.0)
- Switched from `megadl` to `wget` for downloading drivers

Changes in version 1.1 (original author wvthoog's latest release)
- Added new driver versions: 16.2, 16.4, 17.0
- Added checks for multiple GPUs
- Added MD5 checksums on downloaded files
- Created database to check for PCI IDs to determine native GPU support
- Implemented UDEV rules for multiple GPU handling
- Added Docker-based FastAPI-DLS licensing
- Created PowerShell and Bash license retrieval scripts

## Supported NVIDIA Driver Versions

### v20.x Series (Kernel 7.x Support)
- **20.1**: 595.71.03 (latest, ZIP format)
- **20.0**: 595.58.02 (Kernel 7.x support)

### v19.x Series (Native vGPU Only)
- **19.5**: 580.159.01 (latest release)
- **19.4**: 580.126.08
- **19.3**: 580.105.06
- **19.2**: 580.95.02 (supports RTX PRO 6000D)
- **19.1**: 580.82.02 (supports RTX PRO 6000 Blackwell Server Edition)
- **19.0**: 580.65.05 (recommended for Proxmox 8/9)

### v18.x Series (Native vGPU Only)
- **18.4**: 570.172.07 (stable)
- **18.3**: 570.158.02 (older stable)
- **18.1**: 570.133.10 (PTHyperdrive fork addition)
- **18.0**: 570.124.03 (PTHyperdrive fork addition, Pascal or newer GPUs)

### v17.x Series (Pascal/Newer GPUs)
- **17.6**: 550.163.02 (Native vGPU only)
- **17.5**: 550.144.02 (Pascal or newer GPUs)
- **17.4**: 550.127.06 (Pascal or newer GPUs)
- **17.3**: 550.90.05 (Pascal or newer GPUs)
- **17.1**: 550.54.16 (Pascal or newer GPUs)
- **17.0**: 550.54.10 (Pascal or newer GPUs, legacy support)

### v16.x Series (Pascal/Older GPUs)
- **16.14**: 535.309.01 (latest)
- **16.13**: 535.288.01
- **16.12**: 535.274.03
- **16.11**: 535.261.03
- **16.10**: 535.247.01
- **16.9**: 535.230.02 (Use with Pascal or older GPUs)
- **16.8**: 535.216.01 (Use with Pascal or older GPUs)
- **16.7**: 535.183.04 (Use with Pascal or older GPUs)
- **16.5**: 535.161.05 (Use with Pascal or older GPUs)
- **16.2**: 535.129.03 (Use with Pascal or older GPUs)
- **16.1**: 535.104.06 (Use with Pascal or older GPUs)
- **16.0**: 535.54.06 (Use with Pascal or older GPUs)

### Menu Options Explained

**Option 1: New vGPU installation**
- Complete setup from scratch
- Automatically detects your GPU and suggests compatible driver versions
- Configures system for vGPU support
- Handles both native vGPU and vgpu_unlock scenarios

**Option 2: Upgrade vGPU installation**
- Upgrades existing vGPU drivers to newer versions
- Removes previous drivers before installing new ones
- Maintains existing configuration and UDEV rules

**Option 3: Remove vGPU installation**
- Clean removal of entire vGPU stack
- Removes NVIDIA drivers, vgpu_unlock-rs, and vgpu-proxmox
- Option to remove FastAPI-DLS licensing server
- Prepares system for fresh reinstallation

**Option 4: Download vGPU drivers**
- Downloads drivers without installing them
- Includes smart download logic with file existence checking and MD5 verification
- Useful for offline installations or testing
- Supports multiple driver versions

**Option 5: Download guest drivers**
- Downloads corresponding Linux/Windows guest drivers
- Provides drivers matching your host driver version
- Essential for VM vGPU functionality

**Option 6: License vGPU**
- Sets up Docker-based FastAPI-DLS licensing server
- Generates license retrieval scripts for VMs
- Configures SSL certificates and database

### What to Expect During Installation

**Step 1 (System Preparation):**
- GPU detection and compatibility checking
- APT repository configuration for Proxmox
- Package installation (build tools, headers, etc.)
- IOMMU configuration for Intel/AMD platforms
- Kernel module setup and secure boot preparation
- **Kernel compatibility management** (v1.75+): Automatic kernel downgrade for vGPU unlock on Proxmox VE 9.1.1+
- Optional vgpu_unlock-rs compilation

**Step 2 (Driver Installation):**
- Smart driver download with file existence checking
- Driver installation with appropriate flags
- System service configuration
- Guest driver download (optional)
- Licensing server setup (optional)

### Smart Download Features (v1.8+)

The installer now includes intelligent download management:

**File Existence Checking:**
- Before downloading, the installer checks if the driver file already exists
- Skips download if file is valid (executable for .run, valid ZIP for .zip)
- Automatic decision-making based on file validity

**Download Scenarios:**
- **File exists and is valid**: Skips download with notification
- **File exists but is invalid**: Re-downloads the file
- **File doesn't exist**: Proceeds with normal download

**User Notifications:**
```
[+] Driver file already exists, skipping download
[-] Driver file exists but not executable, re-downloading...
[+] ZIP file is valid, skipping download
```

### Kernel Compatibility (v1.8+)

The installer supports kernel 7.x with vGPU 20.0 and 20.1:

**Kernel 7.x Support:**
- vGPU 20.0 (595.58.02) and 20.1 (595.71.03) support kernel 7.x
- Proxmox VE 9.2+ with kernel 7.0.2-6-pve and later
- No kernel downgrade needed for these versions

**Older Kernel Support:**
- vGPU 19.x and earlier work with kernel 6.14-6.16
- Kernel 6.17+ requires vGPU 20.0+ or manual kernel downgrade

### Multi-GPU Systems

If you have multiple NVIDIA GPUs:
1. The script will detect all GPUs automatically
2. You'll be prompted to select which GPU to configure for vGPU
3. Other GPUs can be configured for passthrough via UDEV rules
4. The script provides detailed information about each GPU's vGPU capabilities

### Guest Driver Integration

Starting from v1.7, the script includes built-in guest driver support:
- Automatic prompts to download guest drivers after host installation
- Curated catalog with Linux and Windows drivers for each vGPU branch
- Sanitized filenames and robust download mechanisms
- Support for both curl and wget with automatic fallbacks

### Post-Installation Verification

After successful installation:
```bash
# Check vGPU status
nvidia-smi vgpu

# List available mdev types
mdevctl types

# Verify IOMMU groups
find /sys/kernel/iommu_groups/ -type l

# Check service status
systemctl status nvidia-vgpud.service
systemctl status nvidia-vgpu-mgr.service
```

![RTX PRO 6000 Blackwell Server Edition vGPU MDEV Enabled at Resource Mappings page of Proxmox VE 9](pic/vgpu-rtxpro6kbwse-pcimapping.png)

## Secure Boot Support

The installer includes comprehensive Secure Boot integration:

**Automatic Signed Kernel & Tooling Installation**:
- Detects if Secure Boot is enabled directly via UEFI variables (`/sys/firmware/efi/efivars`) or fallback to `mokutil`.
- Automatically installs required prerequisites (`shim-signed`, `grub-efi-amd64-signed`, `mokutil`) if Secure Boot is active.
- Automatically installs `proxmox-kernel-*-signed` if available, and falls back to unsigned kernel with warning if signed variant unavailable.
- No behavior change when Secure Boot is disabled.

**MOK Key Management & Auto-Enrollment**:
- Generates RSA 4096 keys for module signing.
- Automatically enrolls keys via `mokutil` during installation.
- Supports manual enrollment if needed, with keys backed up for recovery.

**Persistent DKMS Module Signing (New in v1.82+)**:
- NVIDIA driver modules are automatically signed with MOK keys during installation.
- Configures the DKMS framework (`/etc/dkms/framework.conf.d/nvidia-vgpu.conf` or `/etc/dkms/framework.conf`) to point to the generated custom keys.
- **Why this is critical**: This ensures that when Proxmox updates the kernel and DKMS automatically rebuilds the NVIDIA modules in the future, DKMS will automatically sign the rebuilt modules with the same enrolled key, preventing driver load failures ("bad shim signature" or module load errors) after kernel upgrades.

**Issue #14 & Future-Proofing**:
- Resolves "bad shim signature" boot failures.
- Ensures signed kernel is installed when Secure Boot is active.
- Provides clear warnings if signed kernel unavailable.

## Advanced Usage

### Command Line Options (v1.8)

By default, host drivers are resolved via **auto-discovery** on `alist.homelabproject.cc` (no URL to copy). Use `--url` or `--file` only when you need a manual source.

| Option | Purpose |
|--------|---------|
| `--debug` | Verbose logging to `debug.log` |
| `--step N` | Resume at step `N` (saved in `config.txt`) |
| `--url <url>` | Download host driver from a direct HTTP(S) link (skips menu & auto-discovery) |
| `--file <path>` | Use a local `.run` already on disk (skips download & menu) |

Run from the installer directory (where `proxmox-installer.sh` lives). Values are stored in `config.txt` and reused on the next run unless you change them.

#### `--url` — direct download link

**When to use**

- Auto-discovery failed for your vGPU branch
- You host the driver on an internal mirror
- You have a **direct** download URL (wget/curl must work without Mega.nz login)

**Not supported via `--url`**: Mega.nz page links (use `--file` after downloading with `megadl`, or let v1.8 auto-discovery use alist).

**Supported formats**

1. **`.run` file** — downloaded with `wget`, filename taken from the URL path  
2. **`.zip` archive** — downloaded, extracted in the current directory, first `*.run` found is used  

The `.run` basename must match a version in the installer catalog (e.g. `NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run`), or the script exits with “Unrecognized filename”.

**Examples — alist direct links**

```bash
cd /path/to/proxmox-vgpu-installer

# Nested Host_Drivers layout (typical for 16.9, 17.5, 19.x)
sudo bash proxmox-installer.sh --url \
  "https://alist.homelabproject.cc/d/foxipan/vGPU/16.9/NVIDIA-GRID-Linux-KVM-535.230.02-539.19/Host_Drivers/NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run"

# ZIP-only layout (e.g. 16.13, 20.1) — script unzips and picks the .run inside
sudo bash proxmox-installer.sh --url \
  "https://alist.homelabproject.cc/d/foxipan/vGPU/16.13/NVIDIA-GRID-Linux-KVM-535.288.01-539.64.zip"

# Resume step 2 after step 1 + reboot (URL kept in config.txt)
sudo bash proxmox-installer.sh --step 2
```

**How to find an alist URL**

1. Open `https://alist.homelabproject.cc/foxipan/vGPU/<branch>/` (e.g. `16.9`, `17.5`).  
2. Browse to `NVIDIA-GRID-Linux-KVM-…/Host_Drivers/` and copy the download link for `NVIDIA-Linux-x86_64-*-vgpu-kvm.run`, **or** copy the `.zip` link if only ZIP is offered.  
3. The link must start with `https://alist.homelabproject.cc/d/foxipan/vGPU/…` (the `/d/` path is the direct download endpoint).

**Other mirrors**

```bash
sudo bash proxmox-installer.sh --url "https://your-mirror.example/internal/NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run"
```

#### `--file` — local driver already downloaded

Place the `.run` in the installer directory (or pass a path the script can read), then:

```bash
sudo bash proxmox-installer.sh --file NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run
```

Use this for offline installs, Mega.nz files saved via `megadl`, or when you do not want any network download during install.

#### Combining options

```bash
# Debug + custom URL + start at step 2
sudo bash proxmox-installer.sh --debug --url "https://alist.homelabproject.cc/d/foxipan/vGPU/19.5/..." --step 2
```

**Clearing a saved URL**: remove the `URL=` or `FILE=` line from `config.txt`, or delete `config.txt`, then run the script normally to use auto-discovery again.

### Menu Options

1. **New vGPU installation** - Complete setup from scratch
2. **Upgrade vGPU installation** - Upgrade existing vGPU drivers
3. **Remove vGPU installation** - Clean removal of vGPU stack
4. **Download vGPU drivers** - Download drivers without installation
5. **Download guest drivers** - Download Linux/Windows guest drivers
6. **License vGPU** - Setup FastAPI-DLS licensing server
7. **Exit** - Exit the installer

## Database Management

The `gpu_info.db` SQLite database contains GPU compatibility information for vGPU detection (use [SQLite Tools](https://sqlite.org/download.html) to view/edit):

```bash
# View all native vGPU cards
./sqlite3.exe gpu_info.db "SELECT * FROM gpu_info WHERE vgpu='Native';"

# Add a new GPU (replace XXXX with actual device ID)
./sqlite3.exe gpu_info.db "INSERT OR IGNORE INTO gpu_info VALUES ('10de', 'XXXX', 'GPU Name', 'Native', '19;18;17', 'Architecture');"

# Update existing GPU support
./sqlite3.exe gpu_info.db "UPDATE gpu_info SET vgpu='Native', driver='19;18;17' WHERE deviceid='XXXX';"

# Check for duplicates
./sqlite3.exe gpu_info.db "SELECT deviceid, COUNT(*) FROM gpu_info GROUP BY deviceid HAVING COUNT(*) > 1;"
```

**Database Schema:**
- `vendorid`: GPU vendor (always "10de" for NVIDIA)
- `deviceid`: PCI device ID (primary key)
- `description`: GPU model name
- `vgpu`: Support level ("Native", "Yes", "No")
- `driver`: Supported driver versions (semicolon-separated)
- `chip`: GPU architecture

## To-Do

1. Replace FastAPI-DLS with nvlts (https://git.collinwebdesigns.de/vgpu/nvlts) in future releases
2. Continue adding new GPU data to gpu_info.db as new models are released (RTX 5000 series desktop GPUs completed)
3. Enhanced automation for guest driver distribution across VM clusters
4. Integration testing for latest Proxmox VE versions and NVIDIA drivers
5. Implement download caching for faster subsequent installations

## Contributing

This project has evolved through contributions from multiple developers:
- **Original Author**: wvthoog.nl
- **Major Contributors**: RocketRammer, LeonardSEO, Anomixer, PTHyperdrive

### Adding New GPU Support

To add support for new GPUs, update the `gpu_info.db` file using SQLite:

```bash
# Add new GPU entry
sqlite3 gpu_info.db "INSERT OR IGNORE INTO gpu_info VALUES ('10de', 'XXXX', 'GPU Name', 'Native', '19;18;17', 'Architecture');"

# Verify entry
sqlite3 gpu_info.db "SELECT * FROM gpu_info WHERE deviceid='XXXX';"
```

### Driver Version Support

To add new driver versions:
1. Update the driver registry in `proxmox-installer.sh`
2. Add corresponding patch files to `driver_patches.json`
3. Update guest driver catalog URLs
4. Test compatibility across Proxmox versions

## License

This project follows the original licensing terms established by the community. Please refer to the source repositories and original author for specific license details.

## Support

For issues and questions:
1. Check the [PVE Wiki](https://pve.proxmox.com/wiki/NVIDIA_vGPU_on_Proxmox_VE) for general vGPU setup
2. Review driver compatibility on NVIDIA's official documentation
3. Consult the original blog post for detailed setup instructions
4. Check GitHub/GitLab issues for known problems and solutions

## Acknowledgments

- Original work by wvthoog.nl
- Community contributions and improvements
- NVIDIA for vGPU technology and driver support
- Proxmox team for excellent virtualization platform
- Various community mirrors and driver sources


