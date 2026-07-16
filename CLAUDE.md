# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Type

This is a **stow-based dotfiles repository**, split into two account profiles
for a two-account macOS setup: a minimal admin account and an isolated,
non-admin dev account that owns all development tooling.

## Package layout

- **`admin/`** — deployed on the main/admin account. No Homebrew, no
  language runtimes, no dev tooling by design. Just shell basics (`.zshrc`,
  `.zprofile`) and a `dev-shell` function to `ssh` into the dev account
  (not `su` — see `admin/.zprofile` for why: `su` shares process ancestry
  with the admin's Terminal.app, letting the dev account send unprompted
  Apple Events back to it).
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

### Deploy admin profile (main account)
```bash
stow -t ~ admin
```

### Bootstrap + deploy dev profile (isolated non-admin account)
```bash
git clone https://github.com/eklavyamirani/dotfiles ~/dotfiles && cd ~/dotfiles
./bootstrap.sh
```
`bootstrap.sh` (repo root -- deliberately not in `dev/.local/bin`, since it
runs `stow` itself and can't depend on `stow` having already run) is a
generic step-runner; the actual steps (Homebrew install, `stow`, `mise`
install, `sync-external-repos`, `brew bundle`) are declared in
`bootstrap-steps.json`, not hardcoded in the script. Each step's `command`
runs via `eval` in the same process (not a subshell) so env/`PATH` changes
persist across steps; `skip_if` allows idempotent skip conditions. Halts on
first failure; every step's output is logged to
`~/.local/state/dotfiles/setup-<timestamp>.log`.

## Configuration Structure

### Shell Configuration (`dev/`)
- **`.zshrc`** - prompt, fzf sourcing
- **`.zprofile`** - thin loader, sources `.zprofile.d/*.zsh` in filename order
- **`.zprofile.d/05-local-bin-path.zsh`** - `~/.local/bin` on PATH
- **`.zprofile.d/10-editor-history.zsh`** - EDITOR, history settings, nvim aliases
- **`.zprofile.d/20-pi-aliases.zsh`** - local LLM / pi agent aliases
- **`.zprofile.d/40-mise.zsh`** - mise activation
- **`.zprofile.d/50-homebrew-isolated.zsh`** - isolated Homebrew shellenv,
  a `brew()` function pinning to `~/.homebrew` regardless of PATH ordering,
  and a startup tripwire warning if isolation is ever compromised

### Neovim Configuration (`dev/.config/nvim`, external repo via `sync-external-repos`)
- **`init.lua`** - Main initialization file with basic settings and keymaps
- **`lua/config/plugins.lua`** - Plugin declarations and setup via vim-plug

### macOS Defaults (`admin/.macos`)
- Run once on the admin account for system-wide typing/keyboard preferences

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
