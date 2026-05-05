# Firejail security profile for Cursor AppImage
#
# Used by cursor-sandbox.sh.  Workspace and AppImage paths are added
# via command-line --whitelist arguments at launch time.

# --- Noblacklist (must come before includes) ---
# Prevent disable-*.inc from blacklisting Cursor's own directories
noblacklist ${HOME}/.cursor
noblacklist ${HOME}/.cursor-server
noblacklist ${HOME}/.config/Cursor
noblacklist ${HOME}/.local/share/Cursor
noblacklist ${HOME}/.cache/Cursor
noblacklist ${HOME}/.gitconfig

# --- Standard blacklist includes ---
# These block access to sensitive dirs: ~/.ssh, ~/.gnupg, ~/.pki,
# password managers, other applications' data, etc.
include disable-common.inc
include disable-programs.inc

# --- Whitelist: only these $HOME paths are visible ---
whitelist ${HOME}/.cursor
whitelist ${HOME}/.cursor-server
whitelist ${HOME}/.config/Cursor
whitelist ${HOME}/.local/share/Cursor
whitelist ${HOME}/.cache/Cursor

# Git config (visible but read-only)
whitelist ${HOME}/.gitconfig
read-only ${HOME}/.gitconfig

# --- Security hardening ---

# Drop all Linux capabilities
caps.drop all

# Enable seccomp syscall filtering
seccomp

# Prevent privilege escalation
noroot
nonewprivs

# Drop supplementary groups
nogroups

# --- Network ---
# Allow network (needed for LSP, extensions, AI features)
# Restrict to common protocols only
protocol unix,inet,inet6,netlink

# --- Filesystem isolation ---

# Isolated /tmp (Cursor can't see host /tmp)
private-tmp

# Pre-create directories Cursor expects in /tmp
mkdir /tmp/.terminals

# Isolated /dev (only null, zero, random, urandom, tty, dri, snd, etc.)
# GPU (/dev/dri) and audio (/dev/snd) are included automatically
private-dev

# --- Disable unnecessary features ---
notv
novideo
