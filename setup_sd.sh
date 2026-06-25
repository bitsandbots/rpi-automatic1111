#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

progress() { echo -e "${YELLOW}$1${NC}"; sleep 0.4; }
ok() { echo -e "${GREEN}$1${NC}"; }
fail() { echo -e "${RED}$1${NC}"; }

DOWNLOAD_MODELS=1

get_target_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
    echo "$SUDO_USER"
  else
    id -un
  fi
}

get_home_for_user() {
  local u="$1"
  local h=""
  h="$(getent passwd "$u" | cut -d: -f6 || true)"
  [ -d "$h" ] && echo "$h" || echo "${HOME:-/home/$u}"
}

TARGET_USER="$(get_target_user)"
USER_HOME="$(get_home_for_user "$TARGET_USER")"

WEBUI_DIR="$USER_HOME/stable-diffusion-webui"
VENV_DIR="$USER_HOME/stable-diffusion-env"

CLEANUP_ON_FAIL=1
trap 'rm -rf "$WEBUI_DIR" "$VENV_DIR" 2>/dev/null || true' ERR

progress "Detected architecture: $(uname -m)"

# ============================================================
# FIX 1: disable piwheels
# ============================================================
progress "Sanitizing pip configuration..."

sed -i '/piwheels/d' "$USER_HOME/.config/pip/pip.conf" 2>/dev/null || true
sed -i '/piwheels/d' "$USER_HOME/.pip/pip.conf" 2>/dev/null || true
sudo sed -i '/piwheels/d' /etc/pip.conf 2>/dev/null || true

progress "Updating system..."
sudo apt update && sudo apt upgrade -y

progress "Installing dependencies..."
sudo apt install -y \
  git wget curl ca-certificates \
  python3 python3-venv python3-pip python3-dev \
  python3-setuptools python3-pkg-resources \
  build-essential libgl1 libglib2.0-0 \
  zenity lxterminal

progress "Creating venv..."
rm -rf "$VENV_DIR"
sudo -u "$TARGET_USER" python3 -m venv "$VENV_DIR"

source "$VENV_DIR/bin/activate"

export PIP_CONFIG_FILE=/dev/null
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1

progress "Upgrading pip..."
python -m pip install -U "pip<24.1" "setuptools<70" wheel packaging

progress "Cloning WebUI..."
rm -rf "$WEBUI_DIR"
sudo -u "$TARGET_USER" git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$WEBUI_DIR"

cd "$WEBUI_DIR"
sudo -u "$TARGET_USER" git checkout 82a973c04367123ae98bd9abdf80d9eda9b910e2

progress "Installing PyTorch..."
python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

progress "Installing requirements..."
python -m pip install -r requirements.txt --index-url https://pypi.org/simple

# ============================================================
# FIX 2: correct pytorch_lightning
# ============================================================
python -m pip install pytorch-lightning==1.9.5 --index-url https://pypi.org/simple

# ============================================================
# FIX 3: install CLIP (missing on ARM)
# ============================================================
python -m pip install git+https://github.com/openai/CLIP.git --no-deps --index-url https://pypi.org/simple
progress "Patching launch_utils..."
sed -i 's#https://github.com/Stability-AI/stablediffusion.git#https://github.com/comp6062/Stability-AI-stablediffusion.git#g' modules/launch_utils.py
sed -i 's/run_pip(f"install {clip_package}", "clip")/run_pip(f"install --no-build-isolation --no-use-pep517 {clip_package}", "clip")/g' modules/launch_utils.py

download_if_missing() {
  [ -f "$2" ] || { mkdir -p "$(dirname "$2")"; wget -O "$2" "$1"; }
}

# ============================================================
# OPTIONAL MODEL DOWNLOADS
# ============================================================
if [ "$DOWNLOAD_MODELS" = "1" ]; then
  progress "Downloading models..."

  download_if_missing \
  "https://huggingface.co/cyberdelia/CyberRealistic/resolve/main/CyberRealistic_V7.0_FP16.safetensors" \
  "$WEBUI_DIR/models/Stable-diffusion/CyberRealistic_V7.0_FP16.safetensors"

  download_if_missing \
  "https://huggingface.co/SG161222/Realistic_Vision_V5.1_noVAE/resolve/main/Realistic_Vision_V5.1-inpainting.safetensors" \
  "$WEBUI_DIR/models/Stable-diffusion/Realistic_Vision_V5.1-inpainting.safetensors"
fi

deactivate || true

cat <<'EOF' > "$USER_HOME/run_sd.sh"
#!/bin/bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

WEBUI_DIR="$USER_HOME/stable-diffusion-webui"
VENV_DIR="$USER_HOME/stable-diffusion-env"

echo ""
echo "1) LAN mode (first run installs)"
echo "2) Offline mode"
echo "3) Uninstall"
echo "q) Quit"
echo ""

read -rp "Choice: " c

case "$c" in
  1)
    source "$VENV_DIR/bin/activate"
    cd "$WEBUI_DIR"
    IP=$(hostname -I | awk '{print $1}')
    echo "http://$IP:7860"
    python launch.py --skip-torch-cuda-test --no-half --listen
    ;;
  2)
    source "$VENV_DIR/bin/activate"
    cd "$WEBUI_DIR"
    python launch.py --skip-torch-cuda-test --no-half --listen --skip-install
    ;;
  3)
    rm -rf "$WEBUI_DIR"
    rm -rf "$VENV_DIR"
    rm -f "$USER_HOME/run_sd.sh"
    rm -f "$USER_HOME/.sd_gui_runner.sh"
    rm -f "$USER_HOME/.local/share/applications/sd-gui.desktop"
    rm -f "$USER_HOME/Desktop/StableDiffusionGUI.desktop"
    rm -f /tmp/sd_gui.pid
    echo "Cleanup complete."
    ;;
  q|Q)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "$USER_HOME/run_sd.sh"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/run_sd.sh"


# ============================================================
# GUI LAUNCHER
# ============================================================
APP_NAME="Stable Diffusion GUI"
LAUNCHER="$USER_HOME/.local/share/applications/sd-gui.desktop"
DESKTOP_SHORTCUT="$USER_HOME/Desktop/StableDiffusionGUI.desktop"

cat <<'EOF' > "$USER_HOME/.sd_gui_runner.sh"
#!/bin/bash

SCRIPT="$HOME/run_sd.sh"
PID_FILE="/tmp/sd_gui.pid"

run_mode() {
    MODE="$1"

    # Run in terminal and keep it open
    lxterminal --command="bash -c 'echo Running mode $MODE; printf \"%s\n\" \"$MODE\" | \"$SCRIPT\"; echo; echo Press ENTER to close...; read'" &
    echo $! > "$PID_FILE"

    zenity --notification \
        --text="Stable Diffusion is running (mode $MODE)"
}

stop_run() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        kill "$PID" 2>/dev/null || true
        rm -f "$PID_FILE"
        zenity --notification --text="Stable Diffusion stopped"
    else
        zenity --error --text="Not running"
    fi
}

CHOICE=$(zenity --list \
    --title="Stable Diffusion GUI" \
    --column="Action" \
    "LAN Mode (install if needed)" \
    "Offline Mode" \
    "Uninstall" \
    "Stop Running" \
    "Quit")

case "$CHOICE" in
    "LAN Mode (install if needed)")
        run_mode 1
        ;;
    "Offline Mode")
        run_mode 2
        ;;
    "Uninstall")
        run_mode 3
        ;;
    "Stop Running")
        stop_run
        ;;
    *)
        exit 0
        ;;
esac
EOF

chmod +x "$USER_HOME/.sd_gui_runner.sh"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/.sd_gui_runner.sh"

mkdir -p "$USER_HOME/.local/share/applications"
mkdir -p "$USER_HOME/Desktop"

cat > "$LAUNCHER" << EOF
[Desktop Entry]
Name=$APP_NAME
Comment=Launch Stable Diffusion GUI
Exec=$USER_HOME/.sd_gui_runner.sh
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Utility;
EOF

cp "$LAUNCHER" "$DESKTOP_SHORTCUT"
chmod +x "$DESKTOP_SHORTCUT"
chown "$TARGET_USER:$TARGET_USER" "$LAUNCHER" "$DESKTOP_SHORTCUT"

CLEANUP_ON_FAIL=0
ok "Setup complete."
ok "Run: ~/run_sd.sh"
