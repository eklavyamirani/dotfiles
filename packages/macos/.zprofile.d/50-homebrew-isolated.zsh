# Isolated Homebrew for this (non-admin) dev account: installed to ~/.homebrew
# via git clone, entirely separate from any admin account's /opt/homebrew or
# /usr/local Homebrew. No sudo required to install or use.
#
# This file lives in packages/macos/, so it is only ever stowed on macOS and
# needs no $OSTYPE guard -- its location is the guard. It used to carry one,
# back when a single package shipped every file to every machine: running
# `eval "$(~/.homebrew/bin/brew shellenv)"` on a box with no ~/.homebrew fails
# on every single login shell. That is also why stow-packages.sh refuses to
# deploy another platform's package -- the guard is gone, so a stray link here
# would break the shell rather than merely be inert.
#
# Numbered before 55-mise.zsh (in packages/unix/, shared) because Homebrew is
# what puts mise on PATH here. packages/linux/.zprofile.d/45-nix.zsh plays the
# same role on the other machine from its own package; the numbers still sort
# correctly because stow merges every package's .zprofile.d/ into a single
# ~/.zprofile.d/.
eval "$(~/.homebrew/bin/brew shellenv)"

# Add Homebrew's completions to the shell path
if type brew &>/dev/null; then
  FPATH=$(brew --prefix)/share/zsh/site-functions:$FPATH
  autoload -Uz compinit
  compinit
fi

# Pin 'brew' to this account's Homebrew regardless of PATH ordering (defense in
# depth on top of the tripwire below — functions can't be shadowed by PATH the
# way plain commands can, only by explicit 'command brew').
brew() { "$HOME/.homebrew/bin/brew" "$@"; }

# --- Homebrew isolation tripwire ---
# Warns (doesn't block) if the real 'brew' binary on PATH (ignoring the pinning
# function above) ever resolves outside this account's home directory. That
# would mean some other Homebrew install (an admin account's /opt/homebrew or
# /usr/local, for example) has leaked onto this account's PATH.
_brew_isolation_check() {
  local resolved="$(whence -p brew 2>/dev/null)"
  if [[ -n "$resolved" && "$resolved" != "$HOME"/* ]]; then
    print -P "%F{red}⚠ WARNING: real 'brew' on PATH resolves to $resolved, outside \$HOME. Homebrew isolation may be broken.%f"
  fi
  local other_prefix
  for other_prefix in /opt/homebrew /usr/local/Homebrew; do
    if [[ -d "$other_prefix" && -w "$other_prefix" ]]; then
      print -P "%F{red}⚠ WARNING: $other_prefix is writable by this account. Another account's Homebrew should stay isolated.%f"
    fi
  done
}
_brew_isolation_check
