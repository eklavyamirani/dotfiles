# Nix: this account's package manager on Linux, and the counterpart to
# 50-homebrew-isolated.zsh on macOS. Inert on a Mac -- there, Homebrew in
# ~/.homebrew plays this role and none of the paths below exist.
#
# Numbered 45 so it lands BEFORE 55-mise.zsh: on Linux mise itself comes out
# of the Nix environment (nix/flake.nix declares it), so mise has to be on
# PATH before that snippet can activate it. Same constraint that puts Homebrew
# at 50 on macOS, one manager earlier.
# Single-user install: /nix is owned by this account outright, so nothing
# here needs sudo. The installer is run with --no-modify-profile precisely
# so that this file, and not an appended line in a stow-managed ~/.zshrc,
# is what loads it.
if [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
  source "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# The realised flake environment (stow, mise, git, tree, zsh). Prepended,
# because the whole point of pinning is that these outrank whatever the
# distribution happens to ship in /usr/bin.
_nix_env="$HOME/.local/state/dotfiles/nix-env"
if [[ -d "$_nix_env/bin" ]]; then
  export PATH="$_nix_env/bin:$PATH"

  # Completions for what Nix installed, mirroring the FPATH block that
  # 50-homebrew-isolated.zsh runs for brew's site-functions on macOS.
  if [[ -d "$_nix_env/share/zsh/site-functions" ]]; then
    FPATH="$_nix_env/share/zsh/site-functions:$FPATH"
    autoload -Uz compinit
    compinit
  fi
fi

# --- Nix environment tripwire ---
# Sibling of the Homebrew isolation tripwire in 50-* and the mise precedence
# one in 55-*: warn, never block. A missing or dangling out-link means the
# environment was garbage-collected or never built, and the symptom
# otherwise shows up much later as `stow: command not found` halfway through
# a reapply.
if [[ -L "$_nix_env" && ! -e "$_nix_env" ]]; then
  print -P "%F{red}⚠ WARNING: $_nix_env is a dangling link — the Nix environment was garbage-collected. Run ./reapply.sh to rebuild it.%f"
elif [[ ! -e "$_nix_env" ]] && command -v nix >/dev/null 2>&1; then
  print -P "%F{yellow}⚠ WARNING: Nix is installed but $_nix_env does not exist — run ./reapply.sh to build the declared environment.%f"
fi

unset _nix_env
