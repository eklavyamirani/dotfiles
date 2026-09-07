# mise: version manager for this account's CLI tools and language runtimes.
# Installs entirely in userspace (~/.local/share/mise) -- no sudo either way.
#
# Numbered after both package-manager snippets on purpose: mise is installed
# by whichever one this machine uses -- Homebrew on macOS (see Brewfile, 50-)
# or Nix on Linux (see nix/flake.nix, 45-) -- so that manager's bin
# directory must already be on PATH here. Being *after* them also matters for
# precedence: `mise activate` prepends the active tool paths, so a pinned
# nvim/gh/rg wins over a brew formula or nixpkgs package of the same name that
# happens to still be installed.
eval "$(mise activate zsh)"

# Shims as a fallback, appended (not prepended) so activate keeps priority.
# `mise activate` only rewrites PATH inside shells that source this file; a
# process started outside one -- a GUI launcher, a LaunchAgent -- would
# otherwise see none of the pinned tools.
if [[ -d "$HOME/.local/share/mise/shims" ]]; then
  export PATH="$PATH:$HOME/.local/share/mise/shims"
fi

# --- mise precedence tripwire ---
# Companion to the Homebrew isolation tripwire in 50-*. That one checks where
# `brew` comes from; this one checks that tools this account pins actually
# resolve to the pinned copy, rather than to /usr/bin (macOS ships its own
# git, a Linux distribution ships its own nvim/tmux/rg, and an older install
# may linger either way). The test is "inside \$HOME", which holds for both
# machines: mise, Homebrew and the Nix out-link all live under it, while
# /usr/bin and /opt never do. Warns only -- a tool that is simply not
# installed yet is not an error.
_mise_precedence_check() {
  local tool resolved
  for tool in nvim rg gh tmux; do
    resolved="$(whence -p "$tool" 2>/dev/null)" || continue
    [[ -n "$resolved" ]] || continue
    if [[ "$resolved" != "$HOME"/* ]]; then
      print -P "%F{yellow}⚠ WARNING: '$tool' resolves to $resolved, outside \$HOME — the version pinned in ~/.config/mise/config.toml is being shadowed.%f"
    fi
  done
}
_mise_precedence_check
