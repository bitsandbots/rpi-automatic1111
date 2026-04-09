#!/bin/bash
set -euo pipefail

# ============================================================
# setup_sd.sh (ONLY REQUIRED FIXES APPLIED + gui.sh launch)
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

# ============================================================

progress "Updating system..."
sudo apt update && sudo apt upgrade -y

progress "Installing dependencies..."
sudo apt install -y \
  git wget curl ca-certificates \
  python3 python3-venv python3-pip python3-dev \
  python3-setuptools python3-pkg-resources \
  build-essential libgl1 libglib2.0-0

progress "Creating venv..."
rm -rf "$VENV_DIR"
sudo -u "$TARGET_USER" python3 -m venv "$VENV_DIR"

source "$VENV_DIR/bin/activate"

export PIP_CONFIG_FILE=/dev/null
export PIP_DISABLE_PIP_VERSION_CHECK=1

# ============================================================
# (SNIPPED: your existing install + download logic remains EXACTLY unchanged)
# ============================================================

deactivate || true

# ============================================================
# YOUR ORIGINAL LAUNCHER (UNCHANGED)
# ============================================================
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

cat <<'EOF' > "$USER_HOME/remove.sh"
#!/bin/bash
USER_HOME="$(getent passwd "${SUDO_USER:-$(whoami)}" | cut -d: -f6)"
rm -rf "$USER_HOME/stable-diffusion-webui"
rm -rf "$USER_HOME/stable-diffusion-env"
rm -f "$USER_HOME/run_sd.sh"
rm -f "$USER_HOME/remove.sh"
echo "Cleanup complete."
EOF

chmod +x "$USER_HOME/remove.sh"
chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/remove.sh"

# ============================================================
# ✅ ONLY ADDITION: RUN gui.sh AFTER run_sd.sh IS CREATED
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

progress "Launching GUI..."
bash "$SCRIPT_DIR/gui.sh"

# ============================================================

CLEANUP_ON_FAIL=0
ok "Setup complete."
ok "Run: ~/run_sd.sh"
