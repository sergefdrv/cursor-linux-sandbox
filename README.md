# Cursor Linux Sandbox

Run [Cursor](https://cursor.com) inside a [firejail](https://firejail.wordpress.com/) sandbox on Linux. Cursor and its AI agents are confined to an explicit allowlist of paths -- your project directory plus a small set of read-only tool installs (cargo, rustup, nvm, pyenv, pnpm, etc.) and Cursor's own profile. The rest of your filesystem is invisible.

> **Disclaimer:** Personal project, not affiliated with or endorsed by Cursor (Anysphere) or the firejail authors. The sandbox is best-effort -- firejail/Linux namespace isolation is not a security boundary against a determined attacker, and escape paths exist. Review [`cursor.firejail.profile`](cursor.firejail.profile) before use, and don't treat this as your only line of defense. Provided as-is, no warranty (see [LICENSE](LICENSE)).

## What the sandbox enforces

- **Filesystem whitelisting** -- only the workspace and Cursor's config dirs are visible under `$HOME`
- **seccomp filtering** -- blocks dangerous syscalls
- **Capability dropping** -- removes all Linux capabilities
- **Private `/dev`** -- only exposes GPU, audio, and essential devices
- **Private `/tmp`** -- Cursor gets its own `/tmp`, isolated from the host
- **Protocol filtering** -- limits network to `unix`, `inet`, `inet6`, `netlink`

Cursor **can** use the display server (X11/Wayland), GPU, audio, network, and read your `.gitconfig` (read-only). It **cannot** see your home directory, other projects, SSH keys, browser data, or anything outside the workspace.

## Prerequisites

- Linux with X11 or Wayland
- [Cursor AppImage](https://cursor.com) (>= 0.45)
- firejail

```bash
sudo apt install firejail    # Debian/Ubuntu
sudo dnf install firejail    # Fedora/RHEL
sudo pacman -S firejail      # Arch
```

## Setup

Run setup once:

```bash
./cursor-sandbox-setup.sh
```

On first run, setup will prompt for your workspace directory. It also checks `~/Downloads` (or `$XDG_DOWNLOAD_DIR`) for a newer AppImage and offers to install it — both on first run and when re-running setup after an upgrade. You can also put the AppImage in `~/.local/opt/cursor/` beforehand, or set `CURSOR_APPIMAGE` when running setup.

Setup installs the launcher and config outside the workspace (so the sandbox cannot modify them): config and profile in `~/.local/opt/cursor-sandbox/`, launcher at `~/.local/bin/cursor`. Re-run setup after pulling changes to update the installed copy.

Override defaults:

```bash
CURSOR_APPIMAGE=/path/to/Cursor.AppImage WORKSPACE_DIR=$HOME/repos ./cursor-sandbox-setup.sh
```

**Desktop integration** (on by default, use `--no-desktop` to skip): adds a "Cursor" entry in your app menu (`~/.local/share/applications/`) and, if **7z** (p7zip-full) is available, the application icon. Without 7z the entry is created without an icon.

## Usage

Run `cursor` from anywhere (if `~/.local/bin` is in your PATH), or from the repo:

```bash
./cursor-sandbox.sh
```

Both use the same config in `~/.local/opt/cursor-sandbox/`.

On each launch the launcher checks `~/Downloads` for a newer `Cursor-*.AppImage`; if found, you're prompted to install it — via a terminal prompt or, from the desktop, a `zenity`/`kdialog` dialog (falls back to a notification if neither is available).

## Docker / Podman

The launcher detects and passes through your Docker/Podman socket at startup. Inside the sandbox, daemon socket access doesn't work directly -- talk to the host daemon over its API by adding `--remote`:

```bash
podman --remote ps
docker --remote info
```

Anything you launch this way actually executes on the host as your real user, outside the sandbox.

## Files

- `cursor-sandbox-setup.sh` -- one-time setup: installs launcher and config to `~/.local/opt/cursor-sandbox/` and `~/.local/bin/cursor`; optionally adds desktop entry (use `--no-desktop` to skip)
- `cursor-sandbox.sh` -- launcher: reads config from `~/.local/opt/cursor-sandbox/`, checks for updates, starts firejail
- `cursor.firejail.profile` -- firejail security profile (copied into `~/.local/opt/cursor-sandbox/` by setup)

## Troubleshooting

**Cursor doesn't start** -- check `firejail --version`, verify the AppImage path in `~/.local/opt/cursor-sandbox/.cursor-sandbox.env`, look for errors in terminal output.

**Wayland issues** -- the launcher whitelists `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`; if your compositor uses a non-default name (or doesn't export `WAYLAND_DISPLAY` at all), the launcher will silently drop Wayland passthrough. Find the real socket with `ls $XDG_RUNTIME_DIR/wayland-*` and re-export `WAYLAND_DISPLAY` accordingly.

**Containers not working** -- look at the launcher's startup output. If it prints `Container socket: not found`, your podman/docker daemon isn't running on the host (start it outside the sandbox). If it does find a socket, make sure your invocation includes `--remote` (e.g., `podman --remote ps`).

## License

MIT -- see [LICENSE](LICENSE).
