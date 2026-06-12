# Proxmox vGPU & Windows Guest VM Setup FAQ

This document summarizes critical troubleshooting insights, hardware limitations, root causes, and workarounds identified during the configuration of NVIDIA vGPU setups on Proxmox VE hosts with Windows Guest VMs.

---

## Table of Contents
1. [Host-Level & Hardware Constraints](#1-host-level--hardware-constraints)
   - [iGPU Coexistence & BIOS Constraints](#igpu-coexistence--bios-constraints)
   - [The 256MB BAR1 Aperture Bottleneck (Resizable BAR)](#the-256mb-bar1-aperture-bottleneck-resizable-bar)
   - [Proxmox MMIO Allocation (PCI Hole)](#proxmox-mmio-allocation-pci-hole)
2. [Guest VM - NoVNC & SPICE Display Issues](#2-guest-vm---novnc--spice-display-issues)
   - [NVIDIA Guest Driver Installation Best Practices (Proxmox Wiki)](#nvidia-guest-driver-installation-best-practices-proxmox-wiki)
   - [Black Screen on NoVNC after Installing vGPU Driver](#black-screen-on-novnc-after-installing-vgpu-driver)
   - [Screen Resolution Locked/Limited (Standard VGA vs. VirtIO-GPU)](#screen-resolution-lockedlimited-standard-vga-vs-virtio-gpu)
3. [Guest VM - High VRAM & Compute Application Issues](#3-guest-vm---high-vram--compute-application-issues)
   - [VM Crashes (Video TDR Failure / GPU Lockup) when allocating >50% VRAM](#vm-crashes-video-tdr-failure--gpu-lockup-when-allocating-50-vram)
   - [Windows TDR Tweaks (Increasing Timeout Limits)](#windows-tdr-tweaks-increasing-timeout-limits)
   - [Ollama Offloads 100% to CPU on Smaller Profiles (e.g., 3GB Profile)](#ollama-offloads-100-to-cpu-on-smaller-profiles-eg-3gb-profile)

---

## 1. Host-Level & Hardware Constraints

### iGPU Coexistence & BIOS Constraints
*   **Problem:** Disabling the Integrated Graphics (iGPU) in the motherboard BIOS causes the host system to become unstable or fail to boot due to motherboard BIOS design limitations.
*   **Impact:** Keeping the iGPU enabled consumes physical MMIO (Memory-Mapped I/O) space and system RAM, reducing the available memory resources and PCIe address space available for the discrete GPU (dGPU).

### The 256MB BAR1 Aperture Bottleneck (Resizable BAR)
*   **Problem:** Legacy or entry-level GPUs (e.g., NVIDIA T1000 8GB, Turing architecture) do not support Resizable BAR (ReBAR) at the hardware level. The BAR1 size is locked at **256MB** (as verified by `lspci -v -s <GPU-ID> | grep "Memory at"` showing `[size=256M]`).
*   **Impact:** BAR1 is the PCIe aperture window the CPU uses to map and access the GPU's framebuffer (VRAM). When Resizable BAR is disabled/unsupported, the host CPU must access VRAM through a tiny 256MB window. High-throughput workloads (like loading 3GB+ LLM models) will trigger extreme, constant memory paging/swapping over PCIe.

### Proxmox MMIO Allocation (PCI Hole)
*   **Workaround:** For VMs with large PCI mappings, ensure the hypervisor allocates enough 64-bit MMIO space by adding the following line to the Proxmox VM configuration file (`/etc/pve/qemu-server/<VMID>.conf`):
    ```ini
    args: -global q35-pcihost.pci-hole64-size=1024G
    ```

---

## 2. Guest VM - NoVNC & SPICE Display Issues

### NVIDIA Guest Driver Installation Best Practices (Proxmox Wiki)
*   **Key Concept from Proxmox Wiki:** According to [Proxmox VE Official vGPU Wiki](https://pve.proxmox.com/wiki/NVIDIA_vGPU_on_Proxmox_VE#Guest_Configuration), the built-in NoVNC and SPICE consoles **cannot display the virtual display output provided by the vGPU** once the guest driver is initialized.
*   **Best Practice:**
    1.  **Always enable Remote Desktop (RDP)** (on Windows) or configure a remote desktop server (like LightDM + x11vnc, Parsec, or Moonlight on Linux) **BEFORE** installing the NVIDIA driver.
    2.  Always connect and perform the NVIDIA Guest driver installation **via RDP** (or another remote tool). Doing so over NoVNC will result in a disconnect/black screen midway through installation when the driver initializes, locking you out of the VM.

### Black Screen on NoVNC after Installing vGPU Driver
*   **Symptom:** The VM is accessible via Remote Desktop (RDP), but the Proxmox NoVNC/SPICE console remains black or unresponsive after the NVIDIA vGPU driver loads.
*   **Root Cause:** RDP virtualizes display sessions at the software level, hiding physical/virtual GPUs. Outside RDP (at the console level), Windows detects both the virtual VGA card (`Microsoft Basic Display Adapter`) and the `NVIDIA vGPU`. Windows automatically designates the NVIDIA vGPU as the primary display and disables or stops outputting to the virtual VGA. Since NoVNC monitors the virtual VGA framebuffer, it goes black.
*   **Resolution:**
    1.  **Configure Proxmox Hardware:**
        *   In VM -> Hardware -> **Display**, set it to **`Default`** or **`virtio`**.
        *   In VM -> Hardware -> **PCI Device (vGPU)**, **DO NOT check** the "Primary GPU" (`x-vga=1`) box. (Checking this disables the virtual display entirely).
    2.  **Force Primary Display Alignment:**
        Because RDP hides display configurations, you must force Windows to set the virtual display adapter as the primary output. Use the lightweight utility [MultiMonitorTool](https://www.nirsoft.net/utils/multimonitortool.html) to override the RDP lock.
        
        Create a batch file named `fix_novnc.bat` on the VM's desktop in the same directory as `MultiMonitorTool.exe`:
        ```cmd
        @echo off
        :: 1. Redirect current active RDP session back to physical Console (forces RDP disconnect)
        for /f "tokens=3-4" %%a in ('query session ^| findstr /i "active"') do (
            tscon %%a /dest:console
        )

        :: 2. Wait 5 seconds for Windows to reload the physical and virtual display adapters
        timeout /t 5

        :: 3. Change directory to script location
        cd /d "%~dp0"

        :: 4. Force set the virtual display (typically DISPLAY1) as the primary screen
        MultiMonitorTool.exe /SetPrimary \\.\DISPLAY1
        
        :: 5. Ensure both display channels are enabled in extended mode
        MultiMonitorTool.exe /TurnOn \\.\DISPLAY1 \\.\DISPLAY2
        ```
        Right-click `fix_novnc.bat` and select **"Run as administrator"**. The RDP session will disconnect. Wait 10 seconds, then open the Proxmox NoVNC console. The desktop will display properly.

### Screen Resolution Locked/Limited (Standard VGA vs. VirtIO-GPU)
*   **Problem:** The NoVNC console resolution is locked at 1280x800 or 1024x768 and cannot be adjusted.
*   **Root Cause:** Using Proxmox's Standard VGA display defaults to `Microsoft Basic Display Adapter` in Windows, which has extremely limited VESA resolution profiles.
*   **Resolution:**
    1.  Change Proxmox VM **Display** hardware to **`virtio`** (VirtIO-GPU).
    2.  Mount the `virtio-win.iso` in the VM's CD drive.
    3.  In Windows **Device Manager**, update the Display Adapter driver by pointing to the `viogpu\w10\amd64` folder on the VirtIO ISO.
    4.  The adapter will upgrade to **`Red Hat VirtIO GPU DOD controller`**, unlocking custom resolutions and allowing NoVNC auto-scaling.

---

## 3. Guest VM - High VRAM & Compute Application Issues

### VM Crashes (Video TDR Failure / GPU Lockup) when allocating >50% VRAM
*   **Symptom:** When a vGPU profile with larger VRAM (e.g., 6GB profile) is allocated, any compute application (e.g., Ollama/PyTorch) attempting to allocate more than 3GB+ VRAM causes the guest OS to crash (BSOD "Video TDR Failure"), freeze, or experience driver restarts.
*   **Root Cause & VRAM Overhead:**
    *   **Windows OS/DWM VRAM Reservation:** Windows WDDM driver reserves 20% - 30% of the allocated VRAM for OS/DWM (desktop display window manager) tasks. For instance, on a **6GB profile**, Windows reserves a significant chunk, leaving only about **3GB of VRAM** actually available for compute applications. 
    *   **BAR1 Mapping Overload:** Because the physical GPU lacks Resizable BAR (locked at 256MB BAR1), transferring large models (exceeding the remaining ~3GB) forces the driver to constantly map/unmap memory pages through the tiny 256MB PCIe window.
    *   **vGPU Manager Timeout:** In a vGPU virtualized environment, the hypervisor's `nvidia-vgpu-mgr` mediates all GPU page mappings. The sheer volume of mapping operations triggers watchdog/swapping timeouts, causing the host driver to drop the GPU state (Xid 31/43 Page Fault), crashing the guest.
*   **Ultimate Cure (PCIe Passthrough):**
    If multi-VM sharing is not mandatory, switch the VM from **vGPU** to **PCIe Passthrough** (Direct Path). Without the virtualization mediation layer (`nvidia-vgpu-mgr`), the native Windows driver (GART) handles 256MB BAR1 swapping much more gracefully, allowing stable allocation of all 8GB VRAM without crashing.

### Windows TDR Tweaks (Increasing Timeout Limits)
*   **Problem:** By default, Windows checks if the GPU is responsive. If a compute kernel takes longer than 2 seconds (common during heavy LLM memory paging/swapping over a 256MB BAR1), Windows resets the graphics driver, causing the application to crash or trigger a BSOD.
*   **Workaround:** You can increase the Timeout Detection and Recovery (TDR) limit in the Windows Registry to allow the GPU more time to complete operations without being killed by the OS.
*   **Registry Config:**
    Run the following commands in an administrator Command Prompt to increase the timeout limit to **60 seconds**:
    ```cmd
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDelay /t REG_DWORD /d 60 /f
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDdiDelay /t REG_DWORD /d 60 /f
    ```
    *Note: A system reboot is required for these registry changes to take effect.*

### Ollama Offloads 100% to CPU on Smaller Profiles (e.g., 3GB Profile)
*   **Symptom:** On a 3GB vGPU profile, Ollama runs extremely slow, and `ollama ps` shows `98%/2% CPU/GPU` or 100% CPU offload, despite VRAM showing only 365MB used.
*   **Root Cause:** 
    *   Windows WDDM driver reserves 20% - 30% of the VRAM for OS/DWM overhead (~900MB on a 3GB card).
    *   This leaves only ~2.1GB of physical VRAM. Since the target model (e.g., `qwen3.5:2b` at 2.5GB+) is larger than the available physical VRAM, Ollama's scheduler automatically offloads the computation to system memory/CPU to prevent Out-Of-Memory (OOM) crashes.

---

> [!NOTE]
> The scenarios and solutions described in this document are compiled from various community experiences. Depending on your specific motherboard, GPU generation, host OS, and guest Windows build, these workarounds may not guarantee a 100% success rate, but they are highly recommended steps worth experimenting with.

