#!/usr/bin/env bash
# Scenario 1: full apply from scratch.
#
# Empty $HOME, fresh checkout, one `./bootstrap.sh` run. Asserts the whole
# manifest actually ran and produced the deployment it claims: this platform's
# package manager set up where it belongs and nowhere else, every managed file
# linked individually, every managed directory real (never folded into the
# repository), the external nvim config cloned, the package manifest applied, a
# transcript on disk, and a login shell that sources the deployed profile
# cleanly.
#
# The package-manager half is the only part that differs by OS -- Homebrew in
# ~/.homebrew on macOS, the nix/flake.nix environment on Linux -- so those
# sections branch on $PLATFORM and everything else is asserted identically on
# both.

CURRENT_SCENARIO="01-fresh-apply"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/harness.sh"

sandbox_create
trap sandbox_destroy EXIT

printf 'sandbox: %s\n' "$SANDBOX"

section "preconditions: nothing is deployed yet"
assert_missing "no ~/.zshrc before bootstrap"      "$HOME/.zshrc"
assert_missing "no ~/.homebrew before bootstrap"   "$HOME/.homebrew"
assert_missing "no Nix environment before bootstrap" "$NIX_ENV"
# Recorded before bootstrap runs so the isolation check below can prove this
# run left any pre-existing system Homebrew alone.
opt_homebrew_state() {
  [ -d /opt/homebrew ] || { printf 'absent\n'; return; }
  find /opt/homebrew -maxdepth 1 2>/dev/null | sort | cksum
}
OPT_HOMEBREW_BEFORE="$(opt_homebrew_state)"
# Same idea for the login shell: recorded before the run so the assertion
# further down compares against reality rather than against an assumption.
LOGIN_SHELL_BEFORE="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
assert_missing "no ~/.config/nvim before bootstrap" "$HOME/.config/nvim"

repo_before="$(repo_tree_snapshot)"

section "run bootstrap.sh on a from-scratch account"
assert_true "bootstrap exits 0" run_bootstrap
cp "$BOOTSTRAP_OUT" "$SANDBOX/fresh.out"
out="$SANDBOX/fresh.out"

assert_file_has "reports completion" "$out" 'bootstrap complete'
assert_file_lacks "no step failed" "$out" 'ERROR: step failed'
# Derived from the manifest rather than listed here, so a step added to
# bootstrap-steps.json is covered without editing this file -- and, more to the
# point, so the LAST step cannot quietly stop running. This list used to stop at
# "install Brewfile packages", which is why nothing caught the runner feeding
# the manifest in on stdin: `brew bundle` ate the remainder, "wire docker CLI
# plugins" never ran, and the run still reported success.
# A skipped step still logs "==> <name> (skipped, ...)", so this matches either
# way; that a step did the right thing is asserted further down, per step.
while IFS= read -r step; do
  assert_file_has "ran step: $step" "$out" "==> ${step//[\[\]().*+?^$\\]/.}"
done < <(python3 -c '
import json, sys
for s in json.load(open(sys.argv[1])):
    print(s["name"])
' "$REPO/bootstrap-steps.json")

section "transcript"
log_file="$(find "$HOME/.local/state/dotfiles" -name 'setup-*.log' -type f 2>/dev/null | head -1)"
assert_true "transcript written under ~/.local/state/dotfiles" test -n "$log_file"
[ -n "$log_file" ] && assert_file_has "transcript records the steps" "$log_file" '==> stow dev profile'

section "the package manager for this platform, and only that one"
# bootstrap-steps.json gates its package-manager steps with `os`, so exactly
# one of these two branches should have run. Asserting the *other* one was
# skipped is the point: a gate that silently let both through would install
# Homebrew on Linux, and a gate that let neither through would produce a
# half-applied account that still reported success.
if [ "$PLATFORM" = darwin ]; then
  assert_file_has "the Linux steps were skipped as not-for-this-OS" "$out" \
    'install Nix \(single-user\) \(skipped, declared for linux'
else
  assert_file_has "the macOS steps were skipped as not-for-this-OS" "$out" \
    'install Homebrew into ~/\.homebrew \(skipped, declared for darwin'
  assert_file_lacks "brew was never invoked on Linux" "$BREW_CALL_LOG" '.'
  assert_missing "no Homebrew prefix was created on Linux" "$HOME/.homebrew"
fi

if [ "$PLATFORM" = linux ]; then
section "Nix environment (Linux)"
# The installer step is seeded by the harness rather than run (see
# sandbox_seed_nix), so what is asserted here is that the runner honoured the
# step's declared state and that everything downstream of it really happened.
assert_file_has "the installer step was skipped via its declared state" "$out" \
  'install Nix \(single-user\) \(skipped, already in the declared state\)'
assert_file_has "built from the repo flake, into the expected out-link" "$NIX_CALL_LOG" \
  "build --out-link $NIX_ENV path:$REPO/nix#default"
# The experimental-features flag is not decoration: on a fresh machine
# ~/.config/nix/nix.conf has not been stowed yet (stow is what this build
# produces), so without it on the command line the build fails outright.
assert_file_has "flakes were enabled on the command line, not via the stowed nix.conf" \
  "$NIX_CALL_LOG" '^--extra-experimental-features nix-command flakes build '
assert_true "the out-link exists and resolves" test -d "$NIX_ENV"
assert_true "the out-link is a symlink into the store" \
  bash -c '[ -L "$1" ] && case "$(readlink "$1")" in "$2"/*) exit 0 ;; *) exit 1 ;; esac' _ "$NIX_ENV" "$NIX_STORE_ROOT"
# Every package the flake declares has to be in the built environment: that is
# the whole contract between nix/flake.nix and the rest of the deployment, and
# stow in particular is what the very next bootstrap step runs.
while read -r pkg; do
  assert_true "flake package present in the environment: $pkg" test -x "$NIX_ENV/bin/$pkg"
done < <(sed -n '/paths = with pkgs;/,/^[[:space:]]*\];/p' "$REPO/nix/flake.nix" |
           sed -e 's/#.*$//' |
           sed -n -E 's/^[[:space:]]*(unstable\.)?([A-Za-z0-9_-]+)[[:space:]]*$/\2/p')
assert_true "stow, the thing the next step needs, came out of it" test -x "$NIX_ENV/bin/stow"
assert_true "and so did mise" test -x "$NIX_ENV/bin/mise"

# The login-shell steps are the only ones that touch state outside $HOME and
# /nix, so the suite must prove it never reaches them. Both are guarded by
# `skip_if: ! sudo -n true`, and the container's account has no sudo, so they
# skip -- and a skip must not look like a failure. If this ever stops holding,
# a CI run would rewrite the runner's /etc/shells and login shell.
assert_file_has "the /etc/shells step was skipped without sudo" "$out" \
  'register the pinned zsh as a valid login shell \(skipped, nothing to do\)'
assert_file_has "the chsh step was skipped without sudo" "$out" \
  "make the pinned zsh this account's login shell \\(skipped, nothing to do\\)"
assert_eq "the test account's login shell was not changed" \
  "$LOGIN_SHELL_BEFORE" "$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
# The flake is a manifest the root scripts apply, not a dotfile: stow must not
# deploy it. A ~/nix directory here would mean it drifted back into dev/.
assert_missing "the flake is not deployed into \$HOME" "$HOME/nix"

else
section "Homebrew isolation (macOS)"
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
fi

section "pinned tools: mise owns them, and owns them exclusively"
# The mise config is stowed like any other managed file (asserted below with
# the rest of the package); what matters here is that bootstrap asked mise to
# reconcile it, and that the two manifests do not both claim the same tool --
# a formula and a pin of the same name would race for PATH.
# Whichever package manager provided mise is the one whose shim recorded the
# call, so read the log belonging to this platform's stub.
if [ "$PLATFORM" = darwin ]; then MISE_SHIM_LOG="$BREW_SHIM_LOG"; else MISE_SHIM_LOG="$NIX_SHIM_LOG"; fi
assert_file_has "mise was asked to install the pinned tools" "$MISE_SHIM_LOG" '^mise install$'
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
  # Neither package manager may claim a name mise pins, on either platform:
  # both manifests ship to both machines, so a duplicate is a bug everywhere,
  # not only where it would currently bite.
  assert_file_lacks "not also declared in the Brewfile: $brewname" \
    "$REPO/dev/Brewfile" "^[[:space:]]*brew[[:space:]]+\"$brewname\""
  assert_file_lacks "not also declared in the Nix flake: $tool" \
    "$REPO/nix/flake.nix" "^[[:space:]]*(unstable\.)?$tool[[:space:]]*(#.*)?$"
  if [ "$PLATFORM" = darwin ]; then
    assert_file_lacks "not installed by brew either: $brewname" \
      "$HOME/.homebrew/bundled.txt" "^${brewname}$"
  else
    assert_missing "not installed by nix either: $tool" "$NIX_ENV/bin/$tool"
  fi
done < <(mise_tools)

# The Brewfile has a job left, and it is not CLI tools: the bootstrap pair,
# what mise has no backend for, the docker plugins, and casks.
assert_file_has "Brewfile still declares the bootstrap pair" "$REPO/dev/Brewfile" '^brew "stow"$'
assert_file_has "Brewfile still declares mise itself" "$REPO/dev/Brewfile" '^brew "mise"$'
assert_file_has "docker CLI plugins stay with Homebrew" "$REPO/dev/Brewfile" '^brew "docker-buildx"$'

# The Linux manifest carries the same job, and the same two bootstrap
# dependencies -- if either fell out of the flake, a fresh Linux machine would
# get as far as `stow: command not found`.
assert_file_has "the flake still declares stow" "$REPO/nix/flake.nix" '^[[:space:]]*stow[[:space:]]*(#.*)?$'
assert_file_has "the flake still declares mise" "$REPO/nix/flake.nix" '^[[:space:]]*unstable\.mise[[:space:]]*(#.*)?$'
# flake.lock is what makes the flake a pin rather than a moving target; without
# it committed, every machine resolves nixos-26.05 to whatever is current.
assert_exists "the flake is locked to an exact revision" "$REPO/nix/flake.lock"
assert_file_has "the lock names a nixpkgs revision" "$REPO/nix/flake.lock" '"rev": "[0-9a-f]{40}"'

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
assert_file_has "EDITOR is nvim"             "$zsh_out" '^EDITOR=nvim$'
assert_file_has "NVIM_APPNAME is set"        "$zsh_out" '^NVIM_APPNAME=nvim$'

if [ "$PLATFORM" = darwin ]; then
  assert_file_has "~/.homebrew/bin is on PATH" "$zsh_out" "^PATH=.*$HOME/\.homebrew/bin"
  assert_file_has "HOMEBREW_PREFIX is the isolated prefix" "$zsh_out" "^HOMEBREW_PREFIX=$HOME/.homebrew$"
  assert_file_lacks "no isolation tripwire warning" "$zsh_out" 'isolation may be broken'
  # The tripwire in .zprofile.d/50-homebrew-isolated.zsh warns when another
  # account's Homebrew prefix is writable from here. On the macOS runner
  # /opt/homebrew is present and writable by the CI user, so it must speak up;
  # if it is not, it must stay quiet. Asserting the behaviour the environment
  # actually calls for tests the tripwire in both directions instead of only
  # ever checking that it is silent.
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
else
  # 50-homebrew-isolated.zsh is gated on $OSTYPE. Before that guard existed it
  # ran `eval "$(~/.homebrew/bin/brew shellenv)"` unconditionally, which fails
  # on every single login shell on a machine with no ~/.homebrew -- so an empty
  # HOMEBREW_PREFIX here is the assertion that the guard is doing its job.
  assert_file_has "HOMEBREW_PREFIX is unset on Linux" "$zsh_out" '^HOMEBREW_PREFIX=$'
  assert_file_lacks "no Homebrew path leaked onto PATH" "$zsh_out" "^PATH=.*\.homebrew/bin"
  assert_file_lacks "the Homebrew snippet stayed quiet" "$zsh_out" 'isolation may be broken'

  # 45-nix.zsh is the Linux counterpart, and PATH order is the whole point:
  # the Nix environment supplies mise, so it has to precede the mise shims.
  assert_file_has "the Nix environment is on PATH" "$zsh_out" "^PATH=.*$NIX_ENV/bin"
  assert_file_has "nix itself is on PATH" "$zsh_out" "^PATH=.*$HOME/\.nix-profile/bin"
  assert_file_lacks "no dangling-environment warning" "$zsh_out" 'was garbage-collected'
  assert_file_lacks "no missing-environment warning" "$zsh_out" 'run ./reapply.sh to build'
fi

# Whatever provided them, the tools this account pins must resolve inside
# $HOME rather than to the distribution's or the system's copy -- that is what
# 55-mise.zsh's precedence tripwire exists to catch, and it is the one
# assertion that means the same thing on both platforms.
assert_file_lacks "no pinned tool is shadowed from outside \$HOME" "$zsh_out" 'is being shadowed'

section "the deployed sync script is the one on PATH"
assert_symlink_to "~/.local/bin/sync-external-repos is linked" \
  "$HOME/.local/bin/sync-external-repos" "$REPO/dev/.local/bin/sync-external-repos"
assert_true "and it is executable" test -x "$HOME/.local/bin/sync-external-repos"

finish
