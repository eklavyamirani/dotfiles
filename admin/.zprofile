# Minimal admin-account profile. This account intentionally has no dev
# tooling installed (no Homebrew, no language runtimes) — all development
# happens in an isolated non-admin account. Use `dev-shell` below to switch.

export EDITOR='vi'

# Increase history size. Allow 32³ entries; the default is 500.
export HISTSIZE='32768';
export HISTFILESIZE="${HISTSIZE}";
# Omit duplicates and commands that begin with a space from history.
export HISTCONTROL='ignoreboth';

# Switch into the isolated dev account (set DEV_USER if it's not "dev").
dev-shell() {
  su - "${DEV_USER:-dev}"
}
