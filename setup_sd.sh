#!/bin/bash
set -euo pipefail

# ============================================================
# install_sd.sh  (RPi5 + RPi4)
# Fixes:
# 1) Robust user/home detection (no eval/tilde issues)
# 2) Adds python3-setuptools at apt level
# 3) Fixes CLIP install by patching launch_utils.py to use:
#    --no-build-isolation (and --no-use-pep517) to avoid pkg_resources error
# 4) Generates run_sd.sh + remove.sh using same robust home logic
# ============================================================

# -----------------------------
# Pretty output colors
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

progress_bar() {
  echo -e "${RED}$1${NC}"
  sleep 1
}

# -----------------------------
# Resolve target user/home robustly (sudo/non-sudo safe)
# -----------------------------
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

# -----------------------------
# Home + paths
# -----------------------------
WEBUI_DIR="$USER_HOME/stable-diffusion-webui"
VENV_DIR="$USER_HOME/stable-diffusion-env"

# -----------------------------
# Clean fail (README promise)
# -----------------------------
CLEANUP_ON_FAIL=1
cleanup_partial_install() {
  [ "$CLEANUP_ON_FAIL" = "1" ] || return 0
  echo -e "${YELLOW}Installer failed. Cleaning up partial install...${NC}"
  rm -rf "$WEBUI_DIR" 2>/dev/null || true
  rm -rf "$VENV_DIR" 2>/dev/null || true
}
trap cleanup_partial_install ERR

# -----------------------------
# Architecture detection (README)
# -----------------------------
ARCH="$(uname -m)"
is_arm64() { [ "$ARCH" = "aarch64" ]; }
is_arm32() { [[ "$ARCH" == armv7* ]] || [ "$ARCH" = "armv7l" ]; }

# -----------------------------
# OS detection (Bookworm / Trixie)
# -----------------------------
OS_CODENAME=""
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_CODENAME="${VERSION_CODENAME:-}"
fi
is_bookworm() { [ "${OS_CODENAME:-}" = "bookworm" ]; }
is_trixie()   { [ "${OS_CODENAME:-}" = "trixie" ]; }

# -----------------------------
# Required command helper
# -----------------------------
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo -e "${RED}Missing required command:${NC} $1"; exit 1; }
}

# -----------------------------
# Update and upgrade system
# -----------------------------
progress_bar "Updating and upgrading system..."
sudo apt update && sudo apt upgrade -y

# -----------------------------
# Install dependencies
# -----------------------------
progress_bar "Installing necessary dependencies..."
sudo apt install -y \
  python3 python3-pip python3-venv python3-setuptools \
  git libgl1 libglib2.0-0 wget curl

# -----------------------------
# Gate unsupported architectures
# -----------------------------
if is_arm64; then
  echo -e "${GREEN}Detected architecture: aarch64 (ARM64).${NC}"
elif is_arm32; then
  echo -e "${YELLOW}Detected architecture: armv7l (ARM32) — best effort.${NC}"
else
  echo -e "${RED}Unsupported architecture: ${ARCH}${NC}"
  echo -e "${YELLOW}Supported: aarch64 (recommended) and armv7l/armv7* (best effort).${NC}"
  exit 1
fi

# Ensure basic tools exist (after deps install)
need_cmd python3
need_cmd pip3
need_cmd git
need_cmd curl
need_cmd wget

# -----------------------------
# Python version detection
# -----------------------------
PY_MAJOR="$(python3 -c 'import sys; print(sys.version_info.major)')"
PY_MINOR="$(python3 -c 'import sys; print(sys.version_info.minor)')"

# -----------------------------
# uv handling (robust for Trixie)
# -----------------------------
UV_BIN=""

find_uv() {
  if command -v uv >/dev/null 2>&1; then
    command -v uv
    return 0
  fi
  if [ -x "$USER_HOME/.local/bin/uv" ]; then
    echo "$USER_HOME/.local/bin/uv"
    return 0
  fi
  if [ -x "$USER_HOME/.cargo/bin/uv" ]; then
    echo "$USER_HOME/.cargo/bin/uv"
    return 0
  fi
  return 1
}

ensure_uv() {
  if UV_BIN="$(find_uv)"; then
    return 0
  fi

  progress_bar "Installing uv (local Python manager) for Trixie compatibility..."
  mkdir -p "$USER_HOME/.local/bin"
  curl -fsSL https://astral.sh/uv/install.sh | sh

  if UV_BIN="$(find_uv)"; then
    return 0
  fi

  echo -e "${RED}uv install failed or uv not found after install.${NC}"
  echo -e "${YELLOW}Checked:${NC} PATH, ~/.local/bin/uv, ~/.cargo/bin/uv"
  exit 1
}

create_venv() {
  rm -rf "$VENV_DIR" 2>/dev/null || true

  # Use uv+Python3.11 on Trixie OR if system python >= 3.12
  if is_trixie || { [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 12 ]; }; then
    ensure_uv

    progress_bar "Creating venv using Python 3.11 for compatibility..."
    "$UV_BIN" python install 3.11 >/dev/null
    "$UV_BIN" venv "$VENV_DIR" --python 3.11

    if [ ! -x "$VENV_DIR/bin/python" ]; then
      echo -e "${RED}Virtual environment creation failed at $VENV_DIR${NC}"
      exit 1
    fi

    VENV_MM="$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    if [ "$VENV_MM" != "3.11" ]; then
      echo -e "${RED}Venv Python is not 3.11 (got ${VENV_MM}). Aborting to prevent a broken install.${NC}"
      exit 1
    fi
  else
    progress_bar "Creating venv using system Python..."
    python3 -m venv "$VENV_DIR"
  fi
}

# -----------------------------
# Helper: download if missing (models)
# -----------------------------
download_if_missing() {
  local url="$1"
  local path="$2"

  if [ -z "$url" ] || [ -z "$path" ]; then
    echo -e "${YELLOW}Model download disabled (MODEL lines commented out). Skipping.${NC}"
    return 0
  fi

  if [ -f "$path" ]; then
    echo -e "${GREEN}Model already exists:${NC} $path"
    return 0
  fi

  mkdir -p "$(dirname "$path")"
  echo -e "${RED}Downloading:${NC} $url"
  wget -O "$path" "$url"
}

# -----------------------------
# ARM32: install community wheels from PINTO0309/pytorch4raspberrypi
# -----------------------------
install_pytorch_arm32_best_effort() {
  progress_bar "ARM32: locating matching prebuilt wheels (PINTO0309/pytorch4raspberrypi)..."

  local py_abi
  py_abi="$(python -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")')"

  local api="https://api.github.com/repos/PINTO0309/pytorch4raspberrypi/releases"
  local torch_url torchvision_url numpy_url

  torch_url="$(curl -fsSL "$api" | python - <<PY
import json, sys
abi = sys.argv[1]
data = json.load(sys.stdin)
def ok(name):
    n=name.lower()
    return ('torch-' in n and 'torchvision' not in n and abi in n and 'armv7l' in n and n.endswith('.whl'))
for rel in data:
    for a in rel.get('assets', []):
        name=a.get('name','')
        if ok(name):
            print(a.get('browser_download_url',''))
            raise SystemExit(0)
raise SystemExit(1)
PY
"$py_abi")" || true

  torchvision_url="$(curl -fsSL "$api" | python - <<PY
import json, sys
abi = sys.argv[1]
data = json.load(sys.stdin)
def ok(name):
    n=name.lower()
    return ('torchvision' in n and abi in n and 'armv7l' in n and n.endswith('.whl'))
for rel in data:
    for a in rel.get('assets', []):
        name=a.get('name','')
        if ok(name):
            print(a.get('browser_download_url',''))
            raise SystemExit(0)
raise SystemExit(1)
PY
"$py_abi")" || true

  numpy_url="$(curl -fsSL "$api" | python - <<PY
import json, sys
abi = sys.argv[1]
data = json.load(sys.stdin)
def ok(name):
    n=name.lower()
    return ('numpy' in n and abi in n and 'armv7l' in n and n.endswith('.whl'))
for rel in data:
    for a in rel.get('assets', []):
        name=a.get('name','')
        if ok(name):
            print(a.get('browser_download_url',''))
            raise SystemExit(0)
raise SystemExit(1)
PY
"$py_abi")" || true

  if [ -z "$torch_url" ] || [ -z "$torchvision_url" ]; then
    echo -e "${RED}ARM32 install failed cleanly:${NC} No compatible torch/torchvision wheels found for ${py_abi} (armv7l)."
    echo -e "${YELLOW}Recommendation:${NC} Switch to a 64-bit OS (ARM64), as noted in the README."
    return 1
  fi

  sudo apt install -y libopenblas0 libgomp1 libblas3 >/dev/null 2>&1 || true

  if [ -n "$numpy_url" ]; then
    progress_bar "ARM32: installing numpy wheel (when available)..."
    pip install "$numpy_url"
  fi

  progress_bar "ARM32: installing torch + torchvision wheels..."
  pip install "$torch_url" "$torchvision_url"

  return 0
}

# -----------------------------
# Create and activate venv
# -----------------------------
progress_bar "Setting up virtual environment..."
create_venv
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

# Make pip sane
python -m pip install --upgrade pip setuptools wheel >/dev/null

# -----------------------------
# Clone the Stable Diffusion WebUI repository
# -----------------------------
progress_bar "Cloning Stable Diffusion WebUI repository..."
rm -rf "$WEBUI_DIR" 2>/dev/null || true
git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$WEBUI_DIR"
cd "$WEBUI_DIR"

# -----------------------------
# Install PyTorch and requirements
# -----------------------------
progress_bar "Installing PyTorch and other dependencies..."
if is_arm64; then
  pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
else
  install_pytorch_arm32_best_effort
fi

pip install -r requirements.txt

# -----------------------------
# Download the model files (README: comment out MODEL lines to disable)
# -----------------------------
progress_bar "Downloading the model files..."

MODEL1_PATH="$WEBUI_DIR/models/Stable-diffusion/CyberRealistic_V7.0_FP16.safetensors"
MODEL1_URL="https://huggingface.co/cyberdelia/CyberRealistic/resolve/main/CyberRealistic_V7.0_FP16.safetensors"
MODEL2_PATH="$WEBUI_DIR/models/Stable-diffusion/Realistic_Vision_V5.1-inpainting.safetensors"
MODEL2_URL="https://huggingface.co/SG161222/Realistic_Vision_V5.1_noVAE/resolve/main/Realistic_Vision_V5.1-inpainting.safetensors"

download_if_missing "$MODEL1_URL" "$MODEL1_PATH"
download_if_missing "$MODEL2_URL" "$MODEL2_PATH"

# -----------------------------
# Create the unified run_sd.sh script (robust HOME)
# -----------------------------
progress_bar "Creating run_sd.sh script..."
cat <<'EOF' > "$USER_HOME/run_sd.sh"
#!/bin/bash
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

cleanup() {
  echo -e "${YELLOW}Stopping Stable Diffusion...${NC}"
  if command -v pkill >/dev/null 2>&1; then
    pkill -f "launch.py" 2>/dev/null || true
  fi
  if declare -F deactivate >/dev/null 2>&1; then
    deactivate 2>/dev/null || true
  fi
  echo -e "${YELLOW}Virtual environment deactivated.${NC}"
  exit
}
trap cleanup SIGINT

if [ ! -d "$VENV_DIR" ]; then
  echo -e "${RED}Virtual environment not found at $VENV_DIR. Please set it up first.${NC}"
  exit 1
fi
if [ ! -d "$WEBUI_DIR" ]; then
  echo -e "${RED}Stable Diffusion WebUI not found at $WEBUI_DIR.${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}Select an option:${NC}"
echo "1) Run connected to the internet (http://LAN_IP:7860)"
echo "2) Run completely offline / localhost only (http://127.0.0.1:7860)"
echo "3) Uninstall"
echo "q) Quit"
echo ""

read -rp "Enter your choice: " choice
case "$choice" in
  1)
    echo -e "${GREEN}Running with internet connection (LAN access)...${NC}"
    source "$VENV_DIR/bin/activate"
    cd "$WEBUI_DIR" || exit 1
    DEFAULT_LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [ -n "${DEFAULT_LOCAL_IP:-}" ] || DEFAULT_LOCAL_IP="127.0.0.1"
    echo -e "Access it at: http://$DEFAULT_LOCAL_IP:7860"
    python launch.py --skip-torch-cuda-test --no-half --listen
    cleanup
    ;;
  2)
    echo -e "${GREEN}Running completely offline (localhost only)...${NC}"
    source "$VENV_DIR/bin/activate"
    cd "$WEBUI_DIR" || exit 1
    echo -e "Access it at: http://127.0.0.1:7860"
    python launch.py --skip-torch-cuda-test --no-half --listen --skip-install
    cleanup
    ;;
  3)
    echo -e "${RED}Uninstalling...${NC}"
    bash "$USER_HOME/remove.sh"
    ;;
  q|Q)
    echo -e "${YELLOW}Quitting.${NC}"
    exit 0
    ;;
  *)
    echo -e "${RED}Invalid option. Exiting.${NC}"
    exit 1
    ;;
esac
EOF
chmod +x "$USER_HOME/run_sd.sh"

# -----------------------------
# Create remove.sh (robust HOME)
# -----------------------------
progress_bar "Creating remove.sh script..."
cat <<'EOF' > "$USER_HOME/remove.sh"
#!/bin/bash

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

if [ -f "$USER_HOME/run_sd.sh" ]; then
  echo "Removing $USER_HOME/run_sd.sh..."
  rm "$USER_HOME/run_sd.sh"
fi
if [ -d "$USER_HOME/stable-diffusion-webui" ]; then
  echo "Removing $USER_HOME/stable-diffusion-webui..."
  rm -rf "$USER_HOME/stable-diffusion-webui"
fi
if [ -d "$USER_HOME/stable-diffusion-env" ]; then
  echo "Removing $USER_HOME/stable-diffusion-env..."
  rm -rf "$USER_HOME/stable-diffusion-env"
fi
if [ -f "$USER_HOME/remove.sh" ]; then
  echo "Removing $USER_HOME/remove.sh..."
  rm "$USER_HOME/remove.sh"
fi

echo "Cleanup complete."
EOF
chmod +x "$USER_HOME/remove.sh"

# -----------------------------
# Patch: repair broken repo URL in launch_utils.py
# + Patch: fix CLIP install flags (no build isolation / no pep517)
# -----------------------------
echo "Patch to repair broken repo pre-loded from automatic1111 offical GitHub repo."
cd "$USER_HOME/stable-diffusion-webui" || exit 1
cp -a modules/launch_utils.py "modules/launch_utils.py.bak.$(date +%F_%H%M%S)"

# Your existing repo URL patch
grep -n "stable_diffusion_repo" modules/launch_utils.py >/dev/null 2>&1
grep -n "stable_diffusion_commit_hash" modules/launch_utils.py >/dev/null 2>&1
sed -i 's#https://github.com/Stability-AI/stablediffusion.git#https://github.com/comp6062/Stability-AI-stablediffusion.git#g' modules/launch_utils.py
rm -rf repositories/stable-diffusion-stability-ai

# NEW: CLIP install patch to prevent pkg_resources failure
# (A1111 calls: run_pip(f"install {clip_package}", "clip"))
if grep -n 'run_pip(f"install {clip_package}", "clip")' modules/launch_utils.py >/dev/null 2>&1; then
  sed -i 's/run_pip(f"install {clip_package}", "clip")/run_pip(f"install --no-build-isolation --no-use-pep517 {clip_package}", "clip")/g' modules/launch_utils.py
  echo "Patched CLIP install to use --no-build-isolation --no-use-pep517"
else
  echo "WARNING: Could not find expected CLIP install line to patch. CLIP may still fail at runtime."
fi

echo "End Patch"

# Installer succeeded; don't clean up.
CLEANUP_ON_FAIL=0

echo -e "${GREEN}Setup complete.${NC} Use ~/run_sd.sh to start Stable Diffusion or ~/remove.sh to uninstall."
