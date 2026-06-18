# Stable Diffusion WebUI – Raspberry Pi (ARM)

![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi%20%2F%20ARM-blue)
![CPU](https://img.shields.io/badge/acceleration-CPU--only-orange)
![ARM64](https://img.shields.io/badge/ARM64-aarch64-success)
![ARM32](https://img.shields.io/badge/ARM32-armv7l-yellow)
![License](https://img.shields.io/badge/license-MIT-informational)

This repository provides a **fully automated setup** for running  
**AUTOMATIC1111 Stable Diffusion WebUI** (AI image generator), on Raspberry Pi and other ARM-based Linux systems.

It supports **CPU-only inference**, is optimized for ARM environments, and includes
a guided installer, integrated GUI launcher, unified launcher, and clean uninstall process.

---

## Table of Contents

- [Overview](#overview)
- [Supported Architectures](#supported-architectures)
- [ARM64 aarch64 recommended](#arm64-aarch64-recommended)
- [ARM32 armv7l best-effort](#arm32-armv7l-best-effort)
- [Architecture Detection & Install Logic](#architecture-detection--install-logic)
- [System Requirements](#system-requirements)
- [Installation](#installation)
- [Model Download Control (Setup Script)](#model-download-control-setup-script)
- [Running Stable Diffusion](#running-stable-diffusion)
- [GUI Launcher](#gui-launcher)
- [Offline Mode](#offline-mode)
- [Uninstalling](#uninstalling)
- [Known Limitations](#known-limitations)
- [Credits](#credits)
- [Recommendation Summary](#recommendation-summary)

---

## Overview

This setup installs and configures:

- AUTOMATIC1111 Stable Diffusion WebUI
- Python virtual environment
- CPU-only PyTorch (no CUDA / no ROCm)
- Required Python packages and ARM-related fixes
- Unified launcher (`~/run_sd.sh`)
- Integrated GUI launcher (`~/.sd_gui_runner.sh`)
- Desktop shortcut and application menu entry
- Clean uninstall script (`~/remove.sh`)

Designed for **Raspberry Pi OS**, **Debian**, and other ARM Linux distributions.

---

## Supported Architectures

The installer prints your detected CPU architecture during setup and installs
CPU-only PyTorch from the official PyTorch CPU wheel index.

---

### ARM64 aarch64 recommended

This is the **preferred and most reliable configuration**.

**Details:**
- Uses **official CPU-only PyTorch wheels**
- Installed from the official PyTorch CPU index
- Fully compatible with modern Python versions

**Why ARM64 is recommended:**
- Faster installation
- Fewer dependency issues
- Better performance
- Works best on Raspberry Pi 4 / 5 (64-bit OS)

---

### ARM32 armv7l best-effort

ARM32 (32-bit Raspberry Pi OS) support is **best-effort only**.

**How it works:**
- The setup uses the same CPU-only PyTorch install path
- No separate ARM32 wheel fallback is included
- No source builds are attempted by the setup script

**Limitations:**
- ARM32 may not have compatible PyTorch wheels available
- Significantly slower than ARM64
- Higher memory pressure
- More likely to fail during Python package installation

**If installation fails on ARM32:**
- Switch to a **64-bit Raspberry Pi OS**
- Re-run the setup script on the 64-bit OS

---

## Architecture Detection & Install Logic

This setup script displays the detected architecture using:

```bash
uname -m
```

The current setup does **not** use separate install branches for ARM64 and ARM32.
It uses the official PyTorch CPU wheel index and applies the same install flow.

### Installation Behavior

- Removes piwheels references from pip configuration
- Updates and upgrades the system packages
- Installs required dependencies
- Creates a clean Python virtual environment
- Clones AUTOMATIC1111 Stable Diffusion WebUI
- Checks out a pinned WebUI commit
- Installs CPU-only PyTorch
- Installs WebUI requirements
- Installs `pytorch-lightning==1.9.5`
- Installs OpenAI CLIP
- Patches `modules/launch_utils.py` for ARM compatibility
- Optionally downloads default models
- Creates the CLI launcher, GUI launcher, desktop shortcut, menu entry, and uninstall script

This keeps the setup consistent and repeatable.

---

## System Requirements

### Minimum
- Raspberry Pi 4 / 5 or other ARM SBC
- 4 GB RAM (8 GB recommended)
- Internet connection (for install)

### Strongly Recommended
- **64-bit Raspberry Pi OS**
- Desktop environment if you want to use the GUI launcher

### Required Packages Installed By Setup
- python3
- python3-venv
- python3-pip
- python3-dev
- git
- curl
- wget
- build-essential
- libgl1
- libglib2.0-0
- zenity
- lxterminal

---

## Installation

Install everything with **one command**:

```bash
curl -sSL https://raw.githubusercontent.com/comp6062/rpi-automatic1111/main/setup_sd.sh | bash
```

Or using wget:

```bash
wget -qO- https://raw.githubusercontent.com/comp6062/rpi-automatic1111/main/setup_sd.sh | bash
```

GUI support is installed automatically during setup. No separate GUI installation is required.

### The installer will

- Install system dependencies
- Remove piwheels entries from pip configuration
- Create a Python virtual environment
- Clone AUTOMATIC1111 Stable Diffusion WebUI
- Check out the pinned WebUI version used by this installer
- Install CPU-only PyTorch
- Install Python requirements
- Install ARM-related Python fixes
- Patch WebUI launch utilities
- Download default models when `DOWNLOAD_MODELS=1`
- Create `~/run_sd.sh` and `~/remove.sh`
- Install the Stable Diffusion GUI launcher
- Create a desktop shortcut and application menu entry

---

# Model Download Control (Setup Script)

## Default Model Download Behavior

By default, the setup script **automatically downloads two example Stable Diffusion models** during installation.  
This allows the WebUI to be used immediately after setup completes.

The default downloaded models are:

- CyberRealistic V7.0 FP16
- Realistic Vision V5.1 Inpainting

---

## Enable Model Downloads (Default)

To enable model downloads, set:

### Enabled (Download Models During Setup)

```bash
DOWNLOAD_MODELS=1
```

When enabled:
- Missing models are downloaded automatically
- Existing models are never overwritten
- Setup remains non-interactive

---

## Disable Model Downloads During Setup

If you prefer to **skip downloading models during installation** (for example, for offline systems or when supplying your own models), you can disable this behavior.

### Disabled (No Model Downloads)

```bash
DOWNLOAD_MODELS=0
```

When disabled:
- No models are downloaded during setup
- Installation still completes normally
- The WebUI can be launched after setup
- Models can be added later manually

---

## Adding Models Manually (Optional)

If model downloads are disabled, place your `.ckpt` or `.safetensors` files in:

```bash
~/stable-diffusion-webui/models/Stable-diffusion/
```

Restart the WebUI after adding new models.

---

## Running Stable Diffusion

Launch the unified launcher:

```bash
~/run_sd.sh
```

Then choose:

```text
1) LAN mode (first run installs)
2) Offline mode
3) Uninstall
q) Quit
```

### LAN Mode

LAN mode starts WebUI with:

```bash
--skip-torch-cuda-test --no-half --listen
```

The launcher prints the Raspberry Pi LAN URL, usually:

```text
http://<pi-ip-address>:7860
```

Use this mode for the first run so any remaining WebUI startup dependencies can finish installing.

---

## GUI Launcher

The setup installs an integrated GUI launcher automatically.

Installed GUI files:

- `~/.sd_gui_runner.sh`
- `~/.local/share/applications/sd-gui.desktop`
- `~/Desktop/StableDiffusionGUI.desktop`

The GUI launcher provides:

- LAN Mode (install if needed)
- Offline Mode
- Uninstall
- Stop Running
- Quit

The GUI uses `zenity` for the menu and `lxterminal` to run the selected mode in a terminal window.

---

## Offline Mode

Offline mode runs Stable Diffusion using already installed files and models.

Offline mode starts WebUI with:

```bash
--skip-torch-cuda-test --no-half --listen --skip-install
```

Offline mode:

- Uses already downloaded models
- Skips package installation and updates
- Can run without internet after the first successful setup and first launch
- Runs on port `7860`

Open WebUI from the Pi itself with:

```text
http://127.0.0.1:7860
```

Or from another device on the same LAN with:

```text
http://<pi-ip-address>:7860
```

---

## Uninstalling

To completely remove everything:

```bash
~/remove.sh
```

You can also select **Uninstall** from `~/run_sd.sh` or from the GUI launcher.

The uninstall process removes:

- Stable Diffusion WebUI
- Python virtual environment
- `~/run_sd.sh`
- GUI launcher script
- Desktop shortcut
- Application menu entry
- Temporary GUI PID file
- `~/remove.sh`

---

## Known Limitations

- CPU-only inference (no GPU acceleration)
- ARM64 is strongly recommended
- ARM32 is best-effort only
- Large models may exceed available RAM
- First launch should be run with internet access
- First generation can take several minutes on Raspberry Pi hardware
- GUI launcher requires a desktop environment with `zenity` and `lxterminal`

---

## Credits

- AUTOMATIC1111 – Stable Diffusion WebUI
- PyTorch Team – CPU wheel support
- OpenAI – CLIP
- Raspberry Pi community

---

## Recommendation Summary

| Architecture | Status |
|-------------|--------|
| ARM64 (aarch64) | Recommended |
| ARM32 (armv7l) | Best effort only |

If installation fails on ARM32, switch to a **64-bit OS**.  
That is the intended and supported upgrade path.
