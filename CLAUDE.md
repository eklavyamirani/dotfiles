# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Type

This is a **stow-based dotfiles repository** for the isolated, non-admin
dev account of a two-account macOS setup. The minimal admin account's
profile is archived here (not live) pending a move to its own repository.

## Package layout

- **`archive/admin/`** — frozen, reference-only snapshot of the main/admin
  account profile (`.zshrc`, `.zprofile` with the `dev-shell` ssh helper,
  `.macos`). Not deployed from here; nothing in `dev/` or the bootstrap
  depends on it. Don't extend it — it's leaving this repo.
- **`dev/`** — deployed on the isolated non-admin dev account. Owns:
  - Homebrew, installed to `~/.homebrew` (never `/opt/homebrew` or
    `/usr/local`) — no sudo required to install or use.
  - `.zprofile.d/*.zsh` — numbered snippets sourced in order by `.zprofile`
    (a thin loader). Add new snippets here rather than editing `.zprofile`
    directly.
  - `Brewfile` — the curated package list for `brew bundle`.
  - `external-repos.json` + `sync-external-repos` — declarative manifest
    and idempotent sync script for repos that live outside `dotfiles`
    (currently just the Neovim config), so they stay deployable standalone
    on machines that don't want the rest of this repo. No commit pinning —
    always tracks the tip of the configured branch. Not a git submodule.
  - Neovim config (external repo, see above), pi agent / llama-server configs.

## Setup Instructions

### Bootstrap + deploy dev profile (isolated non-admin account)
```bash
git clone https://github.com/eklavyamirani/dotfiles ~/dotfiles && cd ~/dotfiles
./bootstrap.sh
```
`bootstrap.sh` (repo root -- deliberately not in `dev/.local/bin`, since it
runs `stow` itself and can't depend on `stow` having already run) is a
generic step-runner; the actual steps (Homebrew install, `stow`/`mise`
install, `stow`, `sync-external-repos`, `brew bundle`) are declared in
`bootstrap-steps.json`, not hardcoded in the script. Each step's `command`
runs via `eval` in the same process (not a subshell) so env/`PATH` changes
persist across steps; `skip_if` allows idempotent skip conditions. Halts on
first failure; every step's output is logged to
`~/.local/state/dotfiles/setup-<timestamp>.log`.

Before Stow runs, `prepare-stow-targets.sh` creates real target directories
so Stow links managed files individually instead of folding whole stateful
directories (such as `~/.pi`) into the repository.

## Tests

`tests/` holds two container scenarios (`tests/scenarios/01-fresh-apply.sh`,
`02-reapply.sh`) that run the real `bootstrap.sh` against the real manifests
in a throwaway `$HOME`, with local git repos standing in for the Homebrew and
external-repo remotes — the suite is fully offline (`--network none` in CI).
Homebrew itself is stubbed (`tests/stubs/homebrew`); everything else (stow,
`prepare-stow-targets.sh`, `sync-external-repos`, the `.zprofile` chain under
real zsh) is exercised for real. Run them with
`docker build -f tests/Dockerfile -t dotfiles-ci tests/` then
`docker run --rm --network none -v "$PWD:/repo:ro" -e SOURCE_REPO=/repo dotfiles-ci /repo/tests/run-tests.sh`.
The file-level assertions are derived by walking `dev/`, so new managed files
and directories are covered without touching the tests. CI:
`.github/workflows/ci.yml`. Details and limitations: `tests/README.md`.

## Configuration Structure

### Shell Configuration (`dev/`)
- **`.zshrc`** - prompt, fzf sourcing
- **`.zprofile`** - thin loader, sources `.zprofile.d/*.zsh` in filename order
- **`.zprofile.d/05-local-bin-path.zsh`** - `~/.local/bin` on PATH
- **`.zprofile.d/10-editor-history.zsh`** - EDITOR, history settings, nvim aliases
- **`.zprofile.d/20-pi-aliases.zsh`** - local LLM / pi agent aliases
- **`.zprofile.d/30-system-helpers.zsh`** - `diskcheck` helper
- **`.zprofile.d/50-homebrew-isolated.zsh`** - isolated Homebrew shellenv,
  a `brew()` function pinning to `~/.homebrew` regardless of PATH ordering,
  and a startup tripwire warning if isolation is ever compromised
- **`.zprofile.d/55-mise.zsh`** - mise activation (must run after 50, since
  mise is installed via Homebrew)
- **`.zprofile.d/60-terminal-appearance.zsh`** - Claude-Dev Terminal.app
  profile bootstrap

### Neovim Configuration (`dev/.config/nvim`, external repo via `sync-external-repos`)
- **`init.lua`** - Main initialization file with basic settings and keymaps
- **`lua/config/plugins.lua`** - Plugin declarations and setup via vim-plug

### macOS Defaults (`archive/admin/.macos`)
- Archived; run once on the admin account for system-wide typing/keyboard preferences

## Key Customizations

### Neovim
- Leader key: `<Space>`
- Keymaps: `<Space>ed` (file explorer), `<Space>ei` (edit init.lua)
- Uses MiniFiles instead of nvim-tree
- Catppuccin colorscheme
- Lualine statusline

### Shell
- Custom prompt: `|username@hostname|path|prompt_char > `
- `localClaude` function for local model interactions
- Language/tool versions managed via **mise**, not nvm (nvm's admin-account
  lockdown scripts from earlier revisions of this repo have been removed —
  no dev tooling lives on the admin account anymore, so there's nothing to
  lock down)

## Important Notes

- This uses **stow** for symlink management - do not manually edit deployed files
- Neovim plugins are managed via **vim-plug** (auto-installs on first run)
- The `NVIM_APPNAME` environment variable is set to enable multiple Neovim instances
- The `dev` account's Homebrew must never be pointed at `/opt/homebrew` or
  `/usr/local` — that would break isolation from the admin account
