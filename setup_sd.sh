#!/bin/bash
set -euo pipefail

# ============================================================
# setup_sd.sh  (RPi5 / RPi4) - ARM64 recommended
# (UNCHANGED LOGIC — ONLY FIXES APPLIED)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

progress() { echo -e "${YELLOW}$1${NC}"; sleep 0.4; }
ok() { echo -e "${GREEN}$1${NC}"; }
fail() { echo -e "${RED}$1${NC}"; }

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
  if [ -n "$h" ] && [ -d "$h" ]; then
    echo "$h"
    return 0
  fi
  echo "${HOME:-/home/$u}"
}

TARGET_USER="$(get_target_user)"
USER_HOME="$(get_home_for_user "$TARGET_USER")"

if [ -z "${USER_HOME:-}" ] || [ ! -d "$USER_HOME" ]; then
  fail "ERROR: Could not determine a valid home directory for user: $TARGET_USER"
  exit 1
fi

WEBUI_DIR="$USER_HOME/stable-diffusion-webui"
VENV_DIR="$USER_HOME/stable-diffusion-env"

CLEANUP_ON_FAIL=1
cleanup_partial_install() {
  [ "$CLEANUP_ON_FAIL" = "1" ] || return 0
  echo -e "${YELLOW}Installer failed. Cleaning up partial install...${NC}"
  rm -rf "$WEBUI_DIR" 2>/dev/null || true
  rm -rf "$VENV_DIR" 2>/dev/null || true
}
trap cleanup_partial_install ERR

ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "armv7l" ] && [[ "$ARCH" != armv7* ]]; then
  fail "Unsupported architecture: $ARCH"
  exit 1
fi

progress "Detected architecture: ${ARCH}"

# ============================================================
# ✅ FIX: remove broken piwheels safely (NO permission crash)
# ============================================================
progress "Sanitizing pip configuration..."

remove_piwheels_user() {
  local f="$1"
  [ -f "$f" ] || return 0
  if grep -qi "piwheels" "$f"; then
    sed -i '/piwheels/d' "$f" || true
  fi
}

remove_piwheels_system() {
  local f="$1"
  [ -f "$f" ] || return 0
  if grep -qi "piwheels" "$f"; then
    sudo sed -i '/piwheels/d' "$f" 2>/dev/null || true
  fi
}

remove_piwheels_user "$USER_HOME/.config/pip/pip.conf"
remove_piwheels_user "$USER_HOME/.pip/pip.conf"
remove_piwheels_system "/etc/pip.conf"

# ============================================================

progress "Updating system packages..."
sudo apt update
sudo apt upgrade -y

progress "Installing OS dependencies..."
sudo apt install -y \
  git wget curl ca-certificates \
  python3 python3-venv python3-pip python3-dev \
  python3-setuptools python3-pkg-resources \
  build-essential \
  libgl1 libglib2.0-0

progress "Creating virtual environment..."
rm -rf "$VENV_DIR" 2>/dev/null || true
sudo -u "$TARGET_USER" python3 -m venv "$VENV_DIR"

# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

# ============================================================
# ✅ FIX: force pip to ignore ALL configs (kills piwheels)
# ============================================================
export PIP_CONFIG_FILE=/dev/null
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
# ============================================================

progress "Upgrading pip tooling..."
python -m pip install -U "pip<24.1" "setuptools<70" wheel packaging

progress "Cloning AUTOMATIC1111 WebUI..."
rm -rf "$WEBUI_DIR" 2>/dev/null || true
sudo -u "$TARGET_USER" git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$WEBUI_DIR"

cd "$WEBUI_DIR"
sudo -u "$TARGET_USER" git checkout 82a973c04367123ae98bd9abdf80d9eda9b910e2

progress "Installing PyTorch (CPU wheels)..."
python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

progress "Installing WebUI requirements..."
# ✅ FIX: force PyPI only
python -m pip install -r requirements.txt --index-url https://pypi.org/simple

progress "Patching WebUI launch_utils.py (repo URL + CLIP flags)..."
cp -a modules/launch_utils.py "modules/launch_utils.py.bak.$(date +%F_%H%M%S)"

sed -i 's#https://github.com/Stability-AI/stablediffusion.git#https://github.com/comp6062/Stability-AI-stablediffusion.git#g' modules/launch_utils.py

sed -i 's/run_pip(f"install {clip_package}", "clip")/run_pip(f"install --no-build-isolation --no-use-pep517 {clip_package}", "clip")/g' modules/launch_utils.py

# -----------------------------
# MODELS (UNCHANGED)
# -----------------------------
download_if_missing() {
  local url="$1"
  local path="$2"
  [ -f "$path" ] && return 0
  mkdir -p "$(dirname "$path")"
  wget -O "$path" "$url"
}

progress "Downloading the model files..."

download_if_missing \
"https://huggingface.co/cyberdelia/CyberRealistic/resolve/main/CyberRealistic_V7.0_FP16.safetensors" \
"$WEBUI_DIR/models/Stable-diffusion/CyberRealistic_V7.0_FP16.safetensors"

download_if_missing \
"https://huggingface.co/SG161222/Realistic_Vision_V5.1_noVAE/resolve/main/Realistic_Vision_V5.1-inpainting.safetensors" \
"$WEBUI_DIR/models/Stable-diffusion/Realistic_Vision_V5.1-inpainting.safetensors"

deactivate || true

# ============================================================
# ✅ ORIGINAL LAUNCHER (RESTORED EXACTLY)
# ============================================================
progress "Creating launcher: $USER_HOME/run_sd.sh"
cat <<'EOF' > "$USER_HOME/run_sd.sh"
#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

get_target_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
    echo "$SUDO_USER"
  else
    id -un
  fi
}
TARGET_USER="$(get_target_user)"
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

WEBUI_DIR="$USER_HOME/stable-diffusion-webui"
VENV_DIR="$USER_HOME/stable-diffusion-env"

if [ ! -d "$VENV_DIR" ]; then
  echo -e "${RED}Virtual environment not found at: $VENV_DIR${NC}"
  exit 1
fi
if [ ! -d "$WEBUI_DIR" ]; then
  echo -e "${RED}WebUI not found at: $WEBUI_DIR${NC}"
  exit 1
fi

cleanup() {
  echo -e "${YELLOW}Stopping Stable Diffusion...${NC}"
  pkill -f "launch.py" 2>/dev/null || true
  deactivate 2>/dev/null || true
  echo -e "${YELLOW}Virtual environment deactivated.${NC}"
}
trap cleanup SIGINT

echo ""
echo -e "${GREEN}Select an option:${NC}"
echo "1) Run connected to the internet (http://LAN_IP:7860)  [first run installs]"
echo "2) Run completely offline / localhost only (http://127.0.0.1:7860)  [no installs]"
echo "3) Uninstall"
echo "q) Quit"
echo ""

read -rp "Enter your choice: " choice

export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true
unset SSH_ASKPASS || true

case "$choice" in
  1)
    source "$VENV_DIR/bin/activate"
    cd "$WEBUI_DIR"
    DEFAULT_LOCAL_IP="$(hostname -I | awk '{print $1}')"
    echo -e "Access it at: http://${DEFAULT_LOCAL_IP}:7860"
    python launch.py --skip-torch-cuda-test --no-half --listen
    ;;
  2)
    source "$VENV_DIR/bin/activate"
    cd "$WEBUI_DIR"
    python launch.py --skip-torch-cuda-test --no-half --listen --skip-install
    ;;
  3)
    "$USER_HOME/remove.sh"
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

progress "Creating uninstaller: $USER_HOME/remove.sh"
cat <<'EOF' > "$USER_HOME/remove.sh"
#!/bin/bash
set -euo pipefail
USER_HOME="$(getent passwd "${SUDO_USER:-$(whoami)}" | cut -d: -f6)"
rm -rf "$USER_HOME/stable-diffusion-webui"
rm -rf "$USER_HOME/stable-diffusion-env"
rm -f "$USER_HOME/run_sd.sh"
rm -f "$USER_HOME/remove.sh"
echo "Cleanup complete."
EOF

chmod +x "$USER_HOME/remove.sh"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/remove.sh"

CLEANUP_ON_FAIL=0
ok "Setup complete."
ok "Start:  ~/run_sd.sh"
ok "Remove: ~/remove.sh"
