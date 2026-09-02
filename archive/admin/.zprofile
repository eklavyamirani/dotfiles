# Minimal admin-account profile. This account intentionally has no dev
# tooling installed (no Homebrew, no language runtimes) — all development
# happens in an isolated non-admin account. Use `dev-shell` below to switch.

export EDITOR='vi'

# Increase zsh history size (in memory and persisted to $HISTFILE).
# Allow 32³ entries; the default is 500.
export HISTSIZE='32768';
export SAVEHIST="${HISTSIZE}";
# Omit duplicates and commands that begin with a space from history.
export HISTCONTROL='ignoreboth';

# Switch into the isolated dev account (set DEV_USER if it's not "claude").
#
# Uses ssh, not su -- su keeps the dev shell as a descendant of THIS
# Terminal.app process (owned by the admin account), which lets any process
# running as the dev user send unauthenticated AppleScript/Apple Events back
# to control this admin-owned Terminal.app (macOS resolves the "responsible
# process" by walking up the ancestry chain, so it's treated as self-control
# rather than app-to-app automation -- no permission prompt, no TCC gate).
# Concretely: `osascript -e 'tell application "Terminal" to do script
# "whoever"'` run from a su'd dev shell executes as the ADMIN account, a
# full privilege escalation out of the isolated account. ssh forks a fresh
# process tree (via sshd) with no Terminal.app ancestor, closing this off
# entirely. Requires Remote Login enabled and restricted to the dev user
# (System Settings > General > Sharing > Remote Login), and a key added to
# the dev account's ~/.ssh/authorized_keys.
dev-shell() {
  ssh -t "${DEV_USER:-claude}@127.0.0.1"
}
