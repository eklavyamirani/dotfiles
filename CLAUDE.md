# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Type

This is a **stow-based dotfiles repository** for managing user configuration files across different systems.

## Setup Instructions

### Install dependencies
```bash
brew install stow neovim fzf
```

### Deploy configs
```bash
stow -R -t ~/ .
```

### Update submodules (neovim config)
```bash
git submodule update --remote --merge
```

## Configuration Structure

### Shell Configuration
- **`.zshrc`** - Main zsh configuration (prompt, aliases, functions, plugin loading)
- **`.zprofile`** - Login shell configuration (editor, history settings)

### Neovim Configuration
- **`.config/nvim/init.lua`** - Main initialization file with basic settings and keymaps
- **`.config/nvim/lua/config/plugins.lua`** - Plugin declarations and setup via vim-plug

### GitHub CLI
- **`.config/gh/config.yml`** - Global gh CLI settings
- **`.config/gh/hosts.yml`** - Host-specific authentication

### Git
- **`.config/git/ignore`** - Global gitignore patterns

### macOS Defaults
- **`.macos`** - macOS system defaults configuration

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
- NVM auto-loading via Homebrew

## Important Notes

- This uses **stow** for symlink management - do not manually edit deployed files
- Neovim plugins are managed via **vim-plug** (auto-installs on first run)
- The `NVIM_APPNAME` environment variable is set to enable multiple Neovim instances

## Known Issues (Already Fixed)

- Syntax error in `init.lua` line 57 (`trdf;ue` → `true`)
- Duplicate `tabstop` setting removed
- Dead code (commented NvimTree keymap) removed