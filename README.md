# dotfiles

Stow-based dotfiles, split into two account profiles:

- **`admin/`** — the main/admin macOS account. Intentionally minimal: no
  Homebrew, no language runtimes, no dev tooling. Just shell basics and a
  `dev-shell` helper to `su` into the isolated dev account.
- **`dev/`** — an isolated, non-admin account that owns all development
  tooling (Homebrew installed to `~/.homebrew`, no sudo required; mise;
  neovim; pi/llama-server configs).

## Deploy

On the admin account:
```bash
git clone https://github.com/eklavyamirani/dotfiles ~/dotfiles && cd ~/dotfiles
stow -t ~ admin
```

On the isolated dev account (see "Bootstrap a new dev account" below first):
```bash
git clone https://github.com/eklavyamirani/dotfiles ~/dotfiles && cd ~/dotfiles
git submodule update --init --remote
stow -t ~ dev
```

To re-stow after changes (symlinks not set correctly):
```bash
stow -R -t ~ -n -v dev   # dry run, review diffs
stow -R -t ~ dev         # apply
```

## Bootstrap a new dev account (no sudo, ever)

```bash
# 1. Install Homebrew into this account's home directory only
git clone https://github.com/Homebrew/brew ~/.homebrew
eval "$(~/.homebrew/bin/brew shellenv)"

# 2. Install stow and mise
brew install stow mise

# 3. Clone dotfiles and stow the dev profile
git clone https://github.com/eklavyamirani/dotfiles ~/dotfiles && cd ~/dotfiles
git submodule update --init --remote
stow -t ~ dev

# 4. Install the rest of the toolset
brew bundle --file=dev/Brewfile
```

This account's Homebrew never touches `/opt/homebrew` or `/usr/local` and
never requires an admin password. A startup tripwire in
`dev/.zprofile.d/50-homebrew-isolated.zsh` warns if isolation is ever
compromised (e.g. another account's Homebrew leaks onto `PATH`).

### Local LLM setup (Qwen3.6-27B + pi agent)

After stowing `dev`, run these one-time steps:

```bash
# 1. Download the model (~18 GB)
hf download unsloth/Qwen3.6-27B-MTP-GGUF \
    --include "*UD-Q4_K_XL*" --include "*mmproj*" \
    --local-dir ~/.huggingface/unsloth/Qwen3.6-27B-MTP-GGUF

# 2. Build llama.cpp (Metal enabled by default on Mac)
cd ~/repositories/llama.cpp
cmake -B build -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA=OFF
cmake --build build --config Release -j --target llama-server

# 3. Link pi coding agent globally
cd ~/repositories/pi/packages/coding-agent
npm link
```

### Usage

```bash
# Start the local LLM server (terminal 1)
~/.config/llama-server/models/qwen3.6-27b.sh coding

# Quick question (terminal 2)
ask "What does EINTR mean?"

# Interactive coding session
pi-local "Help me refactor this" @file.py
```

Profiles: `coding` (default), `thinking`, `instruct`. See
`~/.config/llama-server/README.md` for details.
