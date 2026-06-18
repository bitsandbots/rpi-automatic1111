# Stable Diffusion WebUI for Raspberry Pi (ARM)

![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi%20%2F%20ARM-blue)
![CPU](https://img.shields.io/badge/acceleration-CPU--only-orange)
![License](https://img.shields.io/badge/license-MIT-informational)

A fully automated installer for running AUTOMATIC1111 Stable Diffusion WebUI on Raspberry Pi and other ARM-based Linux systems using CPU-only PyTorch.

---

# Features

- AUTOMATIC1111 Stable Diffusion WebUI
- Python virtual environment
- CPU-only PyTorch
- ARM compatibility fixes
- GUI launcher
- Desktop shortcut
- Offline mode support
- One-command uninstall

---

# Requirements

## Minimum

- Raspberry Pi 4 / Raspberry Pi 5
- 4 GB RAM
- Internet connection during installation

## Recommended

- Raspberry Pi OS 64-bit
- 8 GB RAM or more
- Desktop environment for GUI launcher support

---

# What the Installer Does

The setup script performs the following actions:

1. Detects system architecture (`uname -m`)
2. Removes piwheels entries from pip configuration
3. Updates system packages
4. Installs required dependencies
5. Creates a Python virtual environment
6. Clones AUTOMATIC1111 Stable Diffusion WebUI
7. Checks out the pinned commit:

```text
82a973c04367123ae98bd9abdf80d9eda9b910e2
```

8. Installs CPU-only PyTorch
9. Installs WebUI requirements
10. Installs:

```text
pytorch-lightning==1.9.5
```

11. Installs OpenAI CLIP
12. Applies ARM-specific launch utility patches
13. Optionally downloads example models
14. Creates launchers and uninstall scripts

---

# Installed Packages

```text
git
wget
curl
ca-certificates
python3
python3-venv
python3-pip
python3-dev
python3-setuptools
python3-pkg-resources
build-essential
libgl1
libglib2.0-0
zenity
lxterminal
```

---

# ARM Compatibility Patches

The installer patches:

```text
modules/launch_utils.py
```

Changes:

- Replaces the Stability-AI repository URL with:
  - https://github.com/comp6062/Stability-AI-stablediffusion
- Modifies CLIP installation behavior for ARM systems
- Installs OpenAI CLIP manually before launch

---

# Model Downloads

The script contains:

```bash
DOWNLOAD_MODELS=1
```

When enabled, the installer downloads:

- CyberRealistic_V7.0_FP16.safetensors
- Realistic_Vision_V5.1-inpainting.safetensors

Existing files are not overwritten.

## Disable Downloads

Edit the setup script before running:

```bash
DOWNLOAD_MODELS=0
```

Then execute the modified installer.

## Manual Models

Place models in:

```text
~/stable-diffusion-webui/models/Stable-diffusion/
```

Supported formats:

```text
.ckpt
.safetensors
```

---

# Installed Files

The installer creates:

```text
~/stable-diffusion-webui
~/stable-diffusion-env
~/run_sd.sh
~/remove.sh
~/.sd_gui_runner.sh
~/.local/share/applications/sd-gui.desktop
~/Desktop/StableDiffusionGUI.desktop
/tmp/sd_gui.pid
```

---

# Running Stable Diffusion

Start:

```bash
~/run_sd.sh
```

Menu:

```text
1) LAN mode (first run installs)
2) Offline mode
3) Uninstall
q) Quit
```

---

## LAN Mode

Runs:

```bash
python launch.py --skip-torch-cuda-test --no-half --listen
```

Displays:

```text
http://<pi-ip>:7860
```

Important:

The first launch should be performed while connected to the internet. AUTOMATIC1111 may download additional repositories and files required for operation.

---

## Offline Mode

Runs:

```bash
python launch.py --skip-torch-cuda-test --no-half --listen --skip-install
```

Offline mode:

- Uses existing models
- Skips package installation
- Runs on port 7860
- Requires a successful first online launch

Access locally:

```text
http://127.0.0.1:7860
```

Access from another device:

```text
http://<pi-ip>:7860
```

---

# GUI Launcher

Installed files:

```text
~/.sd_gui_runner.sh
~/.local/share/applications/sd-gui.desktop
~/Desktop/StableDiffusionGUI.desktop
```

Menu options:

- LAN Mode (install if needed)
- Offline Mode
- Uninstall
- Stop Running
- Quit

The GUI uses:

```text
zenity
lxterminal
```

Additional behavior:

- Creates `/tmp/sd_gui.pid`
- Displays desktop notifications
- Supports stopping the running launcher process

---

# Uninstall

Run:

```bash
~/remove.sh
```

Or choose:

```text
Uninstall
```

from either launcher.

The uninstall process removes:

```text
~/stable-diffusion-webui
~/stable-diffusion-env
~/run_sd.sh
~/.sd_gui_runner.sh
~/.local/share/applications/sd-gui.desktop
~/Desktop/StableDiffusionGUI.desktop
/tmp/sd_gui.pid
~/remove.sh
```

---

# Architecture Notes

The script does not contain separate installation branches for ARM64 and ARM32.

It simply reports:

```bash
uname -m
```

and proceeds using the same installation workflow.

ARM64 (64-bit Raspberry Pi OS) is strongly recommended.

---

# Known Limitations

- CPU-only inference
- No CUDA support
- No ROCm support
- ARM64 recommended
- First launch requires internet access
- Large models may exceed available RAM
- Image generation on Raspberry Pi hardware can be slow

---

# Credits

- AUTOMATIC1111 Stable Diffusion WebUI
- PyTorch
- OpenAI CLIP
- Raspberry Pi Community
