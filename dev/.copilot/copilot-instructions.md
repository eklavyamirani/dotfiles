<!-- Kept in sync with dev/.claude/CLAUDE.md; edit both. -->

# Dotfile symlink safety

Files under `$HOME` may be GNU Stow symlinks into a Git repository. Before
editing a dotfile, resolve its real path and read the target repository's
instructions and nearby configuration.

For this dotfiles repository:

- Treat edits through deployed symlinks as repository changes.
- Keep `.zprofile` as a thin loader; put shell additions in a suitably named,
  numbered `.zprofile.d/*.zsh` snippet.
- Keep `.zshrc` limited to interactive Zsh initialization already established
  there.
- Use `mise` as the runtime version manager; do not initialize competing
  managers such as NVM, pyenv, rbenv, or asdf.
- Never version credentials, session logs, caches, downloaded binaries, or
  other generated state.
- Inspect the repository diff and status before considering work complete.
