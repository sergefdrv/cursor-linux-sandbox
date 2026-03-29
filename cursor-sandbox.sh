#!/bin/bash
#
# Cursor Sandboxed Launcher (firejail)
#
# Runs Cursor AppImage inside a firejail sandbox that limits filesystem
# access to the workspace directory and Cursor's own settings.
#
# Run cursor-sandbox-setup.sh first to generate the config file.
#

set -e

# ── Load config ──────────────────────────────────────────────────────
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
if [ -f "$SCRIPT_DIR/cursor-sandbox-common.sh" ]; then
    source "$SCRIPT_DIR/cursor-sandbox-common.sh"
else
    source "$HOME/.local/opt/cursor-sandbox/cursor-sandbox-common.sh"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$SCRIPT_DIR/cursor-sandbox-setup.sh" ]; then
        echo "Config not found. Running setup..."
        "$SCRIPT_DIR/cursor-sandbox-setup.sh"
        [ -f "$CONFIG_FILE" ] || { echo "Error: Setup failed to create config."; exit 1; }
    else
        echo "Config not found at: $CONFIG_FILE"
        echo "Run cursor-sandbox-setup.sh from the repo to install."
        exit 1
    fi
fi

source "$CONFIG_FILE"

# ── Check ~/Downloads for a newer AppImage ────────────────────────────
dl_newest="$(get_newest_cursor_appimage_in_dir "$DOWNLOADS_DIR")"
if [ -n "$dl_newest" ] && [ "$dl_newest" -nt "$CURSOR_APPIMAGE" ]; then
    _ver_old="$(get_appimage_version "$CURSOR_APPIMAGE")"
    _ver_new="$(get_appimage_version "$dl_newest")"
    _ver_summary="Installed: ${_ver_old:-none}  —  Found in Downloads: $_ver_new"
    if [[ -t 0 ]]; then
        echo "$_ver_summary"
        read -rp "Install and launch it? [Y/n] " answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
            CURSOR_APPIMAGE="$(install_appimage_to_dir "$dl_newest")"
            write_cursor_sandbox_config
            source "$CONFIG_FILE"
        fi
    else
        notify-send "Cursor Update" "$_ver_summary. Run cursor from a terminal to install." 2>/dev/null || true
    fi
fi

# ── Print launch info ────────────────────────────────────────────────
echo "Starting Cursor in firejail sandbox..."
echo "  AppImage:  $CURSOR_APPIMAGE"
echo "  Workspace: $WORKSPACE_DIR"
echo "  Profile:   $PROFILE"

# ── Build dynamic firejail arguments ─────────────────────────────────
FIREJAIL_ARGS=(
    --profile="$PROFILE"

    # Handle AppImage mounting inside the sandbox (no host FUSE needed)
    --appimage

    # Workspace directory (read-write)
    --whitelist="$WORKSPACE_DIR"

    # AppImage file itself (read-only)
    --whitelist="$CURSOR_APPIMAGE"
    --read-only="$CURSOR_APPIMAGE"
)

# Display server sockets (Wayland + XWayland)
USER_ID=$(id -u)
XDG_DIR="/run/user/$USER_ID"

if [ -n "$WAYLAND_DISPLAY" ] && [ -S "$XDG_DIR/$WAYLAND_DISPLAY" ]; then
    echo "  Wayland:   $XDG_DIR/$WAYLAND_DISPLAY"
    FIREJAIL_ARGS+=(--whitelist="$XDG_DIR/$WAYLAND_DISPLAY")
fi

# D-Bus session bus (needed by Electron for IPC, tray, notifications)
if [ -S "$XDG_DIR/bus" ]; then
    FIREJAIL_ARGS+=(--whitelist="$XDG_DIR/bus")
fi

# Audio server socket (needed for voice prompting / microphone)
if [ -d "$XDG_DIR/pulse" ]; then
    echo "  Audio:     PulseAudio"
    FIREJAIL_ARGS+=(--whitelist="$XDG_DIR/pulse")
elif [ -S "$XDG_DIR/pipewire-0" ]; then
    echo "  Audio:     PipeWire"
    FIREJAIL_ARGS+=(--whitelist="$XDG_DIR/pipewire-0")
fi

# Mount container socket if available (detected at launch time)
if [ -S "/run/user/$USER_ID/podman/podman.sock" ]; then
    echo "  Podman socket: found"
    FIREJAIL_ARGS+=(--whitelist="/run/user/$USER_ID/podman/podman.sock")
elif [ -S "/var/run/docker.sock" ]; then
    echo "  Docker socket: found"
    FIREJAIL_ARGS+=(--whitelist="/var/run/docker.sock")
else
    echo "  Container socket: not found (containers may not work)"
fi

echo ""
echo "Launching firejail sandbox..."
echo "================================================"
echo ""

# --no-sandbox: disable Chromium's internal SUID sandbox since firejail
# already provides seccomp + namespace sandboxing at the OS level.
exec firejail "${FIREJAIL_ARGS[@]}" "$CURSOR_APPIMAGE" --no-sandbox "$@"
