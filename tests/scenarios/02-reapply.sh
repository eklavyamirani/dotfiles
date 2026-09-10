#!/usr/bin/env bash
# Scenario 2: re-apply new changes onto an already-configured account.
#
# The fresh-machine path is bootstrap.sh (scenario 1). This scenario covers the
# path a user actually takes afterwards -- `git pull && ./reapply.sh` -- so it
# drives reapply.sh, not bootstrap.sh, for every run after the baseline.
#
# It starts from the state scenario 1 produces, then does what really happens:
# the repository gains new snippets, new nested config directories, an edited
# managed file, a new Brewfile entry and a new external repo, while the external
# repo's remote moves forward. On top of that it exercises the reconciliation
# reapply.sh exists for and bootstrap cannot do: pruning links stranded by an
# upstream rename, reporting package-manager drift, removing undeclared
# packages only when asked, and moving a conflicting real file aside instead of
# clobbering it.
#
# The package-manager half branches on $PLATFORM, matching the branch
# reapply.sh itself takes: on macOS drift means the Brewfile versus what brew
# has installed, and pruning is opt-in via --prune; on Linux the environment is
# rebuilt whole from manifests/linux/flake.nix, so a deleted line is already a removal and
# drift is a store-path comparison. Everything else -- stow, external repos,
# mise, backups, the rename case -- is asserted identically on both.

CURRENT_SCENARIO="02-reapply"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/harness.sh"

sandbox_create
trap sandbox_destroy EXIT

printf 'sandbox: %s\n' "$SANDBOX"

# --------------------------------------------------------------------------
section "baseline: apply once so there is an existing configuration"
# --------------------------------------------------------------------------
assert_true "initial bootstrap exits 0" run_bootstrap
assert_true "baseline deployed ~/.zshrc" test -L "$HOME/.zshrc"
assert_true "baseline cloned the nvim config" test -d "$HOME/.config/nvim/.git"

links_before="$(home_link_snapshot)"
zshrc_inode_before="$(inode "$HOME/.zshrc")"
nvim_root_before="$(git -C "$HOME/.config/nvim" rev-list --max-parents=0 HEAD)"
if [ "$PLATFORM" = macos ]; then
  brew_clone_before="$(git -C "$HOME/.homebrew" rev-parse HEAD)"
else
  nix_env_before="$(readlink "$NIX_ENV")"
fi

# User state that lives in stow-managed directories must survive a re-apply.
printf '{"session":"keep me"}\n' >"$HOME/.pi/agent/runtime-state.json"

# --------------------------------------------------------------------------
section "change the configuration the way a real update would"
# --------------------------------------------------------------------------
# A new profile snippet in an existing managed directory.
cat >"$REPO/packages/unix/.zprofile.d/40-ci-added-snippet.zsh" <<'EOF'
export DOTFILES_CI_ADDED_SNIPPET=1
EOF

# A new file in a new *nested* managed directory (exercises prepare-stow-targets
# on a rerun: without it, stow would fold ~/.claude/skills/ci-demo into the repo).
mkdir -p "$REPO/packages/common/.claude/skills/ci-demo"
printf '# CI demo skill\n' >"$REPO/packages/common/.claude/skills/ci-demo/SKILL.md"

# A new top-level managed directory.
mkdir -p "$REPO/packages/common/.newtool"
printf 'answer = 42\n' >"$REPO/packages/common/.newtool/config.ini"

# An edit to an already-deployed file.
printf '\n# added by the CI reapply scenario\nexport DOTFILES_CI_ZSHRC_EDIT=1\n' >>"$REPO/packages/unix/.zshrc"

# A new package in this platform's manifest. Both are appended regardless of
# which one this run will apply -- a real commit would ship both files too, and
# it keeps the repository state identical on the two runners.
printf '\nbrew "jq"           # added by the CI reapply scenario\n' >>"$REPO/manifests/macos/Brewfile"
python3 - "$REPO/manifests/linux/flake.nix" <<'EOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
marker = "            zsh # the login shell these dotfiles configure\n"
assert marker in s, "flake.nix package list no longer matches what this scenario patches"
p.write_text(s.replace(marker, marker + "            jq # added by the CI reapply scenario\n"))
EOF

# A second external repo in the manifest, plus a new upstream commit in the
# first one, so this run both clones and fast-forwards.
origin_new ci-extra-repo
git config --global "url.file://$ORIGINS/ci-extra-repo.insteadOf" 'https://github.com/eklavyamirani/ci-extra-repo'
python3 - "$REPO/packages/common/.config/external-repos.json" <<'EOF'
import json, sys
path = sys.argv[1]
entries = json.load(open(path))
entries.append({
    "repo": "https://github.com/eklavyamirani/ci-extra-repo",
    "local_dir": "~/.local/share/ci-extra-tool",
    "purpose": "second external repo, added by the CI reapply scenario",
    "branch": None,
    "git_options": [],
})
json.dump(entries, open(path, "w"), indent=2)
EOF
origin_commit nvim-config init.lua '-- upstream moved forward'
nvim_target="$(origin_head nvim-config)"

git -C "$REPO" add -A
git -C "$REPO" commit --quiet -m 'CI: new snippet, new dirs, new Brewfile entry, new external repo'
repo_after_change="$(repo_tree_snapshot)"
bundle_calls_before="$(grep -c '^bundle --file' "$BREW_CALL_LOG")"
nix_builds_before="$(grep -c ' build --out-link ' "$NIX_CALL_LOG")"

# --------------------------------------------------------------------------
section "re-apply onto the existing configuration"
# --------------------------------------------------------------------------
assert_true "reapply exits 0" run_reapply
out="$REAPPLY_OUT"
assert_file_has "reports completion" "$out" 're-apply complete'
assert_file_has "prints a plan before acting" "$out" '^\[[^]]*\] PLAN$'
assert_file_has "logs its transcript path" "$out" 'transcript: .*/reapply-[0-9]+-[0-9]+\.log'

section "every reconcile step runs"
assert_file_has "stow re-ran" "$out" '==> stow -R common unix'
assert_file_has "external repo sync ran" "$out" '==> sync-external-repos'
if [ "$PLATFORM" = macos ]; then
  assert_file_has "brew bundle ran" "$out" '==> brew bundle'
  assert_file_has "docker cli plugins were wired" "$out" '==> link docker cli plugins'
  assert_file_lacks "reapply does not reinstall Homebrew" "$out" 'install Homebrew'
  assert_eq "existing ~/.homebrew checkout untouched" \
    "$brew_clone_before" "$(git -C "$HOME/.homebrew" rev-parse HEAD)"
else
  assert_file_has "the Nix environment was rebuilt" "$out" '==> nix build '
  assert_file_lacks "reapply does not run brew on Linux" "$out" '==> brew bundle'
  assert_file_lacks "and does not wire Homebrew's docker plugins on Linux" \
    "$out" '==> link docker cli plugins'
  assert_file_lacks "reapply does not reinstall Nix" "$out" 'install Nix'
fi

section "new configuration is deployed"
assert_symlink_to "new snippet linked" \
  "$HOME/.zprofile.d/40-ci-added-snippet.zsh" "$REPO/packages/unix/.zprofile.d/40-ci-added-snippet.zsh"
assert_symlink_to "new nested file linked" \
  "$HOME/.claude/skills/ci-demo/SKILL.md" "$REPO/packages/common/.claude/skills/ci-demo/SKILL.md"
assert_real_dir "new nested directory is real, not folded" "$HOME/.claude/skills/ci-demo"
assert_symlink_to "new top-level file linked" \
  "$HOME/.newtool/config.ini" "$REPO/packages/common/.newtool/config.ini"
assert_real_dir "new top-level directory is real, not folded" "$HOME/.newtool"
assert_true "new snippet is picked up by the profile loader" \
  bash -c 'zsh -c "source \"$HOME/.zprofile\"; [ \"\$DOTFILES_CI_ADDED_SNIPPET\" = 1 ]"'

section "existing deployment is left alone"
assert_eq "~/.zshrc is still the same link (not replaced)" \
  "$zshrc_inode_before" "$(inode "$HOME/.zshrc")"
assert_file_has "edits to a managed file show through the link" "$HOME/.zshrc" '^export DOTFILES_CI_ZSHRC_EDIT=1$'
assert_true "user state in a managed directory survives" test -f "$HOME/.pi/agent/runtime-state.json"
assert_file_has "user state contents survive" "$HOME/.pi/agent/runtime-state.json" 'keep me'
assert_eq "no previously deployed link was dropped or repointed" \
  "$links_before" "$(home_link_snapshot | grep -v -e '40-ci-added-snippet' -e 'ci-demo/SKILL.md' -e '.newtool/config.ini')"

section "external repos: fast-forward the existing clone, clone the new one"
assert_file_has "existing clone was pulled, not re-cloned" "$out" 'already cloned, pulling latest'
assert_eq "existing clone kept its history" \
  "$nvim_root_before" "$(git -C "$HOME/.config/nvim" rev-list --max-parents=0 HEAD)"
assert_eq "existing clone fast-forwarded to the new tip" \
  "$nvim_target" "$(git -C "$HOME/.config/nvim" rev-parse HEAD)"
assert_true "newly listed repo was cloned" test -d "$HOME/.local/share/ci-extra-tool/.git"
assert_eq "newly listed repo is at its tip" \
  "$(origin_head ci-extra-repo)" "$(git -C "$HOME/.local/share/ci-extra-tool" rev-parse HEAD 2>/dev/null)"

if [ "$PLATFORM" = macos ]; then
section "new Brewfile entry is installed"
assert_file_has "reapply planned the missing package" "$out" 'brew bundle will install declared-but-absent'
assert_file_has "brew bundle saw the new entry" "$HOME/.homebrew/bundled.txt" '^jq$'
assert_eq "brew bundle ran exactly once more" \
  "$((bundle_calls_before + 1))" "$(grep -c '^bundle --file' "$BREW_CALL_LOG")"
else
section "new flake entry is installed"
# The drift check reads the manifest, so editing manifests/linux/flake.nix must be enough
# on its own: the plan names the change before acting, and the rebuild moves
# the out-link to a different store path.
assert_file_has "reapply planned the rebuild" "$out" 'rebuild the Nix environment'
assert_file_has "the plan showed what it was rebuilding from" "$out" 'from: '
assert_true "the new package is in the environment" test -x "$NIX_ENV/bin/jq"
assert_eq "nix build ran exactly once more" \
  "$((nix_builds_before + 1))" "$(grep -c ' build --out-link ' "$NIX_CALL_LOG")"
assert_false "the out-link moved to a new store path" \
  test "$nix_env_before" = "$(readlink "$NIX_ENV")"
fi

section "runtimes and docker plugins are reconciled too"
if [ "$PLATFORM" = macos ]; then MISE_SHIM_LOG="$BREW_SHIM_LOG"; else MISE_SHIM_LOG="$NIX_SHIM_LOG"; fi
assert_file_has "mise was asked to install the pinned runtimes" "$MISE_SHIM_LOG" '^mise install$'
if [ "$PLATFORM" = macos ]; then
  for plugin in docker-buildx docker-compose; do
    assert_symlink_to "docker plugin wired: $plugin" \
      "$HOME/.docker/cli-plugins/$plugin" "$HOME/.homebrew/bin/$plugin"
  done
  assert_missing "the docker binary itself is not linked as a plugin" \
    "$HOME/.docker/cli-plugins/docker"
else
  # The plugins are Homebrew formulae; on Linux the step is gated off entirely,
  # so nothing should have been wired into the docker plugin directory.
  assert_missing "no docker plugin directory is created on Linux" \
    "$HOME/.docker/cli-plugins/docker-buildx"
fi

section "re-apply still does not write into the repository"
assert_eq "repository tree unchanged by the re-apply" "$repo_after_change" "$(repo_tree_snapshot)"
assert_eq "repository working tree is clean" "" "$(git -C "$REPO" status --porcelain)"

# --------------------------------------------------------------------------
section "a second run with nothing changed is a no-op"
# --------------------------------------------------------------------------
links_settled="$(home_link_snapshot)"
assert_true "repeat reapply exits 0" run_reapply
assert_eq "deployed links are byte-identical" "$links_settled" "$(home_link_snapshot)"
assert_file_has "reports no dangling links to remove" "$REAPPLY_OUT" 'no dangling symlinks to remove'
if [ "$PLATFORM" = macos ]; then
  assert_file_has "reports no Homebrew drift" "$REAPPLY_OUT" 'no Homebrew drift'
else
  # The point of the drift comparison: an unchanged manifest must evaluate to
  # the store path already linked, so a no-op run says so instead of rebuilding.
  assert_file_has "reports no Nix drift" "$REAPPLY_OUT" 'no Nix drift'
  assert_file_lacks "and did not rebuild" "$REAPPLY_OUT" 'rebuild the Nix environment'
fi
assert_eq "nvim clone stays at the same commit" \
  "$nvim_target" "$(git -C "$HOME/.config/nvim" rev-parse HEAD)"
assert_eq "repository still clean" "" "$(git -C "$REPO" status --porcelain)"

# --------------------------------------------------------------------------
section "a file renamed upstream leaves no dangling link behind"
# --------------------------------------------------------------------------
# The reason reapply.sh exists. `stow -R` unstows using the package's CURRENT
# contents, so a renamed file's old link survives, pointing at nothing -- and
# .zprofile globs .zprofile.d/*.zsh, so one stale link breaks every new shell.
git -C "$REPO" mv packages/unix/.zprofile.d/40-ci-added-snippet.zsh packages/unix/.zprofile.d/45-ci-renamed-snippet.zsh
git -C "$REPO" commit --quiet -m 'CI: rename a snippet, as an upstream change would'

assert_true "link to the pre-rename name still exists before reapply" \
  test -L "$HOME/.zprofile.d/40-ci-added-snippet.zsh"
assert_true "reapply after a rename exits 0" run_reapply
assert_file_has "reports the stale link it removed" "$REAPPLY_OUT" \
  'removed dangling link: .*/\.zprofile\.d/40-ci-added-snippet\.zsh'
assert_missing "the stale link is gone" "$HOME/.zprofile.d/40-ci-added-snippet.zsh"
assert_symlink_to "the renamed file is linked under its new name" \
  "$HOME/.zprofile.d/45-ci-renamed-snippet.zsh" "$REPO/packages/unix/.zprofile.d/45-ci-renamed-snippet.zsh"
assert_true "a login shell still works after the rename" \
  bash -c 'zsh -c "source \"$HOME/.zprofile\"; [ \"\$DOTFILES_CI_ADDED_SNIPPET\" = 1 ]"'

# --------------------------------------------------------------------------
section "a whole directory vanishing upstream is still reclaimed"
# --------------------------------------------------------------------------
# The rename case above only removes a FILE, so the link's parent directory
# still exists and resolving the target through it works. Splitting the single
# `dev` package into packages/{common,unix,macos,linux} deleted a whole
# directory, and every deployed link's parent went with it -- at which point
# the `cd` used to resolve the target failed, the scan skipped those links
# entirely, and stow then reported them as conflicts that the backup step
# refused to move (they are symlinks, not real files). The re-apply had no way
# to make progress. This is that shape, in miniature.
git -C "$REPO" mv packages/common/.newtool packages/common/.newtool-renamed
git -C "$REPO" commit --quiet -m 'CI: move a whole managed directory, as the package split did'

assert_true "the link into the now-missing directory still exists" \
  test -L "$HOME/.newtool/config.ini"
assert_false "and its target really is gone" test -e "$HOME/.newtool/config.ini"
assert_true "reapply after a directory move exits 0" run_reapply
assert_file_has "reports the stale link it removed" "$REAPPLY_OUT" \
  'removed dangling link: .*/\.newtool/config\.ini'
assert_missing "the stale link is gone" "$HOME/.newtool/config.ini"
assert_symlink_to "the moved file is linked under its new path" \
  "$HOME/.newtool-renamed/config.ini" "$REPO/packages/common/.newtool-renamed/config.ini"

section "the plan describes the outcome, not stow's scratch work"
# stow's dry run narrates actions it later cancels, and the
# "(reverts previous action)" marker lands on the CANCELLING line, not the
# cancelled one. With several packages contributing to one directory it
# proposes folding ~/.zprofile.d into a single link into one package, reverts
# that twice, then settles on a real directory. Reporting the phantom folds
# told the user their entire snippet directory was about to collapse. The plan
# is what gets approved, so it must not contain actions that never happen.
assert_true "reapply exits 0 on a settled tree" run_reapply --dry-run
assert_file_has "a settled tree plans no new links" "$REAPPLY_OUT" 'no new links to create'
assert_file_lacks "no phantom fold of the snippet directory" "$REAPPLY_OUT" \
  'LINK: \.zprofile\.d =>'
assert_real_dir "and it is still a real directory" "$HOME/.zprofile.d"

section "links that are not this repository's business are left alone"
mkdir -p "$HOME/.zprofile.d"
ln -sfn /nowhere/at/all.zsh "$HOME/.zprofile.d/99-foreign.zsh"
assert_true "reapply exits 0 with a foreign dangling link present" run_reapply
assert_true "foreign dangling link survives" test -L "$HOME/.zprofile.d/99-foreign.zsh"
assert_file_lacks "reapply did not claim to remove it" "$REAPPLY_OUT" '99-foreign'
rm -f "$HOME/.zprofile.d/99-foreign.zsh"

# --------------------------------------------------------------------------
# Drift: what is installed but not declared. The two managers answer this
# question in structurally different ways, so the sections are separate rather
# than forced into one shape.
#
#   macOS: `brew install` mutates a shared prefix, so an undeclared package
#          lingers until something removes it -- hence reporting, and --prune.
#   Linux: the environment is rebuilt whole from the flake, so "installed but
#          not declared" cannot persist: dropping the line is the removal.
#          There is nothing to prune, and no --prune to test.
# --------------------------------------------------------------------------
if [ "$PLATFORM" = macos ]; then
section "WezTerm cask drift is reported and repaired"
"$HOME/.homebrew/bin/brew" uninstall --cask wezterm >/dev/null 2>&1
rmdir "$HOME/Applications/WezTerm.app"
assert_true "reapply reinstalls a missing WezTerm cask" run_reapply
assert_file_has "missing WezTerm is reported" "$REAPPLY_OUT" '^ +wezterm$'
assert_file_has "WezTerm is registered again" "$HOME/.homebrew/bundled-casks.txt" '^wezterm$'
assert_true "reapply restores the app in the account" test -d "$HOME/Applications/WezTerm.app"
cp "$REPO/manifests/macos/Brewfile" "$SANDBOX/Brewfile.wezterm"
sed '/^cask "wezterm"$/d' "$SANDBOX/Brewfile.wezterm" >"$REPO/manifests/macos/Brewfile"
assert_true "reapply reports an undeclared WezTerm" run_reapply --dry-run
assert_file_has "undeclared cask drift is reported" "$REAPPLY_OUT" 'DRIFT: 1 package\(s\) installed but not declared'
assert_file_has "undeclared WezTerm is named" "$REAPPLY_OUT" '^ +wezterm$'
cp "$SANDBOX/Brewfile.wezterm" "$REPO/manifests/macos/Brewfile"

section "a package installed out of band is reported, and removed only on --prune"
# --------------------------------------------------------------------------
"$HOME/.homebrew/bin/brew" install straggler >/dev/null 2>&1

assert_true "reapply exits 0 with drift present" run_reapply
assert_file_has "drift is reported" "$REAPPLY_OUT" 'DRIFT: 1 package\(s\) installed but not declared'
assert_file_has "names the undeclared package" "$REAPPLY_OUT" '^ +straggler$'
assert_file_has "points at the fix" "$REAPPLY_OUT" 'rerun with --prune'
assert_file_has "still installed: drift alone never removes" "$HOME/.homebrew/installed.txt" '^straggler$'

assert_true "reapply --prune exits 0" run_reapply --prune
assert_file_has "announces the uninstall" "$REAPPLY_OUT" 'UNINSTALL 1 package\(s\)'
assert_file_has "uninstalled it" "$HOME/.homebrew/uninstalled.txt" '^straggler$'
assert_file_lacks "no longer installed" "$HOME/.homebrew/installed.txt" '^straggler$'
assert_missing "its shim is gone" "$HOME/.homebrew/bin/straggler"

section "declared packages are never pruned"
while read -r pkg; do
  assert_file_lacks "declared package not uninstalled: $pkg" \
    "$HOME/.homebrew/uninstalled.txt" "^${pkg}$"
done < <(sed -e 's/#.*$//' "$REPO/manifests/macos/Brewfile" |
           sed -n -E 's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p' | head -5)

# --------------------------------------------------------------------------
section "--prune refuses to act on a Brewfile it cannot read"
# --------------------------------------------------------------------------
# An empty or unparseable manifest makes every installed package look
# undeclared. Pruning on that would wipe the account, so it must refuse.
"$HOME/.homebrew/bin/brew" install another-straggler >/dev/null 2>&1
installed_before_guard="$(sort "$HOME/.homebrew/installed.txt")"
cp "$REPO/manifests/macos/Brewfile" "$SANDBOX/Brewfile.bak"
: >"$REPO/manifests/macos/Brewfile"

assert_false "reapply --prune exits non-zero on an empty Brewfile" run_reapply --prune
assert_file_has "says why it refused" "$REAPPLY_OUT" 'refusing to prune'
assert_eq "nothing was uninstalled" \
  "$installed_before_guard" "$(sort "$HOME/.homebrew/installed.txt")"

cp "$SANDBOX/Brewfile.bak" "$REPO/manifests/macos/Brewfile"
run_reapply --prune >/dev/null 2>&1 || true   # settle: drop the straggler again

else
section "on Linux, deleting a line from the flake is the removal"
# The Homebrew equivalent of this needs an explicit --prune; here the rebuild
# does it, which is the property worth pinning down.
python3 - "$REPO/manifests/linux/flake.nix" <<'EOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
marker = "            jq # added by the CI reapply scenario\n"
assert marker in s, "the scenario's own flake edit is missing"
p.write_text(s.replace(marker, ""))
EOF
assert_true "the package is present before the removal" test -x "$NIX_ENV/bin/jq"
assert_true "reapply after deleting the line exits 0" run_reapply
assert_file_has "planned a rebuild for the removal" "$REAPPLY_OUT" 'rebuild the Nix environment'
assert_missing "the package is gone from the environment" "$NIX_ENV/bin/jq"
assert_true "the packages still declared survived" test -x "$NIX_ENV/bin/stow"
assert_file_lacks "no --prune advice on Linux, because none is needed" \
  "$REAPPLY_OUT" 'rerun with --prune'
fi

# --------------------------------------------------------------------------
section "a re-apply that cannot fast-forward fails loudly and changes nothing"
# --------------------------------------------------------------------------
printf '\n-- local edit the user has not committed\n' >>"$HOME/.config/nvim/init.lua"
nvim_local_sum="$(cksum <"$HOME/.config/nvim/init.lua")"
origin_commit nvim-config init.lua '-- upstream moved again, conflicting'
# sync-external-repos runs before mise on both platforms, so counting mise
# invocations proves the halt actually stopped the run rather than merely
# logging. (On macOS `brew bundle` is later still; either is a valid witness,
# but mise is the first step after the failure on both.)
if [ "$PLATFORM" = macos ]; then MISE_SHIM_LOG="$BREW_SHIM_LOG"; else MISE_SHIM_LOG="$NIX_SHIM_LOG"; fi
mise_calls_before="$(grep -c '^mise install$' "$MISE_SHIM_LOG" 2>/dev/null || echo 0)"

assert_false "reapply exits non-zero when a repo cannot be fast-forwarded" run_reapply
out="$REAPPLY_OUT"
assert_file_has "names the repo that failed" "$out" 'pull failed for .*/\.config/nvim'
assert_file_lacks "does not report completion" "$out" 're-apply complete'
assert_eq "the user's local edit is untouched" "$nvim_local_sum" "$(cksum <"$HOME/.config/nvim/init.lua")"
assert_eq "later steps did not run" \
  "$mise_calls_before" "$(grep -c '^mise install$' "$MISE_SHIM_LOG" 2>/dev/null || echo 0)"

# --------------------------------------------------------------------------
section "re-applying over a pre-existing real file backs it up instead of clobbering"
# --------------------------------------------------------------------------
# Where bootstrap.sh halts on a stow conflict, reapply.sh moves the real file
# into a timestamped backup directory and continues -- the file is never lost.
sandbox_destroy
sandbox_create
assert_true "baseline bootstrap for the backup check" run_bootstrap
rm -f "$HOME/.zshrc"
printf '# hand-written zshrc that predates the dotfiles\n' >"$HOME/.zshrc"
conflicting_sum="$(cksum <"$HOME/.zshrc")"

assert_true "reapply exits 0 over a conflicting real file" run_reapply
assert_file_has "reports the backup" "$REAPPLY_OUT" 'backed up conflicting file: \.zshrc'
assert_true "the managed link is now in place" test -L "$HOME/.zshrc"
backup="$(find "$HOME/.local/state/dotfiles" -name .zshrc -path '*/backup-*' | head -1)"
assert_true "a backup copy exists" test -n "$backup"
assert_eq "the backup is byte-identical to what was there" \
  "$conflicting_sum" "$(cksum <"$backup")"

finish
