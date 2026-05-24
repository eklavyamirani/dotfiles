### To use the config on an existing system
Update the submodule. ```git submodule update --remote --merge```
Commit
Use diff to compare the files between local and the git repo.
Since symlinks aren't set correctly, we need to restow. 
```stow -R -t ~/ -n -v .```
Remove the current files on the host
Run the stow command without -n.

---

### Prerequisites

These tools must be installed separately (not managed by stow):

| Tool | Install | Purpose |
|------|---------|---------|
| [Homebrew](https://brew.sh) | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` | Package manager |
| nvm | `brew install nvm` | Node version manager |
| Node.js | `nvm install --lts` | Runtime for pi agent |
| [Hugging Face CLI](https://huggingface.co/docs/huggingface_hub/guides/cli) | `brew install hf` | Model downloads |

### Local LLM setup (Qwen3.6-27B + pi agent)

After stowing dotfiles, run these one-time steps:

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

Profiles: `coding` (default), `thinking`, `instruct`. See `~/.config/llama-server/README.md` for details.
