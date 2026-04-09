#!/bin/bash
set -e

APP_NAME="Stable Diffusion GUI"
SCRIPT="$HOME/run_sd.sh"
LAUNCHER="$HOME/.local/share/applications/sd-gui.desktop"
DESKTOP_SHORTCUT="$HOME/Desktop/StableDiffusionGUI.desktop"

# Install dependencies
sudo apt update
sudo apt install -y zenity lxterminal

# Create GUI runner script
cat > "$HOME/.sd_gui_runner.sh" << 'EOF'
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

chmod +x "$HOME/.sd_gui_runner.sh"

# Create application launcher
mkdir -p "$HOME/.local/share/applications"

cat > "$LAUNCHER" << EOF
[Desktop Entry]
Name=$APP_NAME
Comment=Launch Stable Diffusion GUI
Exec=$HOME/.sd_gui_runner.sh
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Utility;
EOF

# Copy to Desktop
cp "$LAUNCHER" "$DESKTOP_SHORTCUT"
chmod +x "$DESKTOP_SHORTCUT"

echo ""
echo "✅ DONE"
echo "→ Desktop shortcut created"
echo "→ Menu entry installed"
echo ""
echo "Launch it from:"
echo "  - Desktop icon"
echo "  - Start Menu → Utilities → Stable Diffusion GUI"