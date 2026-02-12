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

Place your Cursor AppImage in `~/.local/opt/cursor/`:

```bash
mkdir -p ~/.local/opt/cursor
mv ~/Downloads/Cursor-*.AppImage ~/.local/opt/cursor/
```

Run setup once -- it will auto-detect the AppImage and ask for your workspace directory:

```bash
./cursor-sandbox-setup.sh
```

To override defaults, pass env vars:

```bash
CURSOR_APPIMAGE=/path/to/Cursor.AppImage WORKSPACE_DIR=$HOME/repos ./cursor-sandbox-setup.sh
```

## Desktop integration

Setup installs desktop integration by default: a "Cursor" entry in your app menu (under `~/.local/share/applications/`), a launcher symlink at `~/.local/bin/cursor` (so the desktop file works even when the repo path contains spaces), and, if **7z** (p7zip-full) is available, the application icon under `~/.local/share/icons/hicolor/`. If 7z is not installed, the desktop entry is still created but without an icon (you can continue without it, or install p7zip-full and re-run setup to get the icon). To skip desktop integration, run setup with `--no-desktop`.

## Usage

From the repo directory:

```bash
./cursor-sandbox.sh
```

Or run `cursor` from anywhere if `~/.local/bin` is in your PATH (setup creates a symlink there when desktop integration is enabled).

On each launch, the script checks `~/Downloads` for a newer `Cursor-*.AppImage`. If one is found, you're prompted to install it.

## Docker / Podman

The launcher detects and passes through your Docker/Podman socket at startup. Inside the sandbox, daemon socket access doesn't work directly -- talk to the host daemon over its API by adding `--remote`:

```bash
podman --remote ps
docker --remote info
```

Anything you launch this way actually executes on the host as your real user, outside the sandbox.

## Files

- `cursor-sandbox-setup.sh` -- one-time setup: validates prerequisites, writes config, optionally installs desktop entry and `~/.local/bin/cursor` symlink
- `cursor-sandbox.sh` -- launcher: checks for updates, starts firejail
- `cursor.firejail.profile` -- firejail security profile (whitelist, seccomp, caps)
- `.cursor-sandbox.env` -- generated config (gitignored)

## Troubleshooting

**Cursor doesn't start** -- check `firejail --version`, verify the AppImage path in `.cursor-sandbox.env`, look for errors in terminal output.

**Wayland issues** -- the launcher whitelists `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`; if your compositor uses a non-default name (or doesn't export `WAYLAND_DISPLAY` at all), the launcher will silently drop Wayland passthrough. Find the real socket with `ls $XDG_RUNTIME_DIR/wayland-*` and re-export `WAYLAND_DISPLAY` accordingly.

**Containers not working** -- look at the launcher's startup output. If it prints `Container socket: not found`, your podman/docker daemon isn't running on the host (start it outside the sandbox). If it does find a socket, make sure your invocation includes `--remote` (e.g., `podman --remote ps`).

## License

MIT -- see [LICENSE](LICENSE).
