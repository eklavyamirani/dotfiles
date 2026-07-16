# dotfiles

Stow-based dotfiles, split into two account profiles:

- **`admin/`** — the main/admin macOS account. Intentionally minimal: no
  Homebrew, no language runtimes, no dev tooling. Just shell basics and a
  `dev-shell` helper to `ssh` into the isolated dev account.
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
git clone https://github.com/eklavyamirani/dotfiles ~/dotfiles && cd ~/dotfiles
./bootstrap.sh
```

`bootstrap.sh` is a generic, declarative step-runner: the actual steps
(Homebrew install, `stow`, `mise`/`stow` install, `sync-external-repos`,
`brew bundle`) live in `bootstrap-steps.json`, not hardcoded in the script.
To change what bootstrap does, edit that manifest -- `bootstrap.sh` itself
shouldn't need touching. Each step entry has:

```json
{
  "name": "install Homebrew into ~/.homebrew",
  "command": "git clone https://github.com/Homebrew/brew \"$HOME/.homebrew\"",
  "skip_if": "[ -d \"$HOME/.homebrew\" ]",
  "purpose": "Isolated Homebrew -- never /opt/homebrew or /usr/local"
}
```

- `name`, `command` -- required. `command` is a shell string run via
  `eval` **in the same process** (not a subshell), so `export`/`PATH`
  changes from one step (e.g. loading Homebrew's `shellenv`) persist to
  later steps, the way sourcing would in an interactive shell.
- `skip_if` -- optional shell condition; if it exits `0`, the step is
  skipped (e.g. "already installed" checks).
- `purpose` -- optional, shown in logs.

It halts immediately on the first failing step (later steps depend on
earlier ones succeeding), and writes a full transcript of every step's
output to `~/.local/state/dotfiles/setup-<timestamp>.log` regardless of
outcome, so a failure always leaves you with complete detail to diagnose.
Every step is
idempotent (or guarded by `skip_if`), so it's always safe to fix the issue and rerun.

This account's Homebrew never touches `/opt/homebrew` or `/usr/local` and
never requires an admin password. A startup tripwire in
`dev/.zprofile.d/50-homebrew-isolated.zsh` warns if isolation is ever
compromised (e.g. another account's Homebrew leaks onto `PATH`).

### Setting up `dev-shell` (SSH, not `su`)

`dev-shell` uses `ssh claude@127.0.0.1`, not `su`. `su` keeps the dev shell
as a descendant of the admin account's own Terminal.app process, and macOS
resolves Apple Event "responsible process" permissions by walking up that
ancestry — so a process running as the dev user can send unprompted
AppleScript to the admin's Terminal.app (e.g. `do script "..."` runs as the
admin account: a full privilege escalation out of the isolated account).
`ssh` forks a fresh process tree via `sshd` with no Terminal.app ancestor,
closing this off entirely. One-time setup, on the **admin** account:

```bash
# 1. Enable Remote Login, restricted to the dev account only
sudo systemsetup -setremotelogin on
sudo dseditgroup -o edit -a claude -t user com.apple.access_ssh

# 2. Generate a key pair for the admin account (on this machine, not copied
#    in from elsewhere) and authorize it for the dev account
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_dev -N ""
ssh-copy-id -i ~/.ssh/id_ed25519_dev.pub claude@127.0.0.1

# 3. Require key-based auth only (edit /etc/ssh/sshd_config as root)
#    Match User claude
#        PasswordAuthentication no
sudo tee -a /etc/ssh/sshd_config <<'EOF'
Match User claude
    PasswordAuthentication no
EOF
sudo launchctl kickstart -k system/com.openssh.sshd
```

Then `dev-shell` (from `admin/.zprofile`) just works: `ssh -t claude@127.0.0.1`.

Note: use `127.0.0.1`, not `localhost` — macOS's `sshd_config` ships with
`ListenAddress 127.0.0.1` (IPv4 only), so if `localhost` resolves to `::1`
first on your machine, the connection will fail even with everything else
configured correctly.

### GitHub Copilot CLI login and the Keychain

Under `dev-shell` (SSH), the session runs in the `Background` security
session class, not `Aqua` — so macOS Keychain writes fail with "User
interaction is not allowed," and `copilot` offers to save the auth token as
plaintext instead. To use the login Keychain, unlock it first (prompts for
the dev account's password), then relock it right after so it doesn't stay
unlocked indefinitely:

```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db && \
copilot; \
security lock-keychain ~/Library/Keychains/login.keychain-db
```

The trailing `;` before the lock command ensures the keychain relocks even
if `copilot` exits non-zero.

### External repos (e.g. Neovim config)

Some tools (currently just the Neovim config) live in their own repos
instead of being tracked directly in `dotfiles`, so they can be deployed
standalone on machines that don't want the rest of this repo. These are
declared in `dev/.config/external-repos.json` (stowed to
`~/.config/external-repos.json`) and synced with `sync-external-repos`
(stowed to `~/.local/bin/sync-external-repos`, already on `PATH`):

```json
[
  {
    "repo": "https://github.com/eklavyamirani/nvim-config",
    "local_dir": "~/.config/nvim",
    "purpose": "Neovim configuration",
    "branch": null,
    "git_options": []
  }
]
```

- `repo`, `local_dir` -- required. `local_dir` can be named independently
  of the repo (e.g. `nvim-config` deploys to `~/.config/nvim`).
- `purpose` -- required, shown when the script runs.
- `branch` -- optional; `null`/omitted uses the repo's default branch.
- `git_options` -- optional array of extra flags appended to both `clone`
  and `pull` (e.g. `["--depth=1"]`).

Running `sync-external-repos` is fully idempotent: missing `local_dir`s are
cloned, existing ones get `git pull --ff-only`. There's no commit pinning
(unlike a git submodule) -- it always tracks the tip of whatever branch you
configure. To track a new repo, just add an entry and rerun.

Each entry is synced independently -- one failing entry doesn't halt the
rest. A failed clone has its partial directory cleaned up automatically; a
failed pull (e.g. local edits blocking a fast-forward) is reported and left
completely untouched, never auto-reverted. A summary is printed at the end
and the exit code is non-zero if anything failed.

### `dev/.config` is allowlisted, not blocklisted

`.gitignore` ignores all of `dev/.config/*` by default and explicitly
un-ignores only the specific configs meant to be tracked (currently
`terminal/`, `llama-server/`, `external-repos.json`). This is deliberate:
many CLI tools write credential/token files into their `~/.config/<tool>`
directory over time (OAuth tokens, API keys, session state), and a
blocklist approach requires remembering to add every such path -- one
missed entry and a `git add -A` silently commits a secret. To track a new
tool's config, add explicit `!dev/.config/<tool>/` and
`!dev/.config/<tool>/**` un-ignore lines to `.gitignore`.

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
