#!/bin/bash
# Shared paths and helpers.
# Source this file; do not run directly.

APPIMAGE_DIR="$HOME/.local/opt/cursor"
DOWNLOADS_DIR="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"

get_newest_cursor_appimage_in_dir() {
    ls -t "$1"/Cursor-*.AppImage 2>/dev/null | head -1
}

# Install AppImage from path into APPIMAGE_DIR. Prints new path.
install_appimage_to_dir() {
    local src="$1"
    [[ -n "$src" && -f "$src" ]] || return 1
    mkdir -p "$APPIMAGE_DIR" || return 1
    mv "$src" "$APPIMAGE_DIR/" || return 1
    echo "$APPIMAGE_DIR/$(basename "$src")"
}

# Write CONFIG_FILE from current CURSOR_APPIMAGE, WORKSPACE_DIR, PROFILE.
write_cursor_sandbox_config() {
    {
        echo '# Automatically generated -- re-run setup to regenerate'
        printf 'CURSOR_APPIMAGE=%q\n' "$CURSOR_APPIMAGE"
        printf 'WORKSPACE_DIR=%q\n' "$WORKSPACE_DIR"
        printf 'PROFILE=%q\n' "$PROFILE"
    } > "$CONFIG_FILE"
}
