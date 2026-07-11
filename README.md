# Stable Diffusion WebUI – Raspberry Pi 5+ (ARM)

![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi%205%2B%20%2F%20ARM-blue)
![CPU](https://img.shields.io/badge/acceleration-CPU--only-orange)
![ARM64](https://img.shields.io/badge/ARM64-aarch64-success)
![License](https://img.shields.io/badge/license-MIT-informational)

A streamlined, fully automated installer for **AUTOMATIC1111 Stable Diffusion WebUI** on **Raspberry Pi 5 and newer ARM-based Raspberry Pi systems**.

This project is designed for CPU-only inference and provides an interactive installation experience with an optional graphical launcher, desktop integration, menu integration, optional model downloads, and a clean uninstall process.

> **Hardware Requirement**
>
> This installer is designed and supported for **Raspberry Pi 5 or newer**. Earlier Raspberry Pi models are not supported.

---

## Index

1. [Remote install](#1-remote-install)
2. [Interactive installer](#2-interactive-installer)
3. [Running Stable Diffusion](#3-running-stable-diffusion)
4. [First launch](#4-first-launch)
5. [GUI launcher](#5-gui-launcher)
6. [Model downloads](#6-model-downloads)
7. [Uninstall](#7-uninstall)
8. [Included files](#8-included-files)
9. [Notes](#9-notes)

## 1. Remote install

Run the installer directly from GitHub using either command below.

Using **curl**:

```bash
curl -sSL https://raw.githubusercontent.com/comp6062/rpi-automatic1111/main/setup_sd.sh | bash
```

Using **wget**:

```bash
wget -qO- https://raw.githubusercontent.com/comp6062/rpi-automatic1111/main/setup_sd.sh | bash
```

The installer is completely self-contained. The GUI banner is embedded inside `setup_sd.sh`, so no additional banner download is required during remote installation.

## 2. Interactive installer

Before installation begins, an interactive configuration menu allows you to customize the installation.

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

By default, the installer uses your home directory:

```bash
~/
```

This creates:

```bash
~/stable-diffusion-webui
~/stable-diffusion-env
~/run_sd.sh
```

If a custom installation directory is selected, these files are created in that location instead.

## 3. Running Stable Diffusion

Launch the application with:

```bash
~/run_sd.sh
```

If installed elsewhere:

```bash
/path/to/install/run_sd.sh
```

The launcher provides:

1. LAN Mode — Starts the WebUI with network access. On first launch it downloads and installs any required runtime components.
2. Offline Mode — Starts the WebUI without dependency checks.
3. Stop Running — Stops the currently running WebUI instance.
4. Uninstall — Removes the installed application, virtual environment, launcher, and shortcuts.

## 4. First launch

The first launch should always be performed using **LAN Mode** while connected to the internet. This allows AUTOMATIC1111 to complete its initial setup and install any required runtime components.

After the initial setup has completed successfully, **Offline Mode** can be used without performing additional dependency checks.

## 5. GUI launcher

When enabled, the installer creates:

```bash
.sd_gui_app.py
.sd_gui_runner.sh
.sd_gui_banner.png
~/.local/share/icons/sd_icon.png
~/.local/share/icons/hicolor/256x256/apps/sd_icon.png
```

Desktop shortcut (optional):

```bash
~/Desktop/StableDiffusionGUI.desktop
```

Menu launcher (optional):

```bash
~/.local/share/applications/sd-gui.desktop
```

Both launchers use the installed icon:

```text
sd_icon
```

The GUI provides quick access to:

- LAN Mode
- Offline Mode
- Stop Running
- Uninstall
- Open WebUI

## 6. Model downloads

Downloading models during installation is optional.

When enabled, the installer downloads:

- `CyberRealistic_V7.0_FP16.safetensors`
- `Realistic_Vision_V5.1-inpainting.safetensors`

If model downloads are disabled, models can be added later to:

```bash
stable-diffusion-webui/models/Stable-diffusion/
```

## 7. Uninstall

Run:

```bash
~/run_sd.sh
```

Select:

```text
4) Uninstall
```

If installed in a custom location, run that installation's `run_sd.sh` and choose the uninstall option.

The uninstaller removes:

- `stable-diffusion-webui`
- `stable-diffusion-env`
- `run_sd.sh`
- GUI helper files
- Desktop shortcut
- Menu launcher
- `/tmp/sd_gui.pid`

## 8. Included files

- `setup_sd.sh` — Self-contained interactive installer
- `sd_gui_banner.png` — GUI banner artwork for local installs
- `sd_icon.png` — Desktop and menu launcher icon
- `README.md` — Project documentation

Remote installations require only `setup_sd.sh`.

## 9. Notes

- Designed for **Raspberry Pi 5 or newer**.
- Intended for **Raspberry Pi OS (64-bit)**.
- CPU-only PyTorch is installed.
- The installer uses the known working AUTOMATIC1111 commit validated for this project.
- Run LAN Mode once before using Offline Mode.
