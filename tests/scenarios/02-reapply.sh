#!/usr/bin/env bash
# Scenario 2: re-apply new changes onto an already-configured account.
#
# Starts from the state scenario 1 produces, then does what actually happens in
# practice: the repository gains new snippets, new nested config directories, an
# edited managed file, a new Brewfile entry and a new external repo, while the
# external repo's remote moves forward. Re-running bootstrap must pick all of
# that up, leave existing links and user state alone, stay idempotent on a third
# no-op run, and fail loudly (without clobbering anything) when it can't.

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
zshrc_inode_before="$(stat -c %i "$HOME/.zshrc")"
nvim_root_before="$(git -C "$HOME/.config/nvim" rev-list --max-parents=0 HEAD)"
brew_clone_before="$(git -C "$HOME/.homebrew" rev-parse HEAD)"

# User state that lives in stow-managed directories must survive a re-apply.
printf '{"session":"keep me"}\n' >"$HOME/.pi/agent/runtime-state.json"

# --------------------------------------------------------------------------
section "change the configuration the way a real update would"
# --------------------------------------------------------------------------
# A new profile snippet in an existing managed directory.
cat >"$REPO/dev/.zprofile.d/40-ci-added-snippet.zsh" <<'EOF'
export DOTFILES_CI_ADDED_SNIPPET=1
EOF

# A new file in a new *nested* managed directory (exercises prepare-stow-targets
# on a rerun: without it, stow would fold ~/.claude/skills/ci-demo into the repo).
mkdir -p "$REPO/dev/.claude/skills/ci-demo"
printf '# CI demo skill\n' >"$REPO/dev/.claude/skills/ci-demo/SKILL.md"

# A new top-level managed directory.
mkdir -p "$REPO/dev/.newtool"
printf 'answer = 42\n' >"$REPO/dev/.newtool/config.ini"

# An edit to an already-deployed file.
printf '\n# added by the CI reapply scenario\nexport DOTFILES_CI_ZSHRC_EDIT=1\n' >>"$REPO/dev/.zshrc"

# A new Brewfile entry.
printf '\nbrew "jq"           # added by the CI reapply scenario\n' >>"$REPO/dev/Brewfile"

# A second external repo in the manifest, plus a new upstream commit in the
# first one, so this run both clones and fast-forwards.
origin_new ci-extra-repo
git config --global "url.file://$ORIGINS/ci-extra-repo.insteadOf" 'https://github.com/eklavyamirani/ci-extra-repo'
python3 - "$REPO/dev/.config/external-repos.json" <<'EOF'
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
bundle_calls_before="$(grep -c '^bundle ' "$BREW_CALL_LOG")"

# --------------------------------------------------------------------------
section "re-apply onto the existing configuration"
# --------------------------------------------------------------------------
assert_true "re-run of bootstrap exits 0" run_bootstrap
cp "$BOOTSTRAP_OUT" "$SANDBOX/reapply.out"
out="$SANDBOX/reapply.out"
assert_file_has "reports completion" "$out" 'bootstrap complete'

section "already-satisfied steps are skipped, the rest re-run"
assert_file_has "Homebrew install skipped by skip_if" "$out" '==> install Homebrew into ~/.homebrew \(skipped, already done\)'
assert_eq "existing ~/.homebrew checkout untouched" \
  "$brew_clone_before" "$(git -C "$HOME/.homebrew" rev-parse HEAD)"
assert_file_has "stow re-ran" "$out" '==> stow dev profile$'
assert_file_has "external repo sync re-ran" "$out" '==> sync external repos'
assert_file_has "brew bundle re-ran" "$out" '==> install Brewfile packages$'

section "new configuration is deployed"
assert_symlink_to "new snippet linked" \
  "$HOME/.zprofile.d/40-ci-added-snippet.zsh" "$REPO/dev/.zprofile.d/40-ci-added-snippet.zsh"
assert_symlink_to "new nested file linked" \
  "$HOME/.claude/skills/ci-demo/SKILL.md" "$REPO/dev/.claude/skills/ci-demo/SKILL.md"
assert_real_dir "new nested directory is real, not folded" "$HOME/.claude/skills/ci-demo"
assert_symlink_to "new top-level file linked" \
  "$HOME/.newtool/config.ini" "$REPO/dev/.newtool/config.ini"
assert_real_dir "new top-level directory is real, not folded" "$HOME/.newtool"
assert_true "new snippet is picked up by the profile loader" \
  bash -c 'zsh -c "source \"$HOME/.zprofile\"; [ \"\$DOTFILES_CI_ADDED_SNIPPET\" = 1 ]"'

section "existing deployment is left alone"
assert_eq "~/.zshrc is still the same link (not replaced)" \
  "$zshrc_inode_before" "$(stat -c %i "$HOME/.zshrc")"
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

section "new Brewfile entry is installed"
assert_file_has "brew bundle saw the new entry" "$HOME/.homebrew/bundled.txt" '^jq$'
assert_eq "brew bundle ran exactly once more" \
  "$((bundle_calls_before + 1))" "$(grep -c '^bundle ' "$BREW_CALL_LOG")"

section "re-apply still does not write into the repository"
assert_eq "repository tree unchanged by the re-apply" "$repo_after_change" "$(repo_tree_snapshot)"
assert_eq "repository working tree is clean" "" "$(git -C "$REPO" status --porcelain)"

# --------------------------------------------------------------------------
section "a third run with nothing changed is a no-op"
# --------------------------------------------------------------------------
links_settled="$(home_link_snapshot)"
assert_true "third bootstrap run exits 0" run_bootstrap
assert_eq "deployed links are byte-identical" "$links_settled" "$(home_link_snapshot)"
assert_eq "nvim clone stays at the same commit" \
  "$nvim_target" "$(git -C "$HOME/.config/nvim" rev-parse HEAD)"
assert_eq "repository still clean" "" "$(git -C "$REPO" status --porcelain)"

# --------------------------------------------------------------------------
section "a re-apply that cannot fast-forward fails loudly and changes nothing"
# --------------------------------------------------------------------------
printf '\n-- local edit the user has not committed\n' >>"$HOME/.config/nvim/init.lua"
nvim_local_sum="$(cksum <"$HOME/.config/nvim/init.lua")"
origin_commit nvim-config init.lua '-- upstream moved again, conflicting'
bundle_calls_before="$(grep -c '^bundle ' "$BREW_CALL_LOG")"

assert_false "bootstrap exits non-zero when a repo cannot be fast-forwarded" run_bootstrap
cp "$BOOTSTRAP_OUT" "$SANDBOX/conflict.out"
out="$SANDBOX/conflict.out"
assert_file_has "names the repo that failed" "$out" 'pull failed for .*/\.config/nvim'
assert_file_has "halts the run at that step" "$out" 'ERROR: step failed: sync external repos'
assert_file_lacks "does not report completion" "$out" 'bootstrap complete'
assert_eq "the user's local edit is untouched" "$nvim_local_sum" "$(cksum <"$HOME/.config/nvim/init.lua")"
assert_eq "later steps did not run" \
  "$bundle_calls_before" "$(grep -c '^bundle ' "$BREW_CALL_LOG")"

# --------------------------------------------------------------------------
section "re-applying over a pre-existing real file refuses to clobber it"
# --------------------------------------------------------------------------
sandbox_destroy
sandbox_create
printf '# hand-written zshrc that predates the dotfiles\n' >"$HOME/.zshrc"
conflicting_sum="$(cksum <"$HOME/.zshrc")"
assert_false "bootstrap exits non-zero on a stow conflict" run_bootstrap
assert_file_has "halts at the stow step" "$BOOTSTRAP_OUT" 'ERROR: step failed: stow dev profile'
assert_eq "the pre-existing file is left exactly as it was" "$conflicting_sum" "$(cksum <"$HOME/.zshrc")"
assert_true "~/.zshrc was not turned into a link" test ! -L "$HOME/.zshrc"

finish
