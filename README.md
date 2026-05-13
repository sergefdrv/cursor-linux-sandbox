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

The sandbox exposes common tool directories: `.rustup`, `.nvm`, `.pyenv`, `~/go`, and `~/.local/bin` are wholesale **read-only**. `.cargo` and `~/.local/share/pnpm` are exposed **read-write** with the binary/config sub-paths individually marked read-only — `~/.cargo/bin`, `~/.cargo/env`, `~/.cargo/config{,.toml}`, `~/.local/share/pnpm/pnpm`, `~/.local/share/pnpm/global`, `~/.local/share/pnpm/nodejs`. Compilers, interpreters, and CLI tools installed there work inside the sandbox, but installing or updating them (e.g., `nvm install`, `rustup update`, `pip install --user`) must be done outside the sandbox.

Package-manager **caches** are read-write and shared with the host: `~/.cargo/registry`, `~/.cargo/git`, `~/.npm/_cacache`, `~/.local/share/pnpm/store`, `~/.cache/pip`. This lets `cargo build`, `npm install`, `pnpm install`, and `pip install` work from within a workspace. Sharing is safe because each tool verifies cache content against a lockfile (cargo SHA-256 vs `Cargo.lock`, npm SRI vs `package-lock.json`, pnpm content-addressed store, pip `--require-hashes`), so a sandboxed process cannot substitute forged cache entries for host or other-project builds.

The `.cargo` and `~/.local/share/pnpm` trees aren't wholesale read-only because firejail's `read-write` directive can't carve a writable hole through a `whitelist`+`read-only` parent (no separate bind mount is made for the sub-path). Inverting the default — RW tree, RO binary sub-paths — is what makes the cache carve-outs actually writable. The trade-off: a sandboxed process can write to non-binary files in those trees that aren't individually RO-listed (e.g. `~/.cargo/.crates.toml`). If you've stored anything sensitive elsewhere under `.cargo`, add a `read-only` entry for it via `cursor.local`.

## Site-local overrides

The profile loads an optional `cursor.local` file (firejail's `.local` convention — silently skipped if missing) before any blacklists, so you can add `noblacklist`, `whitelist`, and `read-only` directives without editing the upstream profile. Put your additions in:

```
~/.local/opt/cursor-sandbox/cursor.local
```

That directory is created by `cursor-sandbox-setup.sh` and lives outside the sandbox's writable scope, so the override file can't be tampered with from inside Cursor. Each `whitelist` widens what Cursor can see inside `$HOME`; treat the file like editing the main profile and keep the entries minimal.

### Example

Expose a hypothetical tool `foo` — its install dir under `~/.foo` read-only, its state dir read-write:

```
noblacklist ${HOME}/.foo
whitelist ${HOME}/.foo
read-only ${HOME}/.foo

noblacklist ${HOME}/.local/state/foo
whitelist ${HOME}/.local/state/foo
```

Same shape works for any CLI plugin Cursor needs to reach: per-user state under `$HOME` (read-write), plus the tool's install location (read-only — install/upgrade from outside the sandbox).

## Docker / Podman

**Off by default.** The host Docker/Podman socket is not exposed inside the sandbox unless you opt in. Anything launched via that socket runs *on the host as your real user, outside the sandbox* — and a process that can talk to the daemon can trivially ask it to run a privileged container with `/` bind-mounted in, which is equivalent to host root (Docker / rootful Podman) or full account access (rootless Podman). Binding the socket therefore defeats the sandbox.

Opt in only if you accept that trade-off:

```bash
CURSOR_SANDBOX_BIND_CONTAINER_SOCKET=1 cursor
```

Inside the sandbox, talk to the host daemon over its API by adding `--remote`:

```bash
podman --remote ps
docker --remote info
```

To make the opt-in persistent, export the variable in your shell rc.

## Troubleshooting

**Cursor doesn't start** -- run `cursor` or `./cursor-sandbox.sh` from a terminal. The launcher prints its config before launching, and firejail's error output will usually point to the problem.

**Wayland issues** -- the launcher whitelists `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`; if your compositor uses a non-default name (or doesn't export `WAYLAND_DISPLAY` at all), the launcher will silently drop Wayland passthrough. Find the real socket with `ls $XDG_RUNTIME_DIR/wayland-*` and re-export `WAYLAND_DISPLAY` accordingly.

**Containers not working** -- the host socket is not bound by default. Re-launch with `CURSOR_SANDBOX_BIND_CONTAINER_SOCKET=1 cursor` (see the Docker / Podman section for the security trade-off). The launcher's startup output will then say `Podman socket: bound` or `Docker socket: bound`. Once bound, your invocations need `--remote` (e.g., `podman --remote ps`).

**AppArmor errors (Ubuntu 23.10+)** -- if firejail fails with AppArmor-related messages, reload the firejail profile: `sudo apparmor_parser -r /etc/apparmor.d/firejail-default`.

## License

MIT -- see [LICENSE](LICENSE).
