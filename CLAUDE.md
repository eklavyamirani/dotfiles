# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Design principle: declarative, code-first

Every change to this account's system state should be a commit here, and
`./reapply.sh` should be the only thing that applies it. On **macOS** real
Nix is not an option -- the dev account is deliberately non-admin, and a
macOS Nix install needs root to create the `/nix` APFS volume -- so the
same properties are approximated with plain manifests. On **Linux** Nix
*is* available and is used, taking Homebrew's slot and nothing else:

| Domain | Declared in | Reconciled by |
| --- | --- | --- |
| Shell/config files | `packages/{common,unix,macos,linux}/` (stow packages) | `reapply.sh` (links + prunes stale ones) |
| CLI tools + runtimes | `packages/common/.config/mise/config.toml` | `reapply.sh` / `bootstrap.sh` (`mise install`) |
| What mise can't pin (macOS) | `manifests/macos/Brewfile` | `reapply.sh` (installs; reports drift; `--prune` removes) |
| What mise can't pin (Linux) | `manifests/linux/flake.nix` + `flake.lock` | `reapply.sh` (`nix build`; rebuilt whole, so a deleted line *is* the removal) |
| External repos | `packages/common/.config/external-repos.json` | `sync-external-repos` |
| Fresh-machine setup | `manifests/common/bootstrap-steps.json` | `bootstrap.sh` |
| Docker CLI plugins (macOS) | `packages/macos/.local/bin/link-docker-cli-plugins` | `reapply.sh` (runs it after `brew bundle`) |

Rules that keep it from drifting again:
- Installing something with `brew install` is a *draft*. It is not real
  until it is in `manifests/macos/Brewfile`; `reapply.sh` reports anything installed
  that isn't declared, so undeclared packages surface on the next run
  rather than silently becoming part of the machine.
- The Brewfile describes the whole closure, including packages you might
  not want anymore. Remove things by deleting the line and running
  `./reapply.sh --prune`, not by running `brew uninstall` by hand.
- Transitive dependencies are deliberately NOT declared. `hf` pulls in
  `python@3.14`; that belongs to `hf`, not to you, and drift detection
  compares against `brew leaves --installed-on-request` so it never nags
  about it.

## Cross-platform rules

The two machines diverge in exactly one place: the `os` field on a step in
`manifests/common/bootstrap-steps.json` (`"macos"` / `"linux"`; omit it for steps that are
the same everywhere). Do not add a second mechanism for OS branching --
`reapply.sh` reads `uname -s` into `$PLATFORM` and gates the same way, and
the shell snippets gate on `$OSTYPE`. Anything beyond that should be
shared, because the point is that both machines run the same shell, the
same stow package and the same mise-pinned tool versions.

Consequences worth remembering before editing:
- A shell snippet that touches a platform-specific path MUST be guarded.
  `50-homebrew-isolated.zsh` ran `eval "$(~/.homebrew/bin/brew shellenv)"`
  unconditionally; on a machine with no `~/.homebrew` that fails on every
  login shell.
- **The rule for which tree a file belongs in**: `manifests/<platform>/` is
  declared state *applied from the repository* (Brewfile, flake, the bootstrap
  step list); `packages/<pkg>/` is declared state *deployed into `$HOME`*. The
  mise config is the awkward case and lives in `packages/common/` despite
  being the most "common manifest" here, because mise reads it from
  `~/.config/mise/config.toml` -- it has to be stowed. Putting a manifest in a
  package is how `~/Brewfile` and a stray `~/nix/` directory happened.
- mise comes from `nixpkgs-unstable` in the flake, deliberately, and only
  mise. Its tool *registry* ships inside the binary, so a stable-channel
  mise cannot resolve a tool added to the registry since -- a hard
  `mise ERROR <tool> not found in mise tool registry` that halts bootstrap.
  Both inputs are still pinned by `flake.lock`.
- The Linux side has no `--prune` and needs none: the environment is
  rebuilt whole, so deleting a line from the flake removes the package.
- Bootstrap installs Nix with `--no-modify-profile` because the installer
  would otherwise append its snippet to `~/.zshrc`, which is a stow symlink
  into this repository. `45-nix.zsh` sources the profile script instead.
- The login shell matters more on Linux than it looks. Everything here is
  zsh-only, so on a bash-default distribution the whole deployment is inert
  until `chsh` has run -- installed, linked, and never on `PATH`. Two
  Linux-only bootstrap steps handle it; both are guarded by
  `skip_if: ! sudo -n true` so they skip instead of halting, and so the CI
  container (no sudo) never rewrites the runner's `/etc/shells`. Scenario 01
  asserts exactly that.
- That login shell points at the Nix out-link, so it is pinned but fragile:
  deleting `~/.local/state/dotfiles/nix-env` makes new shells unstartable,
  including over ssh. Never suggest removing that directory without
  `chsh -s /bin/bash` first. See the warning in the README.

Anything mise has a backend for belongs to mise, never to Homebrew or Nix --
runtimes and CLI tools alike. A brew formula tracks one moving version,
silently upgrades on any `brew bundle`, cannot be rolled back, and in this
account's non-default prefix is usually built from source; mise pins an
exact version, keeps installs side by side (rollback = edit the version
string and rerun), and ships prebuilt binaries. Add a tool with
`mise use -g <tool>@<exact version>` and commit the resulting
`packages/common/.config/mise/config.toml` change -- do not add it to the Brewfile.
Check `mise registry` before reaching for `brew install`.

What legitimately stays in the Brewfile, and only this: `stow` and `mise`
(bootstrap dependencies -- something has to bootstrap the bootstrapper),
formulae with no mise backend (`git`, `tree`, `hf`, `audio-cpp`), the docker
CLI plugins, and casks. mise's own version is consequently unpinned; that
gap is accepted and documented in the README rather than papered over.
`manifests/linux/flake.nix` carries the same job on Linux and the same rule for what may
go in it -- with the difference that `flake.lock` pins everything there,
including mise, so that gap does not exist on Linux.

Only *globally* useful runtimes belong in `packages/common/.config/mise/config.toml`.
A runtime that one project needs belongs in that project's own
`.mise.toml` (`mise use dotnet@10.0.400` inside the repo), so the version
travels with the code rather than becoming an account-wide fact.

Docker CLI plugins are not PATH tools and mise does not fit them: `docker
buildx` resolves from `~/.docker/cli-plugins`, not from `$PATH`, so a mise
shim would leave `docker buildx` broken. They stay Homebrew formulae -- `docker-compose` too, even
though mise has a backend for it, since `link-docker-cli-plugins` reads one
source directory and splitting them would leave `docker compose` broken --
and
`packages/macos/.local/bin/link-docker-cli-plugins` wires them into the plugin
directory -- without it, a fresh machine installs the formulae and still
reports `docker: unknown command: docker buildx`. Pointing docker's
`cliPluginsExtraDirs` at brew's bin would also work but is deliberately
avoided: that setting lives in `~/.docker/config.json`, which holds
registry `auths` and so can never be tracked here.

## Repository Type

This is a **stow-based dotfiles repository** for the isolated, non-admin
dev account of a two-account macOS setup, which also deploys unchanged on
Linux (see "Cross-platform rules" above). The minimal admin account's
profile is archived here (not live) pending a move to its own repository.

## Package layout

- **`archive/admin/`** — frozen, reference-only snapshot of the main/admin
  account profile (`.zshrc`, `.zprofile` with the `dev-shell` ssh helper,
  `.macos`). Not deployed from here; nothing in `packages/` or the bootstrap
  depends on it. Don't extend it — it's leaving this repo.
- **`packages/`** — the stow packages, deployed with
  `stow -d packages -t ~ common unix <platform>`. A file's *package is its
  platform declaration*: `common/` goes everywhere (including the future
  Windows milestone), `unix/` is the zsh chain macOS and Linux share, and
  `macos/`/`linux/` hold only what is genuinely specific. Nothing in a
  package needs an `$OSTYPE` guard, because it never reaches the other
  machine -- which is also why `stow-packages.sh` and `reapply.sh` refuse to
  deploy another platform's package: without those guards a leaked link is no
  longer inert, it breaks every login shell.
- **`manifests/`** — `common/bootstrap-steps.json`, `macos/Brewfile`,
  `linux/flake.nix` + `flake.lock`.
- **`lib/platform.sh`** — the only place in the repository that calls
  `uname`. Exports `$PLATFORM` (`macos`/`linux`, this repo's own vocabulary,
  used for directory names and the `os` field) and `$PLATFORM_UNAME`
  (`Darwin`/`Linux`, for anything that must speak the OS's own vocabulary --
  a download URL slug, a Nix system string). Never interpolate `$PLATFORM`
  into something an external tool parses.
- The dev account owns:
  - Homebrew, installed to `~/.homebrew` (never `/opt/homebrew` or
    `/usr/local`) — no sudo required to install or use. macOS only; on
    Linux the equivalent layer is Nix (`manifests/linux/flake.nix`, at the repo root).
  - `.zprofile.d/*.zsh` — numbered snippets sourced in order by `.zprofile`
    (a thin loader). Add new snippets here rather than editing `.zprofile`
    directly.
  - `Brewfile` — only what mise cannot pin: `stow`/`mise` themselves,
    formulae with no mise backend, the docker CLI plugins, and casks.
  - `.config/mise/config.toml` — every other CLI tool and runtime, pinned
    to an exact version.
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
`bootstrap.sh` (repo root -- deliberately not in a package's `.local/bin`, since it
runs `stow` itself and can't depend on `stow` having already run) is a
generic step-runner; the actual steps (package-manager install,
`stow`/`mise` install, `stow`, `sync-external-repos`, and then
`brew bundle` on macOS or `nix build` on Linux) are declared in
`manifests/common/bootstrap-steps.json`, not hardcoded in the script. Steps carry an
optional `os` field; the gate is checked before `skip_if`/`state`, since a
step for the other platform may have predicates that cannot be evaluated
here at all. Each step's `command`
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
`bootstrap.sh` -- it runs `stow`, so it can't live in a package's `.local/bin`) is
the steady-state counterpart to bootstrap: it re-links the `dev` package,
syncs external repos, runs `mise install`, and applies this platform's
package manifest (`brew bundle` on macOS, `nix build` on Linux), but does
not install Homebrew/Nix/stow/mise. On Linux it sources the Nix profile and
puts the environment on PATH before its own `stow` precondition check, so
it works from a plain non-login shell -- and rebuilds the flake *before*
stow, since stow is one of the things that build produces. Prefer it over a bare `stow -R`, which unstows using
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
- Package removal is opt-in *on macOS*. Drift is always *reported*; only
  `--prune` acts on it, and prune refuses to run if the Brewfile parses as
  empty -- otherwise a typo'd or unreadable manifest would make every
  installed package look undeclared and wipe the account. On Linux there is
  nothing to prune: the Nix environment is rebuilt whole from the flake, so
  a package that is no longer declared is already absent from it.
- It prints the full plan and waits for confirmation. `--dry-run` stops
  after the plan; `--yes` runs unattended (required when stdin isn't a
  terminal); `--no-brew` / `--no-sync` skip those steps; `--no-upgrade`
  installs missing packages without upgrading existing ones (`brew bundle`
  upgrades by default); `--no-nix` skips the flake rebuild. Transcript goes to
  `~/.local/state/dotfiles/reapply-<timestamp>.log`.

## Tests

`tests/` holds three scenarios (`tests/scenarios/01-fresh-apply.sh`,
`02-reapply.sh`, `03-step-contract.sh`) that run the real `bootstrap.sh`
(fresh apply) and `reapply.sh` (steady state) against the real manifests
in a throwaway `$HOME`, with local git repos standing in for the Homebrew and
external-repo remotes — the suite is fully offline (`--network none` in CI).
Both package managers are stubbed (`tests/stubs/homebrew`, `tests/stubs/nix`)
and the scenarios branch on `$PLATFORM` the same way the scripts do, each
branch asserting the *other* platform's steps were skipped; everything else (stow,
`prepare-stow-targets.sh`, `sync-external-repos`, the `.zprofile` chain under
real zsh) is exercised for real. Run them with
`docker build -f tests/Dockerfile -t dotfiles-ci tests/` then
`docker run --rm --network none -v "$PWD:/repo:ro" -e SOURCE_REPO=/repo dotfiles-ci /repo/tests/run-tests.sh`.
The file-level assertions are derived by walking the deployed package set, so
new managed files and directories are covered without touching the tests --
and files in the *other* platform's package are asserted absent. CI
(`.github/workflows/ci.yml`) runs every scenario twice: in the Linux container,
and natively on a macOS runner (`apply-macos`) so the suite is exercised on the
OS these dotfiles actually target -- keep the harness free of GNU-only
`stat -c` / `find -printf` for that reason. Details and limitations: `tests/README.md`.

## Configuration Structure

### Shell Configuration (`packages/unix/`, `packages/<platform>/`)
- **`.zshrc`** - prompt, fzf sourcing
- **`.zprofile`** - thin loader, sources `.zprofile.d/*.zsh` in filename order
- **`.zprofile.d/05-local-bin-path.zsh`** - `~/.local/bin` on PATH
- **`.zprofile.d/10-editor-history.zsh`** - EDITOR, history settings, nvim aliases
- **`.zprofile.d/20-pi-aliases.zsh`** - local LLM / pi agent aliases
- **`.zprofile.d/30-system-helpers.zsh`** - `diskcheck` helper
- **`.zprofile.d/45-nix.zsh`** - Linux only (guarded on `$OSTYPE`): sources
  the single-user Nix profile, puts the realised
  `~/.local/state/dotfiles/nix-env/bin` on PATH ahead of the mise snippet
  that depends on it, and carries a tripwire for a missing or
  garbage-collected environment
- **`.zprofile.d/50-homebrew-isolated.zsh`** - macOS only (guarded on
  `$OSTYPE`): isolated Homebrew shellenv,
  a `brew()` function pinning to `~/.homebrew` regardless of PATH ordering,
  and a startup tripwire warning if isolation is ever compromised
- **`.zprofile.d/55-mise.zsh`** - mise activation (must run after 50, since
  mise is installed via Homebrew and its tools must outrank brew's on PATH),
  shims appended as a fallback, plus a tripwire for a shadowed pinned tool
- **`.config/mise/config.toml`** - globally pinned CLI tools and language
  runtimes (exact versions; see the declarative principle above)
- **`.zprofile.d/60-terminal-appearance.zsh`** - Claude-Dev Terminal.app
  profile bootstrap

### Scripts (`packages/*/.local/bin`)
- **`sync-external-repos`** - clones/updates repos from `external-repos.json`
- **`link-docker-cli-plugins`** - links brew's docker plugins into
  `~/.docker/cli-plugins` (idempotent; never overwrites a real file there)
- **`link-herdr-plugins`** - registers locally authored Herdr plugins with
  Herdr (idempotent). Herdr reads a registry of absolute paths at
  `~/.config/herdr/plugins.json` instead of scanning its plugin directory,
  so stowing a plugin's files is not enough to make Herdr see it

### Neovim Configuration (`~/.config/nvim`, external repo via `sync-external-repos`)
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
