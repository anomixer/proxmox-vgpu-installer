This is a little Bash script that configures a Proxmox 7, 8 or 9 server to use Nvidia vGPU's. 

For further instructions see original author's blogpost at https://wvthoog.nl/proxmox-7-vgpu-v3/

For the script architecture, features, installation, and usage, see https://deepwiki.com/anomixer/proxmox-vgpu-installer

Changes in version 1.7 (current release)
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
- Note: Currently there has no patch files available since driver version 19.1 (580.82.02). Please wait for the patch release.

Changes in version 1.6 (Forked and Improved by LeonardSEO)
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

▽ RTX PRO 6000 Blackwell Server Edition vGPU MDEV Enabled at Resource Mappings page of Proxmox VE 9
![vgpu](pic/vgpu-rtxpro6kbwse-pcimapping.png)


Changes in version 1.2 (forker anomixer's release)
- Added support for Proxmox 9.
- Removed support for Proxmox 7.
- Removed kernel pinning as it's no longer necessary.
- Integrated `pve-nvidia-vgpu-helper` for a more robust setup.
- Updated the host driver installation method and its service.
- Updated supported vGPU driver versions to 18.3, 18.4, and 19.0. Check [PVE Wiki](https://pve.proxmox.com/wiki/NVIDIA_vGPU_on_Proxmox_VE#Software_Versions).
- Removed support for older driver versions (16.x, 17.0).
- Switched from `megadl` to `wget` for downloading drivers from new URLs.

Changes in version 1.1 (original author wvthoog's latest release)
- Added new driver versions
    16.2
    16.4
    17.0
- Added checks for multiple GPU's
- Added MD5 checksums on downloaded files
- Created database to check for PCI ID's to determine if a GPU is natively supported
- If multiple GPU's are detected, pass through the rest using UDEV rules
- Always write config.txt to script directory
- Use Docker for hosting FastAPI-DLS (licensing)
- Create Powershell (ps1) and Bash (sh) files to retrieve licenses from FastAPI-DLS

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
1.  Replace FastAPI-DLS with nvlts (https://git.collinwebdesigns.de/vgpu/nvlts) in the future release. (current nvlts may not work).
2.  Continue adding new GPU data to gpu_info.db as new models are released (RTX 5000 series desktop GPUs completed).









