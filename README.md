# Stable Diffusion WebUI – Raspberry Pi 5+ (ARM)

![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi%205%2B%20%2F%20ARM-blue)
![CPU](https://img.shields.io/badge/acceleration-CPU--only-orange)
![ARM64](https://img.shields.io/badge/ARM64-aarch64-success)
![License](https://img.shields.io/badge/license-MIT-informational)

This repository provides a **fully automated setup** for running  
**AUTOMATIC1111 Stable Diffusion WebUI** (AI image generator), on Raspberry Pi 5 or newer ARM-based Raspberry Pi systems.

It supports **CPU-only inference**, is optimized for ARM environments, and includes
a guided installer, integrated GUI launcher, bundled banner artwork, unified launcher, and clean uninstall process.

> **Hardware Requirement**
>
> This installer is designed and supported for **Raspberry Pi 5 or newer**. Earlier Raspberry Pi models are not supported by this project.

---

## Index

1. [Remote install](#1-remote-install)
2. [Interactive installer menu](#2-interactive-installer-menu)
3. [Run after install](#3-run-after-install)
4. [First run note](#4-first-run-note)
5. [GUI launcher](#5-gui-launcher)
6. [Model downloads](#6-model-downloads)
7. [Uninstall](#7-uninstall)
8. [Included files](#8-included-files)
9. [Notes](#9-notes)

## 1. Remote install

Install directly from GitHub with `curl`:

```bash
curl -sSL https://raw.githubusercontent.com/comp6062/rpi-automatic1111/main/setup_sd.sh | bash
```

or with `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/comp6062/rpi-automatic1111/main/setup_sd.sh | bash
```

This installer is self-contained for remote bash installs. The GUI banner is embedded inside `setup_sd.sh`, so the remote install does not need a separate banner download.

## 2. Interactive installer menu

The installer opens a menu before installing:

```text
Stable Diffusion Raspberry Pi Installer
=======================================
Use the menu below to choose install options.

  1) Download included models:  OFF
  2) Install GUI launcher:      ON
  3) Create desktop shortcut:   ON
  4) Create menu launcher:      ON
  5) Install files location:    /home/admin

  6) Start install
  q) Quit
```

Options can be toggled before install starts.

Default install location is your home folder:

```bash
~/
```

With the default location, the installer creates:

```bash
~/stable-diffusion-webui
~/stable-diffusion-env
~/run_sd.sh
```

If you choose a different install location, those files are created inside that folder instead.

## 3. Run after install

Use:

```bash
~/run_sd.sh
```

If you installed to a custom folder, run:

```bash
/path/to/install/run_sd.sh
```

The run menu includes:

1. LAN mode - first run installs needed WebUI files and allows LAN access
2. Offline mode - starts without dependency checks or installs
3. Stop running - stops the running WebUI process
4. Uninstall - removes WebUI, venv, launcher files, and shortcuts

## 4. First run note

The first time you run Stable Diffusion after install, run LAN mode once while online. This allows Automatic1111 to install needed runtime files. After the first successful LAN run, offline mode can be used without checking or installing dependencies.

## 5. GUI launcher

If GUI launcher is enabled, the installer creates:

```bash
.sd_gui_app.py
.sd_gui_runner.sh
.sd_gui_banner.png
~/.local/share/icons/sd_icon.png
~/.local/share/icons/hicolor/256x256/apps/sd_icon.png
```

These are placed in the selected install location.

If desktop shortcut is enabled, the installer creates:

```bash
~/Desktop/StableDiffusionGUI.desktop
```

The desktop shortcut uses the installed icon name:

```bash
sd_icon
```

If menu launcher is enabled, the installer creates:

```bash
~/.local/share/applications/sd-gui.desktop
```

The menu launcher uses the installed icon name:

```bash
sd_icon
```

The GUI includes:

- LAN Mode
- Offline Mode
- Stop Running
- Uninstall
- Open Web-UI

## 6. Model downloads

Model downloads are optional in the installer.

If enabled, the installer downloads:

- `CyberRealistic_V7.0_FP16.safetensors`
- `Realistic_Vision_V5.1-inpainting.safetensors`

If disabled, no models are downloaded during setup. You can add models later in:

```bash
stable-diffusion-webui/models/Stable-diffusion/
```

## 7. Uninstall

Run:

```bash
~/run_sd.sh
```

Then choose:

```bash
4) Uninstall
```

If installed to a custom folder, run that folder's `run_sd.sh` and choose uninstall.

The uninstaller removes:

- `stable-diffusion-webui`
- `stable-diffusion-env`
- `run_sd.sh`
- GUI helper files
- desktop shortcut
- menu launcher
- `/tmp/sd_gui.pid`

## 8. Included files

- `setup_sd.sh` - interactive self-contained remote-bash installer
- `sd_gui_banner.png` - GUI banner artwork for local reference/local extracted installs
- `sd_icon.png` - launcher icon used by the desktop shortcut and menu launcher
- `README.md` - this documentation

Remote install only requires `setup_sd.sh`.

## 9. Notes

- Designed for **Raspberry Pi 5 or newer** running Raspberry Pi OS (64-bit).
- Earlier Raspberry Pi models are not supported.


- This installer is intended for Raspberry Pi OS 64-bit.
- CPU-only PyTorch is installed.
- The WebUI is pinned to the known working Automatic1111 commit used by this setup.
- Offline mode should be used only after LAN mode has completed successfully once.
