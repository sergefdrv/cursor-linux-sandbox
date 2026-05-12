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
    _do_install() {
        CURSOR_APPIMAGE="$(install_appimage_to_dir "$dl_newest")"
        write_cursor_sandbox_config
        source "$CONFIG_FILE"
    }
    if [[ -t 0 ]]; then
        echo "$_ver_summary"
        read -rp "Install and launch it? [Y/n] " answer
        [[ -z "$answer" || "$answer" =~ ^[Yy] ]] && _do_install
    elif command -v zenity &>/dev/null && zenity --question --title="Cursor Update" --text="$_ver_summary\n\nInstall and launch it?" 2>/dev/null; then
        _do_install
    elif command -v kdialog &>/dev/null && kdialog --yesno "$_ver_summary\n\nInstall and launch it?" --title "Cursor Update" 2>/dev/null; then
        _do_install
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

# Audio server socket (needed for voice prompting / microphone)
if [ -d "$XDG_DIR/pulse" ]; then
    echo "  Audio:     PulseAudio"
    FIREJAIL_ARGS+=(--whitelist="$XDG_DIR/pulse")
elif [ -S "$XDG_DIR/pipewire-0" ]; then
    echo "  Audio:     PipeWire"
    FIREJAIL_ARGS+=(--whitelist="$XDG_DIR/pipewire-0")
fi

# Container socket passthrough (host-side daemon access via --remote).
# OFF by default: a process that can talk to the host daemon socket can ask
# it to run a privileged container with `/` mounted in -- effectively root on
# the host (rootful Docker / rootful Podman) or full access to your user
# account (rootless Podman). That trivially escapes the sandbox.
#
# Opt in by exporting CURSOR_SANDBOX_BIND_CONTAINER_SOCKET=1, only if you
# accept that anything Cursor (or its agents) launches via the socket runs
# OUTSIDE the sandbox.
if [ "${CURSOR_SANDBOX_BIND_CONTAINER_SOCKET:-0}" = "1" ]; then
    if [ -S "/run/user/$USER_ID/podman/podman.sock" ]; then
        echo "  Podman socket: bound (CURSOR_SANDBOX_BIND_CONTAINER_SOCKET=1)"
        FIREJAIL_ARGS+=(--whitelist="/run/user/$USER_ID/podman/podman.sock")
    elif [ -S "/var/run/docker.sock" ]; then
        echo "  Docker socket: bound (CURSOR_SANDBOX_BIND_CONTAINER_SOCKET=1)"
        FIREJAIL_ARGS+=(--whitelist="/var/run/docker.sock")
    else
        echo "  Container socket: opt-in set but no socket found on host"
    fi
fi

# ── URL handler (portal OpenURI shim from setup) ─────────────────────
# Installed by cursor-sandbox-setup.sh as $INSTALL_DIR/bin/xdg-open.
URL_HANDLER_BIN="$INSTALL_DIR/bin"
if [[ ! -x "$URL_HANDLER_BIN/xdg-open" ]]; then
    echo "Warning: $URL_HANDLER_BIN/xdg-open missing — run cursor-sandbox-setup.sh"
fi
FIREJAIL_ARGS+=(
    --whitelist="$URL_HANDLER_BIN"
    --read-only="$URL_HANDLER_BIN"
    --env=PATH="$URL_HANDLER_BIN:$PATH"
    --env=BROWSER="$URL_HANDLER_BIN/xdg-open"
)
echo "  URL handler: $URL_HANDLER_BIN/xdg-open"

echo ""
echo "Launching firejail sandbox..."
echo "================================================"
echo ""

# --no-sandbox: disable Chromium's internal SUID sandbox since firejail
# already provides seccomp + namespace sandboxing at the OS level.
exec firejail "${FIREJAIL_ARGS[@]}" "$CURSOR_APPIMAGE" --no-sandbox "$@"
