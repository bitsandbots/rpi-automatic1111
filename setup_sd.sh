#!/bin/bash
set -euo pipefail

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
progress "Detected architecture: ${ARCH}"

progress "Updating system packages..."
sudo apt update
sudo apt upgrade -y

progress "Fixing CA certificates..."
sudo apt install --reinstall -y ca-certificates
sudo update-ca-certificates

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

source "$VENV_DIR/bin/activate"

# 🔥 CRITICAL FIXES
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_CACHE_DIR=1

progress "Upgrading pip tooling..."
python -m pip install -U "pip<24.1" "setuptools<70" wheel packaging \
  --index-url https://pypi.org/simple \
  --trusted-host pypi.org \
  --trusted-host files.pythonhosted.org

progress "Cloning WebUI..."
rm -rf "$WEBUI_DIR" 2>/dev/null || true
sudo -u "$TARGET_USER" git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$WEBUI_DIR"

cd "$WEBUI_DIR"
sudo -u "$TARGET_USER" git checkout 82a973c04367123ae98bd9abdf80d9eda9b910e2

progress "Installing PyTorch..."
python -m pip install torch torchvision torchaudio \
  --index-url https://download.pytorch.org/whl/cpu \
  --trusted-host download.pytorch.org

# 🔥 THIS IS THE FIX FOR YOUR FAILURE
progress "Installing WebUI requirements (forcing PyPI, no piwheels)..."
python -m pip install -r requirements.txt \
  --index-url https://pypi.org/simple \
  --trusted-host pypi.org \
  --trusted-host files.pythonhosted.org

progress "Patching launch_utils.py..."
if [ -f "modules/launch_utils.py" ]; then
  sed -i 's#https://github.com/Stability-AI/stablediffusion.git#https://github.com/comp6062/Stability-AI-stablediffusion.git#g' modules/launch_utils.py

  sed -i 's/run_pip(f"install {clip_package}", "clip")/run_pip(f"install --no-build-isolation --no-use-pep517 {clip_package}", "clip")/g' modules/launch_utils.py
else
  fail "launch_utils.py not found"
  exit 1
fi

deactivate || true

progress "Creating launcher..."
cat <<'EOF' > "$USER_HOME/run_sd.sh"
#!/bin/bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

WEBUI_DIR="$USER_HOME/stable-diffusion-webui"
VENV_DIR="$USER_HOME/stable-diffusion-env"

export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
export GIT_TERMINAL_PROMPT=0

source "$VENV_DIR/bin/activate"
cd "$WEBUI_DIR"

IP=$(hostname -I | awk '{print $1}')
echo "Access: http://$IP:7860"

python launch.py --skip-torch-cuda-test --no-half --listen
EOF

chmod +x "$USER_HOME/run_sd.sh"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/run_sd.sh"

progress "Creating remover..."
cat <<'EOF' > "$USER_HOME/remove.sh"
#!/bin/bash
USER_HOME="$(getent passwd "${SUDO_USER:-$(whoami)}" | cut -d: -f6)"
rm -rf "$USER_HOME/stable-diffusion-webui"
rm -rf "$USER_HOME/stable-diffusion-env"
rm -f "$USER_HOME/run_sd.sh"
rm -f "$USER_HOME/remove.sh"
echo "Removed."
EOF

chmod +x "$USER_HOME/remove.sh"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/remove.sh"

CLEANUP_ON_FAIL=0
ok "Setup complete."
ok "Run: ~/run_sd.sh"
