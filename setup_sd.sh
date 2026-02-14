#!/bin/bash
set -euo pipefail

# ============================================================
# setup_sd.sh  (RPi5 / RPi4) - ARM64 recommended
#
# Requirements you stated:
# - Option 1 (LAN) MUST be allowed to install on first run
# - Fix CLIP install failing with pkg_resources by patching launch_utils.py
#   to use: --no-build-isolation --no-use-pep517
# - Avoid GitHub username/password prompts
# - Suppress pip version-check notices (they can corrupt prompts)
# - Use your fork for the SD repo:
#     https://github.com/comp6062/Stability-AI-stablediffusion.git
# - Generate updated ~/run_sd.sh and ~/remove.sh
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

# Clean fail (so broken installs don't linger)
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
  fail "Supported: aarch64 (recommended) and armv7l/armv7* (best effort)."
  exit 1
fi

progress "Detected architecture: ${ARCH}"

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

# Create venv fresh
progress "Creating virtual environment..."
rm -rf "$VENV_DIR" 2>/dev/null || true
sudo -u "$TARGET_USER" python3 -m venv "$VENV_DIR"

# Activate venv
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

progress "Upgrading pip tooling (pinned to avoid pkg_resources issues)..."
python -m pip install -U "pip<24.1" "setuptools<70" wheel packaging

# Clone webui and pin to known working commit (from your logs)
progress "Cloning AUTOMATIC1111 WebUI..."
rm -rf "$WEBUI_DIR" 2>/dev/null || true
sudo -u "$TARGET_USER" git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$WEBUI_DIR"

cd "$WEBUI_DIR"
sudo -u "$TARGET_USER" git checkout 82a973c04367123ae98bd9abdf80d9eda9b910e2

progress "Installing PyTorch (CPU wheels)..."
python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

progress "Installing WebUI requirements..."
python -m pip install -r requirements.txt

# Patch launch_utils.py for:
# 1) SD repo URL -> your fork
# 2) CLIP install flags to avoid build isolation/pkg_resources failures
progress "Patching WebUI launch_utils.py (repo URL + CLIP flags)..."
if [ -f "modules/launch_utils.py" ]; then
  cp -a modules/launch_utils.py "modules/launch_utils.py.bak.$(date +%F_%H%M%S)"

  # SD repo redirect (if present)
  sed -i 's#https://github.com/Stability-AI/stablediffusion.git#https://github.com/comp6062/Stability-AI-stablediffusion.git#g' modules/launch_utils.py

  # Patch CLIP install call (if present)
  if grep -n 'run_pip(f"install {clip_package}", "clip")' modules/launch_utils.py >/dev/null 2>&1; then
    sed -i 's/run_pip(f"install {clip_package}", "clip")/run_pip(f"install --no-build-isolation --no-use-pep517 {clip_package}", "clip")/g' modules/launch_utils.py
  fi
else
  fail "ERROR: modules/launch_utils.py not found — cannot apply required patches."
  exit 1
fi

deactivate || true

# Create run_sd.sh (Option 1 = installs allowed)
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

# Environment hardening:
# - Prevent pip version-check notices (they can corrupt interactive prompts)
# - Prevent git from asking for username/password (public clones should not need it)
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true
unset SSH_ASKPASS || true

case "$choice" in
  1)
    echo -e "${GREEN}Running with internet connection (LAN access)...${NC}"

    # Quick DNS sanity checks (clear message instead of weird failures)
    if ! getent hosts github.com >/dev/null 2>&1; then
      echo -e "${RED}DNS error: cannot resolve github.com. Fix DNS/network, then try again.${NC}"
      exit 1
    fi
    if ! getent hosts pypi.org >/dev/null 2>&1; then
      echo -e "${RED}DNS error: cannot resolve pypi.org. Fix DNS/network, then try again.${NC}"
      exit 1
    fi

    source "$VENV_DIR/bin/activate"
    cd "$WEBUI_DIR"

    # Ensure this repo never uses credential helpers
    git config --local credential.helper "" >/dev/null 2>&1 || true

    DEFAULT_LOCAL_IP="$(hostname -I | awk '{print $1}')"
    echo -e "Access it at: http://${DEFAULT_LOCAL_IP}:7860"

    # IMPORTANT: Do NOT use --skip-install here. First run must install resources.
    python launch.py --skip-torch-cuda-test --no-half --listen
    ;;

  2)
    echo -e "${GREEN}Running completely offline (localhost only)...${NC}"
    source "$VENV_DIR/bin/activate"
    cd "$WEBUI_DIR"

    git config --local credential.helper "" >/dev/null 2>&1 || true

    echo -e "Access it at: http://127.0.0.1:7860"
    python launch.py --skip-torch-cuda-test --no-half --listen --skip-install
    ;;

  3)
    echo -e "${RED}Uninstalling...${NC}"
    "$USER_HOME/remove.sh"
    ;;

  q|Q)
    echo -e "${YELLOW}Quitting.${NC}"
    exit 0
    ;;

  *)
    echo -e "${RED}Invalid option.${NC}"
    exit 1
    ;;
esac
EOF
chmod +x "$USER_HOME/run_sd.sh"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/run_sd.sh"

# Create remove.sh
progress "Creating uninstaller: $USER_HOME/remove.sh"
cat <<'EOF' > "$USER_HOME/remove.sh"
#!/bin/bash
set -euo pipefail

get_target_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
    echo "$SUDO_USER"
  else
    id -un
  fi
}
TARGET_USER="$(get_target_user)"
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

rm -f  "$USER_HOME/run_sd.sh" 2>/dev/null || true
rm -f  "$USER_HOME/remove.sh" 2>/dev/null || true
rm -rf "$USER_HOME/stable-diffusion-webui" 2>/dev/null || true
rm -rf "$USER_HOME/stable-diffusion-env" 2>/dev/null || true

echo "Cleanup complete."
EOF
chmod +x "$USER_HOME/remove.sh"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/remove.sh"

CLEANUP_ON_FAIL=0
ok "Setup complete."
ok "Start:  ~/run_sd.sh"
ok "Remove: ~/remove.sh"
