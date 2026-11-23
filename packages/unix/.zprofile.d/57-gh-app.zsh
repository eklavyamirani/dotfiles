# gh-app: run gh and git as this computer's own GitHub App, so agent work
# shows up as a bot and notifies the owner. Lives in its own repository
# (external-repos.json -> ~/.local/share/gh-app) so machines that don't use
# these dotfiles can run it too; this snippet only loads it.
#
# Inert until both are true: sync-external-repos has cloned it, and
# `gh-app setup` has created this computer's App (until then the `gh`
# function it defines passes straight through to the real gh).
if [[ -r "$HOME/.local/share/gh-app/gh-app.zsh" ]]; then
  source "$HOME/.local/share/gh-app/gh-app.zsh"
fi
