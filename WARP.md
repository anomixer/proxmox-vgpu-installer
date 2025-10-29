# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This repository contains a Bash script that configures Proxmox 8 or 9 servers to use NVIDIA vGPUs. The project automates the complex process of setting up vGPU support on Proxmox hypervisors, including driver installation, patching, licensing, and configuration.

## Architecture and Core Components

### Main Scripts
- `proxmox-installer.sh` - Current installer (v1.61, support driver version 19.2)
- `old/proxmox-installer-v1.6.sh` - Forker's version (new driver matrix, patch mechanism, and new workflow, etc.)
- `old/proxmox-installer-v1.51.sh` - Previous version (supports Proxmox 7/8/9, comprehensive driver support)
- `old/proxmox-installer-v1.5.sh` - Old version (supports Proxmox 7/8/9, comprehensive driver support)
- `old/proxmox-installer-v1.4.sh` - Older version (Proxmox 8/9, driver versions 18.3, 18.4, 19.0, 19.1)
- `old/proxmox-installer-v1.3.sh` - Older version
- `old/proxmox-installer-v1.2.sh` - Older version
- `old/proxmox-installer-v1.1.sh` - Original version (supports older driver versions 16.x, 17.0)
- All scripts follow a two-step installation process requiring a reboot between steps

### Key Configuration Files
- `config.txt` - Runtime configuration file created during installation (stores step, driver version, vGPU support type)
- `gpu_info.db` - SQLite database containing GPU compatibility information (PCI device IDs, vGPU capabilities, supported driver versions)

### Installation Process Architecture
The installer follows a multi-step workflow:

1. **Step 1**: System preparation
   - APT repository configuration for Proxmox
   - GPU detection and compatibility checking against `gpu_info.db`
   - GRUB/boot configuration for IOMMU
   - Kernel module setup
   - vgpu_unlock-rs compilation (for non-native vGPU cards)

2. **Reboot Required**: System restart to apply kernel changes

3. **Step 2**: Driver installation and finalization
   - NVIDIA driver download and installation
   - Driver patching (for vgpu_unlock scenarios)
   - SR-IOV configuration
   - FastAPI-DLS licensing setup (optional)

### vGPU Support Types
- **Native**: GPUs with built-in vGPU support (Tesla/Quadro cards)
- **vgpu_unlock**: Consumer GPUs made vGPU-capable through patching
- **Passthrough**: Non-vGPU capable cards configured for VM passthrough

## Common Development Commands

### Running the Installer
```bash
# Basic installation
sudo bash proxmox-installer-v1.x.sh

# Debug mode (shows all command output)
sudo bash proxmox-installer-v1.x.sh --debug

# Resume from specific step
sudo bash proxmox-installer-v1.x.sh --step 2

# Install with pre-downloaded driver file
sudo bash proxmox-installer-v1.x.sh --file NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run

# Install with custom driver URL
sudo bash proxmox-installer-v1.x.sh --url "https://example.com/driver.run"
```

### Maintenance Operations
```bash
# Download drivers only (option 4 in menu)
sudo bash proxmox-installer-v1.x.sh
# Select option 4

# Setup licensing server only (option 5 in menu)
sudo bash proxmox-installer-v1.x.sh
# Select option 5

# Clean removal (option 3 in menu)
sudo bash proxmox-installer-v1.x.sh
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
```

## Development Context

### Driver Version Mapping
The installer (v1.51) supports these NVIDIA driver versions:

**v19.x Series** (Native vGPU Only):
- **19.1**: 580.82.02 (latest, supports RTX PRO 6000 Blackwell Server Edition, patch file not yet available)
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
- **17.0**: 550.54.10 (Pascal or newer GPUs, v1.1 legacy support)

**v16.x Series** (Pascal/Older GPUs):
- **16.9**: 535.230.02 (Use with Pascal or older GPUs)
- **16.8**: 535.216.01 (Use with Pascal or older GPUs) 
- **16.7**: 535.183.04 (Use with Pascal or older GPUs)
- **16.5**: 535.161.05 (Use with Pascal or older GPUs)
- **16.2**: 535.129.03 (Use with Pascal or older GPUs, v1.1 legacy support)
- **16.1**: 535.104.06 (Use with Pascal or older GPUs, v1.1 legacy support)
- **16.0**: 535.54.06 (Use with Pascal or older GPUs, v1.1 legacy support)

### Key Dependencies
- `git` - For cloning vgpu-proxmox and vgpu_unlock-rs repositories
- `build-essential`, `dkms` - For compiling drivers and kernel modules
- `mdevctl` - For managing mediated devices
- `pve-nvidia-vgpu-helper` - Proxmox's official vGPU helper (v18.0+ only)
- `sqlite3` - For querying the GPU compatibility database
- Docker (optional) - For FastAPI-DLS licensing server
- `gridd-unlock-patcher` - Required for FastAPI-DLS with v18.0+ drivers

### External Resources
- **vgpu-proxmox**: GitLab repository containing driver patches
- **vgpu_unlock-rs**: Rust library enabling vGPU on consumer cards
- **FastAPI-DLS**: Docker-based license server for vGPU licensing
- Driver downloads from `alist.homelabproject.cc` (v18.3+), legacy links from `mega.nz` (v16.x–v18.1)

### Proxmox Integration Points
- Modifies APT repositories (`/etc/apt/sources.list`, `/etc/apt/sources.list.d/`)
- Configures GRUB bootloader (`/etc/default/grub`)
- Sets up kernel modules (`/etc/modules`, `/etc/modprobe.d/`)
- Creates systemd service overrides for NVIDIA services
- Integrates with Proxmox's PCI passthrough system

### Important Implementation Notes

- v1.51 split logic:
  - Legacy (v16.x–v17.x): mega.nz + megadl; install args `--dkms -m=kernel -s`.
  - v18.0–v18.1: mega.nz + megadl; install args `--dkms -s`.
  - v18.3+ and 19.x: alist.homelabproject.cc + wget; install args `--dkms -s`.
  - Auto-detect download tool by URL; installs megatools on demand.

### Multi-GPU Handling
The installer detects multiple GPUs and allows selection of which GPU to configure for vGPU while automatically setting up PCI passthrough for remaining GPUs via UDEV rules.

### State Management
Installation state is persisted in `config.txt` allowing the script to resume after reboots and maintain context across the multi-step process.

### User Experience Improvements (v1.5)
- **Refined Driver Selection Menu**: Clean, streamlined display with essential compatibility annotations
- **Smart Platform Detection**: Automatic Proxmox version detection with appropriate driver recommendations
- **Compatibility Warnings**: Clear notices about FastAPI-DLS requirements for different vGPU versions
- **Legacy Support Indicators**: Visual cues for users on older Proxmox installations

### Error Handling
The script includes comprehensive error checking with colored output for different log levels (info, notification, error) and maintains debug logs in `debug.log`.

### Security Considerations
- Requires root privileges for system modifications
- Downloads drivers from external sources with MD5 verification
- Creates Docker containers for licensing (network exposure consideration)

### Platform Compatibility
- Designed for Proxmox VE 7.x, 8.x, and 9.x (v1.5 restored Proxmox 7 support)
- **Proxmox 7**: Legacy mode with v16.x/v17.0 drivers, bypasses `pve-nvidia-vgpu-helper`
- **Proxmox 8/9**: Full feature support with all driver versions, uses `pve-nvidia-vgpu-helper` for v18.0+
- Supports both Intel and AMD platforms (different IOMMU configurations)
- Works with various NVIDIA GPU architectures through the database lookup system
- Mixed driver sources: alist.homelabproject.cc (current) and mega.nz (legacy/fork versions)
