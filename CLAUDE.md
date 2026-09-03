# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Design principle: declarative, code-first

Every change to this account's system state should be a commit here, and
`./reapply.sh` should be the only thing that applies it. Real Nix is not an
option on this machine -- the dev account is deliberately non-admin, and a
macOS Nix install needs root to create the `/nix` APFS volume -- so the
same properties are approximated with plain manifests:

| Domain | Declared in | Reconciled by |
| --- | --- | --- |
| Shell/config files | `dev/` (stow package) | `reapply.sh` (links + prunes stale ones) |
| Homebrew packages | `dev/Brewfile` | `reapply.sh` (installs; reports drift; `--prune` removes) |
| External repos | `dev/.config/external-repos.json` | `sync-external-repos` |
| Fresh-machine setup | `bootstrap-steps.json` | `bootstrap.sh` |
| Runtime versions | `dev/.config/mise/config.toml` | `reapply.sh` (`mise install`) |
| Docker CLI plugins | `dev/.local/bin/link-docker-cli-plugins` | `reapply.sh` (runs it after `brew bundle`) |

Rules that keep it from drifting again:
- Installing something with `brew install` is a *draft*. It is not real
  until it is in `dev/Brewfile`; `reapply.sh` reports anything installed
  that isn't declared, so undeclared packages surface on the next run
  rather than silently becoming part of the machine.
- The Brewfile describes the whole closure, including packages you might
  not want anymore. Remove things by deleting the line and running
  `./reapply.sh --prune`, not by running `brew uninstall` by hand.
- Transitive dependencies are deliberately NOT declared. `hf` pulls in
  `python@3.14`; that belongs to `hf`, not to you, and drift detection
  compares against `brew leaves --installed-on-request` so it never nags
  about it.

Runtimes belong to mise, never to Homebrew. A brew formula tracks one
moving version and silently upgrades on any `brew bundle`; mise pins an
exact version that a project-local `.mise.toml` can override. Add a runtime
with `mise use -g <tool>@<exact version>` and commit the resulting
`dev/.config/mise/config.toml` change -- do not add it to the Brewfile.
`mise` itself is the one exception: it is installed by Homebrew, since
something has to bootstrap the bootstrapper.

Only *globally* useful runtimes belong in `dev/.config/mise/config.toml`.
A runtime that one project needs belongs in that project's own
`.mise.toml` (`mise use dotnet@10.0.400` inside the repo), so the version
travels with the code rather than becoming an account-wide fact.

Docker CLI plugins are not runtimes and mise does not fit them: `docker
buildx` resolves from `~/.docker/cli-plugins`, not from `$PATH`, so a mise
shim would leave `docker buildx` broken. They stay Homebrew formulae, and
`dev/.local/bin/link-docker-cli-plugins` wires them into the plugin
directory -- without it, a fresh machine installs the formulae and still
reports `docker: unknown command: docker buildx`. Pointing docker's
`cliPluginsExtraDirs` at brew's bin would also work but is deliberately
avoided: that setting lives in `~/.docker/config.json`, which holds
registry `auths` and so can never be tracked here.

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

### Re-apply after pulling changes
```bash
cd ~/dotfiles && git pull && ./reapply.sh
```
`reapply.sh` (also at the repo root, and for the same reason as
`bootstrap.sh` -- it runs `stow`, so it can't live in `dev/.local/bin`) is
the steady-state counterpart to bootstrap: it re-links the `dev` package,
syncs external repos and runs `brew bundle`, but does not install
Homebrew/stow/mise. Prefer it over a bare `stow -R`, which unstows using
the package's *current* contents and therefore strands a dangling symlink
in `$HOME` whenever a file is renamed or deleted upstream -- and since
`.zprofile` globs `.zprofile.d/*.zsh`, one stale link breaks every new
shell.

Failsafes, so a re-apply can never cost you something unrecoverable:
- It removes only symlinks that point into this repository and whose
  target is gone. Real files, real directories, and links pointing
  anywhere else are left untouched.
- Real files that block a link are moved into
  `~/.local/state/dotfiles/backup-<timestamp>/` under the same relative
  path, never overwritten or deleted.
- Package removal is opt-in. Drift is always *reported*; only `--prune`
  acts on it, and prune refuses to run if the Brewfile parses as empty --
  otherwise a typo'd or unreadable manifest would make every installed
  package look undeclared and wipe the account.
- It prints the full plan and waits for confirmation. `--dry-run` stops
  after the plan; `--yes` runs unattended (required when stdin isn't a
  terminal); `--no-brew` / `--no-sync` skip those steps; `--no-upgrade`
  installs missing packages without upgrading existing ones (`brew bundle`
  upgrades by default). Transcript goes to
  `~/.local/state/dotfiles/reapply-<timestamp>.log`.

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
- **`.config/mise/config.toml`** - globally pinned language runtimes
  (exact versions; see the declarative principle above)
- **`.zprofile.d/60-terminal-appearance.zsh`** - Claude-Dev Terminal.app
  profile bootstrap

### Scripts (`dev/.local/bin`)
- **`sync-external-repos`** - clones/updates repos from `external-repos.json`
- **`link-docker-cli-plugins`** - links brew's docker plugins into
  `~/.docker/cli-plugins` (idempotent; never overwrites a real file there)

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
