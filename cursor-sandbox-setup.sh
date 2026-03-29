#!/bin/bash
#
# Cursor Sandbox Setup (run once)
#
# Validates prerequisites, creates required directories, and writes
# a config file used by cursor-sandbox.sh.
#
# Re-run this script after changing CURSOR_APPIMAGE, WORKSPACE_DIR,
# or moving the Cursor AppImage to a new location.
#

set -e

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
source "$SCRIPT_DIR/cursor-sandbox-common.sh"

# Desktop integration (on by default; use --no-desktop to skip)
DESKTOP_INTEGRATION=true
for arg in "$@"; do
    if [[ "$arg" == "--no-desktop" ]]; then
        DESKTOP_INTEGRATION=false
        break
    fi
done
CURSOR_APPIMAGE="${CURSOR_APPIMAGE:-$(get_newest_cursor_appimage_in_dir "$APPIMAGE_DIR")}"

# If a newer AppImage is available in Downloads, offer to install it
if [[ -t 0 ]]; then
    dl_newest="$(get_newest_cursor_appimage_in_dir "$DOWNLOADS_DIR")"
    if [[ -n "$dl_newest" && -f "$dl_newest" && "$dl_newest" -nt "${CURSOR_APPIMAGE:-/dev/null}" ]]; then
        _dl_current_ver="$(get_appimage_version "${CURSOR_APPIMAGE:-}")"
        _dl_new_ver="$(get_appimage_version "$dl_newest")"
        echo "Installed: ${_dl_current_ver:-none}  —  Found in Downloads: $_dl_new_ver"
        read -rp "Install it to $APPIMAGE_DIR and use it? [Y/n] " answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
            CURSOR_APPIMAGE="$(install_appimage_to_dir "$dl_newest")"
        fi
    fi
fi

if [ -z "$WORKSPACE_DIR" ]; then
    read -rp "Enter workspace directory [$HOME/proj]: " WORKSPACE_DIR
    WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/proj}"
fi

REPO_PROFILE="${SCRIPT_DIR}/cursor.firejail.profile"

# ── Check prerequisites ──────────────────────────────────────────────
if ! command -v firejail &> /dev/null; then
    echo "Error: firejail is not installed"
    echo "Install it with: sudo apt install firejail   (Debian/Ubuntu)"
    echo "                 sudo dnf install firejail   (Fedora)"
    echo "                 sudo pacman -S firejail     (Arch Linux)"
    exit 1
fi

if [ ! -f "$REPO_PROFILE" ]; then
    echo "Error: Firejail profile not found at: $REPO_PROFILE"
    echo "Ensure cursor.firejail.profile is in the same directory as this script."
    exit 1
fi

if [ -z "$CURSOR_APPIMAGE" ] || [ ! -f "$CURSOR_APPIMAGE" ]; then
    echo "Error: No Cursor AppImage found."
    echo "Place a Cursor-*.AppImage in $APPIMAGE_DIR/"
    echo "or set CURSOR_APPIMAGE=/path/to/Cursor.AppImage"
    exit 1
fi

chmod +x "$CURSOR_APPIMAGE"
CURSOR_APPIMAGE="$(readlink -f "$CURSOR_APPIMAGE")"
WORKSPACE_DIR="$(readlink -f "$WORKSPACE_DIR")"

# ── Create required directories ───────────────────────────────────────
mkdir -p "$APPIMAGE_DIR" \
         "$INSTALL_DIR" \
         "$HOME/.local/bin" \
         "$HOME/.cursor" \
         "$HOME/.cursor-server" \
         "$HOME/.config/Cursor" \
         "$HOME/.local/share/Cursor" \
         "$HOME/.cache/Cursor" \
         "$WORKSPACE_DIR"

# ── Install launcher and config outside workspace (sandbox cannot modify) ─
cp "$REPO_PROFILE" "$INSTALL_DIR/cursor.firejail.profile"
cp "$SCRIPT_DIR/cursor-sandbox-common.sh" "$INSTALL_DIR/"
PROFILE="$INSTALL_DIR/cursor.firejail.profile"
write_cursor_sandbox_config
CURSOR_SANDBOX_CMD="$HOME/.local/bin/cursor"
cp "$SCRIPT_DIR/cursor-sandbox.sh" "$CURSOR_SANDBOX_CMD"
chmod +x "$CURSOR_SANDBOX_CMD"

echo "Config:  $CONFIG_FILE"
echo "Launcher: $CURSOR_SANDBOX_CMD (re-run setup to update)"

# ── Optional desktop integration ──────────────────────────────────────
if [[ "$DESKTOP_INTEGRATION" == "true" ]]; then
    APPLICATIONS_DIR="$HOME/.local/share/applications"
    ICONS_DIR="$HOME/.local/share/icons/hicolor"
    ICON_NAME="co.anysphere.cursor"
    ICON_EXTRACTED=false

    if command -v 7z &> /dev/null; then
        EXTRACT_DIR="$(mktemp -d)"
        trap "rm -rf '$EXTRACT_DIR'" EXIT
        if 7z x -o"$EXTRACT_DIR" "$CURSOR_APPIMAGE" "usr/share/pixmaps/${ICON_NAME}.png" "${ICON_NAME}.png" &>/dev/null; then
            ICON_SRC=
            if [[ -f "$EXTRACT_DIR/usr/share/pixmaps/${ICON_NAME}.png" ]]; then
                ICON_SRC="$EXTRACT_DIR/usr/share/pixmaps/${ICON_NAME}.png"
            elif [[ -f "$EXTRACT_DIR/${ICON_NAME}.png" ]]; then
                ICON_SRC="$EXTRACT_DIR/${ICON_NAME}.png"
            fi
            if [[ -n "$ICON_SRC" ]]; then
                mkdir -p "$ICONS_DIR/512x512/apps" "$ICONS_DIR/256x256/apps"
                if command -v convert &> /dev/null; then
                    convert "$ICON_SRC" -resize 512x512 "$ICONS_DIR/512x512/apps/${ICON_NAME}.png"
                    convert "$ICON_SRC" -resize 256x256 "$ICONS_DIR/256x256/apps/${ICON_NAME}.png"
                else
                    cp "$ICON_SRC" "$ICONS_DIR/512x512/apps/${ICON_NAME}.png"
                    cp "$ICON_SRC" "$ICONS_DIR/256x256/apps/${ICON_NAME}.png"
                fi
                ICON_EXTRACTED=true
            fi
        fi
        trap - EXIT
        rm -rf "$EXTRACT_DIR"
    else
        echo "Note: 7z (p7zip-full) not found. Skipping icon extraction."
        echo "      Desktop entry will be installed without an icon. You can continue without it,"
        echo "      or install p7zip-full and re-run setup to get the icon."
    fi

    if [[ "$ICON_EXTRACTED" == "true" ]] && command -v gtk-update-icon-cache &> /dev/null; then
        gtk-update-icon-cache -f -t "$ICONS_DIR" 2>/dev/null || true
    fi

    mkdir -p "$APPLICATIONS_DIR"
    cat > "$APPLICATIONS_DIR/cursor.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Cursor
Comment=Cursor - The AI Code Editor (sandboxed with firejail)
GenericName=Text Editor
Exec=$CURSOR_SANDBOX_CMD %F
Icon=$ICON_NAME
Terminal=false
StartupNotify=false
StartupWMClass=Cursor
Categories=TextEditor;Development;IDE;
MimeType=application/x-cursor-workspace;
Keywords=cursor;code;editor;ai;
Actions=new-empty-window;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=$CURSOR_SANDBOX_CMD --new-window %F
Icon=$ICON_NAME
DESKTOP

    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null || true
    fi

    echo "Desktop entry: $APPLICATIONS_DIR/cursor.desktop"
fi

echo ""
echo "Setup complete."
echo "  AppImage:  $CURSOR_APPIMAGE"
echo "  Workspace: $WORKSPACE_DIR"
echo "  Profile:   $PROFILE"
