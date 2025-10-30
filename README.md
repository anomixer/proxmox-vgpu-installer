# Proxmox vGPU Installer

A comprehensive Bash script that automates the installation and configuration of NVIDIA vGPU drivers on Proxmox VE 7, 8, and 9 hypervisors. This tool supports multiple GPU types, driver versions, and provides both native vGPU and vgpu_unlock capabilities.

For detailed installation instructions, see the original author's blogpost at https://wvthoog.nl/proxmox-7-vgpu-v3/

For complete documentation on script architecture, features, and usage, visit https://deepwiki.com/anomixer/proxmox-vgpu-installer

## Features

- **Multi-Version Support**: Comprehensive driver support from v16.x through v19.x series
- **Smart Driver Downloads**: Intelligent download management with file existence checking and MD5 verification - skips downloads if files already exist and match expected checksums
- **Dual vGPU Modes**: Support for both native vGPU (Tesla/Quadro) and vgpu_unlock (consumer cards)
- **Guest Driver Catalog**: Built-in catalog with curated Linux and Windows guest drivers
- **Automated Licensing**: FastAPI-DLS licensing server deployment with Docker (for v16.x, v17.x)
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

1. **Clone the project from GitHub:**
   ```bash
   git clone https://github.com/anomixer/proxmox-vgpu-installer.git
   cd proxmox-vgpu-installer
   ```

2. **Run the installer:**
   ```bash
   sudo bash proxmox-installer.sh
   ```

2. **Follow the interactive menu:**
   - Select option 1 for new vGPU installation
   - Choose your NVIDIA driver version
   - Complete step 1 (system preparation)
   - Reboot when prompted
   - Run the script again to complete step 2 (driver installation)

3. **Verify installation:**
   ```bash
   nvidia-smi vgpu
   mdevctl types
   ```

## Version History

Changes in version 1.72 (current release)
- This version focuses on stability improvements.
- Replaced the Host Driver note with supported GPUs for easier configuration.
- Switched to the new *.sources repository format introduced in Debian 13 / Proxmox VE 9 (Trixie) to prevent duplicate sources that may cause apt update errors.
- Ensured that nvidia-vgpu-helper automatically installs pve-headers and enables SR-IOV capabilities for native vGPU cards.
- Added file existence checks and MD5 verification to prevent unnecessary re-downloads of host drivers.
- ** Note **: Patch files have not been released since driver version 19.1 (580.82.02). Please wait for an updated patch if you plan to use the vgpu_unlock feature.

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

### v19.x Series (Native vGPU Only)
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
- Optional vgpu_unlock-rs compilation

**Step 2 (Driver Installation):**
- Smart driver download with existence checking and MD5 verification
- Driver installation with appropriate flags
- System service configuration
- Guest driver download (optional)
- Licensing server setup (optional)

### Smart Download Features (v1.73+)

The installer now includes intelligent download management:

**File Existence Checking:**
- Before downloading, the installer checks if the driver file already exists
- MD5 checksum verification for existing files
- Automatic decision-making based on file integrity

**Download Scenarios:**
- **File exists and MD5 matches**: Skips download with notification
- **File exists but MD5 mismatches**: Backs up old file and re-downloads
- **File doesn't exist**: Proceeds with normal download

**User Notifications:**
```
[+] Driver file NVIDIA-Linux-x86_64-xxx-vgpu-kvm.run already exists and MD5 checksum matches. Skipping download.
[-] Driver file exists but MD5 checksum does not match. Re-downloading the file...
[+] Downloading vGPU NVIDIA-Linux-x86_64-xxx-vgpu-kvm.run host driver
```

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

## Advanced Usage

### Command Line Options

```bash
# Debug mode
sudo bash proxmox-installer.sh --debug

# Resume from specific step
sudo bash proxmox-installer.sh --step 2

# Install with pre-downloaded driver file
sudo bash proxmox-installer.sh --file NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run

# Install with custom driver URL
sudo bash proxmox-installer.sh --url "https://example.com/driver.run"
```

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

