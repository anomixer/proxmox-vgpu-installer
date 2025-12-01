# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This repository contains a comprehensive Bash script that automates the installation and configuration of NVIDIA vGPU drivers on Proxmox VE 7, 8, and 9 hypervisors. The project handles the complex process of setting up vGPU support including driver installation, patching, licensing, and system configuration with support for both native vGPU and vgpu_unlock capabilities.

## Architecture and Core Components

### Main Scripts
- `proxmox-installer.sh` - Current installer (v1.75, supports driver 16.x-19.x with smart download, kernel compatibility management, and new sources repository support)
- `old/proxmox-installer-v1.72.sh` - Previous version with driver updates
- `old/proxmox-installer-v1.71.sh` - Added host and guest drivers v19.2 and v16.3
- `old/proxmox-installer-v1.7.sh` - Forker's version with guest driver catalog integration
- `old/proxmox-installer-v1.61.sh` - add driver 19.2
- `old/proxmox-installer-v1.6.sh` - Forker's version with new driver matrix and patch mechanism
- `old/proxmox-installer-v1.51.sh` - Previous version with comprehensive driver support
- `old/proxmox-installer-v1.5.sh` - Legacy version with Proxmox 7/8/9 support
- `old/proxmox-installer-v1.4.sh` - Older version for Proxmox 8/9 with driver versions 18.3-19.1
- `old/proxmox-installer-v1.3.sh` - Historical version
- `old/proxmox-installer-v1.2.sh` - Legacy version
- `old/proxmox-installer-v1.1.sh` - Original version with older driver support
- All scripts follow a two-step installation process requiring a reboot between steps

### Key Configuration Files
- `config.txt` - Runtime configuration file created during installation (stores step, driver version, vGPU support type)
- `gpu_info.db` - SQLite database containing GPU compatibility information (PCI device IDs, vGPU capabilities, supported driver versions)
- `driver_patches.json` - Externalized patch-to-driver mapping for simplified maintenance

### Repository Format Support (v1.72+)
- **Legacy `*.list` format**: Used by Proxmox 7.x and 8.x (Debian 11/12)
- **Modern `*.sources` format**: Used by Proxmox 9.x (Debian 13/trixie)
- **Intelligent Detection**: Automatic format selection based on system version
- **Enterprise Repository Handling**: Enhanced disabling mechanism for both formats

### Installation Process Architecture
The installer follows a comprehensive multi-step workflow:

1. **Step 1**: System preparation
   - **Enhanced APT repository configuration** (v1.72+): Automatic format detection and configuration
   - GPU detection and compatibility checking against `gpu_info.db`
   - GRUB/boot configuration for IOMMU (intel_iommu=on/amd_iommu=on)
   - Kernel module setup and secure boot integration
   - Optional pve-nvidia-vgpu-helper execution
   - vgpu_unlock-rs compilation for non-native vGPU cards

2. **Reboot Required**: System restart to apply kernel changes

3. **Step 2**: Driver installation and finalization
   - **Smart driver download with existence checking and MD5 verification** (v1.72+)
   - Driver patching for vgpu_unlock scenarios (if needed)
   - SR-IOV configuration and systemd service management
   - Guest driver catalog integration and download
   - FastAPI-DLS licensing server setup (optional)

### vGPU Support Types
- **Native**: GPUs with built-in vGPU support (Tesla/Quadro/A-series cards)
- **vgpu_unlock**: Consumer GPUs made vGPU-capable through patching and vgpu_unlock-rs
- **Passthrough**: Non-vGPU capable cards configured for VM passthrough via UDEV rules

## Common Development Commands

### Running the Installer
```bash
# Basic installation
sudo bash proxmox-installer.sh

# Debug mode (shows all command output)
sudo bash proxmox-installer.sh --debug

# Resume from specific step
sudo bash proxmox-installer.sh --step 2

# Install with pre-downloaded driver file
sudo bash proxmox-installer.sh --file NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run

# Install with custom driver URL
sudo bash proxmox-installer.sh --url "https://example.com/driver.run"
```

### Maintenance Operations
```bash
# Download drivers only (option 4 in menu) - includes smart download logic
sudo bash proxmox-installer.sh
# Select option 4

# Download guest drivers (option 5 in menu)
sudo bash proxmox-installer.sh
# Select option 5

# Setup licensing server only (option 6 in menu)
sudo bash proxmox-installer.sh
# Select option 6

# Clean removal (option 3 in menu)
sudo bash proxmox-installer.sh
# Select option 3
```

### Post-Installation Verification
```bash
# Check vGPU status
nvidia-smi vgpu

# List available mediated device types
mdevctl types

# List PCI devices to verify SR-IOV
lspci -d 10de:

# Check IOMMU groups
find /sys/kernel/iommu_groups/ -type l

# Check NVIDIA services status
systemctl status nvidia-vgpud.service
systemctl status nvidia-vgpu-mgr.service
```

## Development Context

### Driver Version Mapping
The installer supports these NVIDIA driver versions:

**v19.x Series** (Native vGPU Only):
- **19.2**: 580.95.02 (supports RTX PRO 6000D)
- **19.1**: 580.82.02 (supports RTX PRO 6000 Blackwell Server Edition)
- **19.0**: 580.65.05 (recommended for Proxmox 8/9)

**v18.x Series** (Native vGPU Only):
- **18.4**: 570.172.07 (stable)
- **18.3**: 570.158.02 (older stable)
- **18.1**: 570.133.10 (PTHyperdrive fork addition)
- **18.0**: 570.124.03 (PTHyperdrive fork addition, Pascal or newer GPUs)

**v17.x Series** (Pascal/Newer GPUs):
- **17.6**: 550.163.02 (Native vGPU only)
- **17.5**: 550.144.02 (Pascal or newer GPUs)
- **17.4**: 550.127.06 (Pascal or newer GPUs)
- **17.3**: 550.90.05 (Pascal or newer GPUs)
- **17.1**: 550.54.16 (Pascal or newer GPUs)
- **17.0**: 550.54.10 (Pascal or newer GPUs, legacy support)

**v16.x Series** (Pascal/Older GPUs):
- **16.9**: 535.230.02 (Use with Pascal or older GPUs)
- **16.8**: 535.216.01 (Use with Pascal or older GPUs) 
- **16.7**: 535.183.04 (Use with Pascal or older GPUs)
- **16.5**: 535.161.05 (Use with Pascal or older GPUs)
- **16.2**: 535.129.03 (Use with Pascal or older GPUs)
- **16.1**: 535.104.06 (Use with Pascal or older GPUs)
- **16.0**: 535.54.06 (Use with Pascal or older GPUs)

### Key Dependencies
- `git` - For cloning vgpu-proxmox and vgpu_unlock-rs repositories
- `build-essential`, `dkms` - For compiling drivers and kernel modules
- `mdevctl` - For managing mediated devices
- `pve-nvidia-vgpu-helper` - Proxmox's official vGPU helper (v18.0+ only)
- `sqlite3` - For querying the GPU compatibility database
- `jq` or `python3` - For parsing driver_patches.json configuration
- `curl` or `wget` - For downloading drivers and guest drivers
- `megatools` - For downloading from mega.nz mirrors (legacy drivers)
- `mokutil` - For Secure Boot key management
- Docker (optional) - For FastAPI-DLS licensing server
- `gridd-unlock-patcher` - Required for FastAPI-DLS with v18.0+ drivers

### External Resources
- **vgpu-proxmox**: GitLab repository containing driver patches
- **vgpu_unlock-rs**: Rust library enabling vGPU on consumer cards
- **FastAPI-DLS**: Docker-based license server for vGPU licensing
- Driver downloads from `alist.homelabproject.cc` (v18.3+), legacy links from `mega.nz` (v16.x–v18.1)
- Guest driver catalog from Google's storage.googleapis.com for Linux and Windows drivers
- GNU patch 2.7.6 - Backported for compatibility with Debian 13 patch 2.8 issues

### Proxmox Integration Points
- Modifies APT repositories (`/etc/apt/sources.list`, `/etc/apt/sources.list.d/`)
- Configures GRUB bootloader (`/etc/default/grub`) with IOMMU settings
- Sets up kernel modules (`/etc/modules`, `/etc/modprobe.d/`)
- Creates systemd service overrides for NVIDIA services with vgpu_unlock integration
- Integrates with Proxmox's PCI passthrough system via UDEV rules
- Secure Boot integration with custom module signing

### Important Implementation Notes

#### Smart Driver Download Management (v1.72+)
- **File Existence Check**: Before downloading, checks if driver file already exists locally
- **MD5 Verification**: Validates existing files against expected checksums from driver registry
- **Intelligent Decision Making**:
  - **File exists and MD5 matches**: Skips download with informative message
  - **File exists but MD5 mismatches**: Backs up old file as `.bak` and re-downloads
  - **File doesn't exist**: Proceeds with normal download process
- **User Feedback**: Clear notifications about download decisions and file status
- **Backup Mechanism**: Existing files are safely backed up before re-downloading
- **Unified Logic**: Same smart download logic applies to both main installation and option 4 downloads

#### Driver Download Strategy (v1.5+)
- **Legacy (v16.x–v17.x)**: mega.nz + megadl; install args `--dkms -m=kernel -s`
- **v18.0–v18.1**: mega.nz + megadl; install args `--dkms -s`
- **v18.3+ and 19.x**: alist.homelabproject.cc + wget/curl; install args `--dkms -s`
- Auto-detects download tool by URL; installs megatools on demand
- MD5 checksum validation for all downloaded drivers
- Smart file management with existence checking (v1.72+)

#### Secure Boot Support (v1.6+)
- Automatic detection of Secure Boot state
- Generation of custom module signing keys
- MOK (Machine Owner Key) enrollment process
- Module signing during driver installation
- Seamless integration with Proxmox's boot security

#### Guest Driver Integration (v1.7+)
- Built-in catalog with curated Linux and Windows guest drivers
- Automatic download prompts after host driver installation
- Sanitized filename handling and download fallbacks
- Branch-aware guest driver selection and guidance
- Support for automated guest driver deployment

### Multi-GPU Handling
The installer detects multiple GPUs and provides intelligent selection:
- Queries GPU compatibility database for vGPU support levels
- Allows user selection of which GPU to configure for vGPU
- Automatically sets up PCI passthrough for remaining GPUs via UDEV rules
- Handles mixed GPU scenarios (native + consumer cards)
- Provides detailed GPU information and compatibility warnings

### State Management
Installation state is persisted in `config.txt` allowing:
- Script resumption after reboots
- Context preservation across multi-step process
- Step-by-step execution control
- Driver version and vGPU support type tracking
- Configuration persistence for troubleshooting

### User Experience Improvements (v1.5+)
- **Smart Download Logic** (v1.72+): File existence checking and MD5 verification with intelligent skipping
- **Kernel Compatibility Management** (v1.75+): Automatic kernel downgrade for vGPU unlock compatibility on Proxmox VE 9.1.1+
- **Refined Driver Selection Menu**: Clean, streamlined display with compatibility annotations
- **Smart Platform Detection**: Automatic Proxmox version detection with driver recommendations
- **Compatibility Warnings**: Clear notices about FastAPI-DLS requirements for different vGPU versions
- **Enhanced Error Handling**: Colored output with detailed error messages and suggestions
- **Installation Summary**: Comprehensive post-installation guidance and verification steps

### Error Handling
The script includes comprehensive error checking:
- Colored output for different log levels (info, notification, error, warning)
- Debug mode with full command output logging to `debug.log`
- Graceful fallbacks for missing dependencies
- MD5 checksum validation with corruption detection
- Network connectivity and download reliability checks
- Smart download decision making with user feedback
- Graceful handling of missing patch files

### Security Considerations
- Requires root privileges for system modifications (appropriate for system-level changes)
- Downloads drivers from external sources with MD5 verification
- Secure Boot integration prevents unsigned kernel modules
- Creates isolated Docker containers for licensing (network exposure consideration)
- Generates and manages custom SSL certificates for FastAPI-DLS
- Safe handling of patch files with integrity checks
- Smart file management with backup mechanisms

### Platform Compatibility
- **Proxmox VE 7.x**: Legacy mode with v16.x/v17.0 drivers, bypasses `pve-nvidia-vgpu-helper`
- **Proxmox VE 8.x**: Full feature support with all driver versions, uses `pve-nvidia-vgpu-helper` for v18.0+
- **Proxmox VE 9.x**: Complete support including latest driver versions and Debian 13 compatibility
- **Intel Platforms**: Supports VT-d IOMMU with `intel_iommu=on iommu=pt`
- **AMD Platforms**: Supports AMD-Vi IOMMU with `amd_iommu=on iommu=pt`
- **GPU Architectures**: Works with Pascal, Turing, Ampere, Ada Lovelace, and Blackwell architectures
- **Mixed Driver Sources**: alist.homelabproject.cc (current) and mega.nz (legacy/fork versions)
- **Smart Downloads**: Works with both cached and fresh downloads across all supported platforms

### Database Schema
The `gpu_info.db` SQLite database uses the following schema:
- `vendorid`: GPU vendor (always "10de" for NVIDIA)
- `deviceid`: PCI device ID (primary key)
- `description`: GPU model name
- `vgpu`: Support level ("Native", "Yes", "No")
- `driver`: Supported driver versions (semicolon-separated)
- `chip`: GPU architecture (Pascal, Turing, Ampere, etc.)

### Recent Updates

#### v1.75 (Current)
- **Kernel Compatibility Management**: Automatic kernel downgrade for vGPU unlock compatibility
  - Detects when running Proxmox VE 9.1.1+ with kernel 6.17 or higher
  - Automatically downgrades to kernel 6.14.11-4-pve for vGPU patch compatibility
  - Pins the downgraded kernel to ensure consistent vGPU patching environment
  - Only applies to vgpu_unlock scenarios (VGPU_SUPPORT="Yes")
- **Driver Updates**: Added vGPU 19.3 driver support (580.105.06)
- **Bug Fixes**: Corrected v16.8 driver MD5 checksum and various driver mapping corrections
- **Enhanced User Experience**: Improved messaging and notifications for kernel management

#### v1.73 (Previous)
- **Minor fix**: pve-nvidia-vgpu-helper setup run_command

#### v1.72
- **Major Enhancement**: Added support for Debian 13 (trixie) and Proxmox 9's new `*.sources` repository format
- **Intelligent Format Detection**: Automatically detects system version and chooses between `*.sources` (trixie+) and `*.list` (legacy) formats
- **Enhanced Enterprise Repository Handling**: Properly handles `Enabled: false` for `*.sources` format and commenting for `*.list` format
- **GPG Security**: Includes proper `Signed-By` keyring references (`/usr/share/keyrings/proxmox-archive-keyring.gpg`) for secure repository access
- **Backward Compatibility**: Maintains full compatibility with Proxmox 7.x and 8.x systems
- **Improved Repository Configuration**: Modular functions for better maintainability and error handling
- **Major Enhancement**: Added intelligent driver download management with file existence checking and MD5 verification
- **Smart Download Logic**: The installer now checks if driver files already exist locally before downloading
- **MD5 Verification**: Automatically validates existing files against expected checksums
- **Download Optimization**: Skips downloads when files are valid, re-downloads only when checksum mismatches occur
- **Backup Mechanism**: Existing files are backed up as .bak files before re-downloading
- **Unified Implementation**: Same smart download logic applied to both main installation (perform_step_two) and option 4 (driver downloads)
- **Enhanced User Feedback**: Clear notifications about download decisions and file status
- **Performance Optimization**: Reduces unnecessary downloads and bandwidth usage for repeat installations
- All code comments converted to English for better internationalization

#### v1.7
- Added built-in guest driver catalog with automatic download prompts
- Improved patched driver discovery with artifact tracking
- Externalized patch-to-driver mapping in `driver_patches.json`
- Enhanced FastAPI-DLS Docker Compose with asyncio support
- Comprehensive installation summary with verification steps
- Attribution section for project contributors

### Development Testing
For testing new features or driver versions:
1. Use `--debug` flag to see all command output
2. Check `debug.log` for detailed execution logs
3. Verify database queries with `sqlite3 gpu_info.db`
4. Test with `--step 1` and `--step 2` for incremental debugging
5. Use `--file` parameter for testing with pre-downloaded drivers
6. Test smart download functionality by intentionally creating checksum mismatches
7. Verify backup mechanism by checking for .bak files after re-downloads

### Testing Smart Download Features (v1.73+)
```bash
# Test with existing valid file
touch NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run
# Should skip download and show matching MD5 message

# Test with existing invalid file
echo "invalid content" > NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run
# Should backup file and re-download

# Test with non-existent file
rm -f NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run
# Should proceed with normal download
```

### Troubleshooting Common Issues
- **Patch compatibility**: Automatic patch 2.7.6 installation for Debian 13
- **Repository format conflicts** (v1.72+): Automatic handling of `*.list` vs `*.sources` format detection
- **Enterprise repository conflicts** (v1.72+): Proper disabling with `Enabled: false` or commenting based on format
- **Download failures**: Automatic fallback between curl/wget/megadl
- **Smart download issues** (v1.73+): Check file permissions and MD5 registry values
- **Secure Boot issues**: MOK enrollment process guidance
- **GPU detection**: Database queries and compatibility checking
- **Service conflicts**: Proper systemd service management
- **Network issues**: Robust download retry and validation mechanisms
- **File corruption**: Smart download automatically re-downloads corrupted files
