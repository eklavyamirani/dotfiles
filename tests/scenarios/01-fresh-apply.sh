#!/usr/bin/env bash
# Scenario 1: full apply from scratch.
#
# Empty $HOME, fresh checkout, one `./bootstrap.sh` run. Asserts the whole
# manifest actually ran and produced the deployment it claims: Homebrew cloned
# into ~/.homebrew (and nowhere else), every managed file linked individually,
# every managed directory real (never folded into the repository), the external
# nvim config cloned, the Brewfile handed to `brew bundle`, a transcript on
# disk, and a login shell that sources the deployed profile cleanly.

CURRENT_SCENARIO="01-fresh-apply"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/harness.sh"

sandbox_create
trap sandbox_destroy EXIT

printf 'sandbox: %s\n' "$SANDBOX"

section "preconditions: nothing is deployed yet"
assert_missing "no ~/.zshrc before bootstrap"      "$HOME/.zshrc"
assert_missing "no ~/.homebrew before bootstrap"   "$HOME/.homebrew"
# Recorded before bootstrap runs so the isolation check below can prove this
# run left any pre-existing system Homebrew alone.
opt_homebrew_state() {
  [ -d /opt/homebrew ] || { printf 'absent\n'; return; }
  find /opt/homebrew -maxdepth 1 2>/dev/null | sort | cksum
}
OPT_HOMEBREW_BEFORE="$(opt_homebrew_state)"
assert_missing "no ~/.config/nvim before bootstrap" "$HOME/.config/nvim"

repo_before="$(repo_tree_snapshot)"

section "run bootstrap.sh on a from-scratch account"
assert_true "bootstrap exits 0" run_bootstrap
cp "$BOOTSTRAP_OUT" "$SANDBOX/fresh.out"
out="$SANDBOX/fresh.out"

assert_file_has "reports completion" "$out" 'bootstrap complete'
assert_file_lacks "no step failed" "$out" 'ERROR: step failed'
for step in \
  'install Homebrew into ~/.homebrew' \
  'load Homebrew into this shell' \
  'install stow and mise' \
  'prepare stow target directories' \
  'stow dev profile' \
  'sync external repos' \
  'install pinned tools (mise)' \
  'install Brewfile packages'
do
  assert_file_has "ran step: $step" "$out" "==> ${step//[\[\]().*+?^$\\]/.}"
done

section "transcript"
log_file="$(find "$HOME/.local/state/dotfiles" -name 'setup-*.log' -type f 2>/dev/null | head -1)"
assert_true "transcript written under ~/.local/state/dotfiles" test -n "$log_file"
[ -n "$log_file" ] && assert_file_has "transcript records the steps" "$log_file" '==> stow dev profile'

section "Homebrew isolation"
assert_true "~/.homebrew is a git checkout" test -d "$HOME/.homebrew/.git"
assert_true "brew is executable at ~/.homebrew/bin/brew" test -x "$HOME/.homebrew/bin/brew"
# A macOS runner (and any Mac with an admin Homebrew) already has
# /opt/homebrew; what matters is that this bootstrap did not create or write to
# it, not that it is absent. Compare before and after instead of asserting the
# machine is bare.
if [ "$OPT_HOMEBREW_BEFORE" = absent ]; then
  assert_missing "bootstrap did not create /opt/homebrew" /opt/homebrew
else
  assert_eq "bootstrap did not touch the pre-existing /opt/homebrew" \
    "$OPT_HOMEBREW_BEFORE" "$(opt_homebrew_state)"
fi
assert_missing "nothing installed to /usr/local/Homebrew" /usr/local/Homebrew
assert_file_has "brew install ran for stow and mise" "$BREW_CALL_LOG" '^install stow mise$'
assert_file_has "brew bundle used the repo Brewfile" "$BREW_CALL_LOG" "^bundle --file=$REPO/dev/Brewfile$"

section "Brewfile packages reached brew bundle"
while read -r pkg; do
  assert_file_has "Brewfile entry installed: $pkg" "$HOME/.homebrew/bundled.txt" "^${pkg}$"
done < <(sed -e 's/#.*$//' "$REPO/dev/Brewfile" | sed -n -E 's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p')
assert_file_lacks "commented-out casks were not installed" "$HOME/.homebrew/bundled.txt" '^(visual-studio-code|obsidian)$'

section "pinned tools: mise owns them, and owns them exclusively"
# The mise config is stowed like any other managed file (asserted below with
# the rest of the package); what matters here is that bootstrap asked mise to
# reconcile it, and that the two manifests do not both claim the same tool --
# a formula and a pin of the same name would race for PATH.
assert_file_has "mise was asked to install the pinned tools" "$BREW_SHIM_LOG" '^mise install$'
assert_true "the mise config was linked before mise ran" test -f "$HOME/.config/mise/config.toml"

MISE_CONFIG="$REPO/dev/.config/mise/config.toml"
# Tool names as declared, one per line (comments and the [tools] header out).
mise_tools() {
  sed -e 's/#.*$//' "$MISE_CONFIG" |
    sed -n -E 's/^[[:space:]]*([A-Za-z0-9_.-]+)[[:space:]]*=[[:space:]]*"([^"]+)".*/\1 \2/p'
}
# Homebrew formula name for a mise tool, where they differ.
brew_name_for() {
  case "$1" in
    github-cli) printf 'gh\n' ;;
    docker-cli) printf 'docker\n' ;;
    *)          printf '%s\n' "$1" ;;
  esac
}
while read -r tool version; do
  [ -n "$tool" ] || continue
  # Exact versions only: "latest", "lts", "3.12" or "~> 1.2" would reintroduce
  # exactly the drift this split exists to remove.
  assert_true "pinned exactly: $tool = $version" \
    bash -c 'printf %s "$1" | grep -Eq "^[0-9]+\.[0-9]+(\.[0-9]+)?[A-Za-z0-9.+-]*$"' _ "$version"
  brewname="$(brew_name_for "$tool")"
  assert_file_lacks "not also declared in the Brewfile: $brewname" \
    "$REPO/dev/Brewfile" "^[[:space:]]*brew[[:space:]]+\"$brewname\""
  assert_file_lacks "not installed by brew either: $brewname" \
    "$HOME/.homebrew/bundled.txt" "^${brewname}$"
done < <(mise_tools)

# The Brewfile has a job left, and it is not CLI tools: the bootstrap pair,
# what mise has no backend for, the docker plugins, and casks.
assert_file_has "Brewfile still declares the bootstrap pair" "$REPO/dev/Brewfile" '^brew "stow"$'
assert_file_has "Brewfile still declares mise itself" "$REPO/dev/Brewfile" '^brew "mise"$'
assert_file_has "docker CLI plugins stay with Homebrew" "$REPO/dev/Brewfile" '^brew "docker-buildx"$'

section "every managed file is linked back to the repository"
while read -r rel; do
  assert_symlink_to "linked: ~/$rel" "$HOME/$rel" "$REPO/dev/$rel"
done < <(package_files "$REPO/dev")

section "every managed directory is a real directory, never folded into the repo"
while read -r rel; do
  assert_real_dir "real dir: ~/$rel" "$HOME/$rel"
done < <(package_dirs "$REPO/dev")

section "stateful directories stay writable by their tools"
assert_true "~/.pi/agent accepts runtime state" \
  bash -c 'touch "$HOME/.pi/agent/session-state.json" && rm -f "$HOME/.pi/agent/session-state.json"'
assert_true "~/.config accepts a new tool config dir" \
  bash -c 'mkdir -p "$HOME/.config/some-new-tool" && rmdir "$HOME/.config/some-new-tool"'

section "external repos"
assert_true "nvim config cloned" test -d "$HOME/.config/nvim/.git"
assert_eq "nvim config is at the remote tip" \
  "$(origin_head nvim-config)" "$(git -C "$HOME/.config/nvim" rev-parse HEAD 2>/dev/null)"
assert_real_dir "~/.config/nvim is a real directory, not a stow link" "$HOME/.config/nvim"

section "the deploy never writes back into the repository"
assert_eq "repository tree is unchanged" "$repo_before" "$(repo_tree_snapshot)"
assert_eq "repository working tree is clean" "" "$(git -C "$REPO" status --porcelain)"

section "the deployed profile loads in zsh"
zsh_out="$SANDBOX/zprofile.out"
zsh_status=0
zsh -c 'source "$HOME/.zprofile"; printf "PATH=%s\nEDITOR=%s\nNVIM_APPNAME=%s\nHOMEBREW_PREFIX=%s\n" "$PATH" "$EDITOR" "$NVIM_APPNAME" "$HOMEBREW_PREFIX"' \
  >"$zsh_out" 2>&1 || zsh_status=$?
assert_eq "sourcing ~/.zprofile succeeds" "0" "$zsh_status"
assert_file_has "~/.local/bin is on PATH"    "$zsh_out" "^PATH=.*$HOME/\.local/bin"
assert_file_has "~/.homebrew/bin is on PATH" "$zsh_out" "^PATH=.*$HOME/\.homebrew/bin"
assert_file_has "EDITOR is nvim"             "$zsh_out" '^EDITOR=nvim$'
assert_file_has "NVIM_APPNAME is set"        "$zsh_out" '^NVIM_APPNAME=nvim$'
assert_file_has "HOMEBREW_PREFIX is the isolated prefix" "$zsh_out" "^HOMEBREW_PREFIX=$HOME/.homebrew$"
assert_file_lacks "no isolation tripwire warning" "$zsh_out" 'isolation may be broken'
# The tripwire in .zprofile.d/50-homebrew-isolated.zsh warns when another
# account's Homebrew prefix is writable from here. In the Linux container none
# exists, so it must stay quiet; on the macOS runner /opt/homebrew is present
# and writable by the CI user, so it must speak up. Asserting the behaviour the
# environment actually calls for tests the tripwire in both directions instead
# of only ever checking that it is silent.
foreign_writable=0
for foreign_prefix in /opt/homebrew /usr/local/Homebrew; do
  [ -d "$foreign_prefix" ] && [ -w "$foreign_prefix" ] && foreign_writable=1
done
if [ "$foreign_writable" = 1 ]; then
  assert_file_has "tripwire warns that another Homebrew is writable" \
    "$zsh_out" 'should stay isolated'
else
  assert_file_lacks "no other Homebrew is writable" "$zsh_out" 'should stay isolated'
fi

section "the deployed sync script is the one on PATH"
assert_symlink_to "~/.local/bin/sync-external-repos is linked" \
  "$HOME/.local/bin/sync-external-repos" "$REPO/dev/.local/bin/sync-external-repos"
assert_true "and it is executable" test -x "$HOME/.local/bin/sync-external-repos"

finish
