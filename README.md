# dotfiles

Stow-based dotfiles for **`dev/`** — an isolated, non-admin macOS account
that owns all development tooling (Homebrew installed to `~/.homebrew`, no
sudo required; mise; neovim; pi/llama-server configs). The paired
main/admin account is deliberately minimal and its profile is kept only as
a frozen snapshot in `archive/admin/` (see its README) until it moves to
its own repository.

## Deploy

On the isolated dev account, the normal path is `./bootstrap.sh` (see
"Bootstrap a new dev account" below). The equivalent manual steps, if you
already have `stow` and Homebrew:
```bash
git clone https://github.com/eklavyamirani/dotfiles ~/dotfiles && cd ~/dotfiles
./prepare-stow-targets.sh dev ~
stow -t ~ dev
~/.local/bin/sync-external-repos   # fetches the Neovim config
```

To re-stow after changes (symlinks not set correctly):
```bash
./prepare-stow-targets.sh dev ~
stow -R -t ~ -n -v dev   # dry run, review diffs
stow -R -t ~ dev         # apply
```

`prepare-stow-targets.sh` creates the package's directory structure in the
target before Stow runs. This prevents Stow from folding an entire directory
such as `~/.pi` into one repository symlink: managed files remain symlinked,
while credentials, sessions, caches, and other runtime files are written to
real directories under `$HOME`.

## Bootstrap a new dev account (no sudo, ever)

```bash
git clone https://github.com/eklavyamirani/dotfiles ~/dotfiles && cd ~/dotfiles
./bootstrap.sh
```

`bootstrap.sh` is a generic, declarative step-runner: the actual steps
(Homebrew install, `stow`/`mise` install, `stow`, `sync-external-repos`,
`brew bundle`) live in `bootstrap-steps.json`, not hardcoded in the script.
To change what bootstrap does, edit that manifest -- `bootstrap.sh` itself
shouldn't need touching. Each step entry has:

```json
{
  "name": "install Homebrew into ~/.homebrew",
  "command": "git clone https://github.com/Homebrew/brew \"$HOME/.homebrew\"",
  "skip_if": "[ -x \"$HOME/.homebrew/bin/brew\" ]",
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

### `dev-shell` from the admin account

The admin-side `dev-shell` helper and its one-time SSH setup live with the
archived admin profile: see `archive/admin/README.md`.

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
rest. A failed clone has its partial directory cleaned up automatically
(only if this run created it -- a pre-existing non-git `local_dir` is
refused, never deleted); a failed pull (e.g. local edits blocking a fast-forward) is reported and left
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

## Tests

Two container scenarios cover the deploy end to end -- a full apply from
scratch, and a re-apply of new changes onto an already-configured account.
They run the real `bootstrap.sh` against the real manifests, with local git
repositories standing in for the Homebrew and external-repo remotes, so the
whole suite runs offline (`--network none` in CI).

```bash
docker build -f tests/Dockerfile -t dotfiles-ci tests/
docker run --rm --network none -v "$PWD:/repo:ro" -e SOURCE_REPO=/repo \
  dotfiles-ci /repo/tests/run-tests.sh
```

Both run on every push and pull request (`.github/workflows/ci.yml`). See
`tests/README.md` for what is real, what is stubbed, and why.
