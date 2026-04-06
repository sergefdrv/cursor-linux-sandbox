# Cursor Linux Sandbox

Run [Cursor](https://cursor.com) inside a [firejail](https://firejail.wordpress.com/) sandbox on Linux. Cursor and its AI agents are confined to an explicit allowlist of paths -- your project directory plus a small set of read-only tool installs (cargo, rustup, nvm, pyenv, pnpm, etc.) and Cursor's own profile. The rest of your filesystem is invisible.

> **Disclaimer:** Personal project, not affiliated with or endorsed by Cursor (Anysphere) or the firejail authors. The sandbox is best-effort -- firejail/Linux namespace isolation is not a security boundary against a determined attacker, and escape paths exist. Review [`cursor.firejail.profile`](cursor.firejail.profile) before use, and don't treat this as your only line of defense. Provided as-is, no warranty (see [LICENSE](LICENSE)).

## What the sandbox enforces

- **Filesystem whitelisting** -- only explicitly whitelisted paths are visible under `$HOME` (workspace, Cursor config, read-only tools)
- **seccomp filtering** -- blocks dangerous syscalls
- **Capability dropping** -- removes all Linux capabilities
- **No privilege escalation** -- prevents gaining root or new privileges inside the sandbox
- **Private `/dev`** -- only exposes GPU, audio, and essential devices
- **Private `/tmp`** -- Cursor gets its own `/tmp`, isolated from the host
- **Protocol filtering** -- limits network to `unix`, `inet`, `inet6`, `netlink`

Cursor **can** use the display server (X11/Wayland), GPU, audio, network, and read your `.gitconfig` (read-only). It **cannot** see your home directory, other projects, SSH keys, or browser data.

## Prerequisites

- Linux with X11 or Wayland
- [Cursor AppImage](https://cursor.com) (>= 0.45)
- firejail
- xdg-dbus-proxy (used by firejail’s `dbus-user filter` for filtered session D-Bus)
- `gdbus` (GLib; setup installs an `xdg-open` shim that calls the XDG desktop portal)

```bash
sudo apt install firejail xdg-dbus-proxy libglib2.0-bin    # Debian/Ubuntu
sudo dnf install firejail xdg-dbus-proxy glib2           # Fedora/RHEL
sudo pacman -S firejail xdg-desktop-portal glib2         # Arch
```

*Note:* You do **not** need `libfuse2`. The launcher uses firejail's `--appimage` flag, which mounts the AppImage directly inside a mount namespace without FUSE.

## Setup

Run setup once:

```bash
./cursor-sandbox-setup.sh
```

On first run, setup will prompt for your workspace directory. It also checks `$XDG_DOWNLOAD_DIR` (defaults to `~/Downloads`) for a newer AppImage and offers to install it — both on first run and when re-running setup after an upgrade. You can also put the AppImage in `~/.local/opt/cursor/` beforehand, or set `CURSOR_APPIMAGE` when running setup.

Setup installs the launcher and config outside the workspace (so the sandbox cannot modify them): config and profile in `~/.local/opt/cursor-sandbox/`, launcher at `~/.local/bin/cursor`, and `~/.local/opt/cursor-sandbox/bin/xdg-open` (portal shim for opening links on the host). Re-run setup after pulling changes to update the installed copy.

Override defaults:

```bash
CURSOR_APPIMAGE=/path/to/Cursor.AppImage WORKSPACE_DIR=$HOME/repos ./cursor-sandbox-setup.sh
```

**Desktop integration** (on by default, use `--no-desktop` to skip): adds a "Cursor" entry in your app menu (`~/.local/share/applications/`) and, if **7z** (`p7zip-full`) is available, the application icon. Without 7z the entry is created without an icon.

## Usage

Run `cursor` from anywhere (if `~/.local/bin` is in your PATH), or from the repo:

```bash
./cursor-sandbox.sh
```

Both use the same config in `~/.local/opt/cursor-sandbox/`.

On each launch the launcher checks `~/Downloads` for a newer `Cursor-*.AppImage`; if found, you're prompted to install it — via a terminal prompt or, from the desktop, a `zenity`/`kdialog` dialog (falls back to a simple notification if neither is available).

## Why `--no-sandbox`?

The launcher passes `--no-sandbox` to Cursor (Electron/Chromium). This disables Chromium's internal SUID sandbox, which is redundant here: firejail already provides namespace isolation and seccomp filtering at the OS level. Running both sandboxes simultaneously would cause conflicts.

## Tools

The sandbox exposes common tool directories as **read-only**: `.cargo`, `.rustup`, `.nvm`, `.pyenv`, `~/go`, and `~/.local/bin`. Compilers, interpreters, and CLI tools installed there work inside the sandbox, but installing or updating them (e.g., `nvm install`, `rustup update`, `pip install`) must be done outside the sandbox.

## Docker / Podman

The launcher detects and passes through your Docker/Podman socket at startup. Inside the sandbox, daemon socket access doesn't work directly -- talk to the host daemon over its API by adding `--remote`:

```bash
podman --remote ps
docker --remote info
```

Anything you launch this way actually executes on the host as your real user, outside the sandbox.

## Troubleshooting

**Cursor doesn't start** -- run `cursor` or `./cursor-sandbox.sh` from a terminal. The launcher prints its config before launching, and firejail's error output will usually point to the problem.

**Wayland issues** -- the launcher whitelists `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`; if your compositor uses a non-default name (or doesn't export `WAYLAND_DISPLAY` at all), the launcher will silently drop Wayland passthrough. Find the real socket with `ls $XDG_RUNTIME_DIR/wayland-*` and re-export `WAYLAND_DISPLAY` accordingly.

**Containers not working** -- look at the launcher's startup output. If it prints `Container socket: not found`, your podman/docker daemon isn't running on the host (start it outside the sandbox). If it does find a socket, make sure your invocation includes `--remote` (e.g., `podman --remote ps`).

**AppArmor errors (Ubuntu 23.10+)** -- if firejail fails with AppArmor-related messages, reload the firejail profile: `sudo apparmor_parser -r /etc/apparmor.d/firejail-default`.

## License

MIT -- see [LICENSE](LICENSE).
