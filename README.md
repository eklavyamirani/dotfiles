# dotfiles

Stow-based dotfiles for an isolated, non-admin macOS account
that owns all development tooling (CLI tools and
runtimes pinned with mise; an isolated Homebrew in `~/.homebrew`, no sudo
required; neovim; pi/llama-server configs). The paired
main/admin account is deliberately minimal and its profile is kept only as
a frozen snapshot in `archive/admin/` (see its README) until it moves to
its own repository.

The same `./bootstrap.sh` and `./reapply.sh` also deploy this package on
**Linux**. Only the package-manager layer differs — Nix takes Homebrew's
place there — and it differs in exactly one place, the `os` field in
`manifests/common/bootstrap-steps.json`. Everything downstream is shared, so both machines
run the same shell, the same stow package, and the same mise-pinned tool
versions. See [Linux](#linux-nix-instead-of-homebrew) below.

## Layout

```
lib/platform.sh                 the only place that calls uname
packages/  common/              every platform, Windows milestone included
           unix/                the zsh chain macOS and Linux share
           macos/  linux/       only what is genuinely platform-specific
manifests/ common/              bootstrap-steps.json
           macos/               Brewfile
           linux/               flake.nix + flake.lock
```

A file's **package is its platform declaration**. Nothing under `packages/`
needs an `$OSTYPE` guard, because it never reaches the other machine — which
is why `stow-packages.sh` refuses to deploy a foreign platform's package: with
the guards gone, a leaked link is no longer inert, it breaks every login
shell.

Snippet numbering in `.zprofile.d/` still sorts globally across packages,
because stow merges them into a single `~/.zprofile.d/`. No reserved ranges
are needed: two packages picking the same number is harmless, and the only
ordering that actually matters — the package manager before `55-mise.zsh` — is
already encoded. The one thing packages must not do is ship the *same
filename*, which is a stow conflict; the test suite asserts that.

## Deploy

On the isolated dev account, the normal path is `./bootstrap.sh` (see
"Bootstrap a new dev account" below). The equivalent manual steps, if you
already have `stow` and this platform's package manager:
```bash
git clone https://github.com/eklavyamirani/dotfiles ~/dotfiles && cd ~/dotfiles
./stow-packages.sh                 # common + unix + this platform
~/.local/bin/sync-external-repos   # fetches the Neovim config
```

`stow-packages.sh` is the single definition of *which* packages get deployed
and the guard against deploying another platform's; both `bootstrap.sh` and
`reapply.sh` go through it rather than calling `stow` themselves.

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
(package-manager install, `stow`/`mise` install, `stow`,
`sync-external-repos`, `brew bundle` or `nix build`) live in
`manifests/common/bootstrap-steps.json`, not hardcoded in the script.
To change what bootstrap does, edit that manifest -- `bootstrap.sh` itself
shouldn't need touching. Each step entry has:

```json
{
  "name": "install Homebrew into ~/.homebrew",
  "command": "git clone https://github.com/Homebrew/brew \"$HOME/.homebrew\"",
  "state": "[ -x \"$HOME/.homebrew/bin/brew\" ]",
  "purpose": "Isolated Homebrew -- never /opt/homebrew or /usr/local"
}
```

- `name`, `command` -- required. `command` is a shell string run via
  `eval` **in the same process** (not a subshell), so `export`/`PATH`
  changes from one step (e.g. loading Homebrew's `shellenv`) persist to
  later steps, the way sourcing would in an interactive shell.
- `state` -- optional shell condition describing **the state the step
  exists to produce**. Checked twice: before the command (holds -> skip,
  the work is already done) and again after it if the command reported
  failure.
- `skip_if` -- optional shell condition meaning **this step has no work to
  do**, which is not the same claim as `state` (the `mise install` step
  has nothing to do when no mise config was stowed, but "no config" is not
  the outcome that step exists to produce). If it exits `0`, the step is
  skipped.
- `os` -- optional, `"macos"` or `"linux"`. The step runs only on that
  platform; elsewhere it is skipped with
  `(skipped, declared for <os>, this is <platform>)`. This is the *only*
  place the two machines diverge, and the gate is checked **before**
  `skip_if` and `state`, because a step for the other OS may have
  predicates that cannot be evaluated here at all (`brew shellenv` on
  Linux). Omit it for the steps that are the same everywhere -- stow,
  `sync-external-repos`, `mise install`.
- `purpose` -- optional, shown in logs.

It halts immediately on the first failing step (later steps depend on
earlier ones succeeding), and writes a full transcript of every step's
output to `~/.local/state/dotfiles/setup-<timestamp>.log` regardless of
outcome, so a failure always leaves you with complete detail to diagnose.
Every step is idempotent (or guarded by `skip_if`/`state`), so it's always
safe to fix the issue and rerun.

**A step fails when its declared `state` was not reached** -- the exit code
is the fallback, used only for steps that declare no state. A command that
exits non-zero but leaves the declared state satisfied is logged as
`WARNING: command exited N, but the declared state was reached` and the run
continues. This is not leniency for its own sake: `brew install` exits `1`
when a formula's post-install hook flakes even though every requested
formula installed, and Homebrew has a single failure exit code
(`exit Homebrew.failed? ? 1 : 0`) shared with a genuinely missing formula.
No exit code can separate those two; only the resulting state can. Keying
success off the exit status alone once halted a bootstrap after a 92-minute
`mise` build over a cert symlink unrelated to the step's purpose. The
`WARNING` keeps the discrepancy visible rather than swallowing it, and a
step that fails *without* reaching its state still halts the run as before.

This account's Homebrew never touches `/opt/homebrew` or `/usr/local` and
never requires an admin password. A startup tripwire in
`packages/macos/.zprofile.d/50-homebrew-isolated.zsh` warns if isolation is ever
compromised (e.g. another account's Homebrew leaks onto `PATH`). That
snippet is guarded on `$OSTYPE`, so on Linux it is inert rather than
failing every login shell on a missing `~/.homebrew`.

### Linux: Nix instead of Homebrew

`./bootstrap.sh` and `./reapply.sh` work unchanged on Linux. What differs is
only the layer Homebrew occupies on macOS:

| | macOS | Linux |
| --- | --- | --- |
| Package manager | Homebrew in `~/.homebrew` | Nix, single-user |
| Manifest for what mise can't pin | `manifests/macos/Brewfile` | `manifests/linux/flake.nix` |
| Applied by | `brew bundle` | `nix build` into `~/.local/state/dotfiles/nix-env` |
| Shell snippet | `50-homebrew-isolated.zsh` | `45-nix.zsh` |
| Removing a package | delete the line, `./reapply.sh --prune` | delete the line, `./reapply.sh` |
| CLI tools + runtimes | `packages/common/.config/mise/config.toml` | same file, same pins |
| Docker CLI plugins | `link-docker-cli-plugins` | not needed (distro packaging already places them) |

Bootstrap installs Nix **single-user** with
`--no-daemon --yes --no-channel-add --no-modify-profile`. Two of those flags
are load-bearing rather than taste:

- `--no-channel-add`, because the package set comes from the flake, not from
  a channel; adding `nixpkgs-unstable` as a channel would be a second,
  unpinned source of the same packages.
- `--no-modify-profile`, because the installer appends its snippet to the
  first writable one of `~/.bash_profile`, `~/.profile`, `~/.zshenv`,
  `~/.zshrc` — and `~/.zshrc` is a **stow symlink into this repository**, so
  without that flag the installer would write into the tracked file.
  `packages/linux/.zprofile.d/45-nix.zsh` sources the profile script instead.

`/nix` is created once with `sudo` by the installer and owned outright by
your account afterwards.

#### Login vs non-login shells

zsh reads `.zprofile` for **login** shells only. macOS Terminal.app starts one,
so this is invisible there; most Linux terminal emulators (GNOME Terminal,
Konsole, …) start a **non-login interactive** shell, which reads only
`.zshrc`. Left alone, that yields the worst kind of failure: a fully deployed
machine that behaves as though nothing were installed — no `mise`, no pinned
tools, no aliases, and no error to explain it.

So `packages/unix/.zshrc` sources `~/.zprofile` when zsh has not already done
it, guarded by a sentinel `.zprofile` exports so login shells don't do the work
twice and subshells don't re-run `compinit` and `mise activate`.

#### The login shell

Everything this repository configures lives in `.zprofile`, `.zprofile.d/`
and `.zshrc`. On macOS that is free, because zsh is already the default login
shell. On a distribution that defaults to **bash the entire deployment is
inert** — the tools are installed, the links are correct, and nothing ever
reaches `PATH`, because nothing sources the profile. So bootstrap has two
Linux-only steps that register `~/.local/state/dotfiles/nix-env/bin/zsh` in
`/etc/shells` and `chsh` to it.

Both need root and are guarded by `skip_if: ! sudo -n true`, so on a machine
without passwordless sudo they skip rather than halting the run — everything
else still applies, and you finish the job by hand:

```bash
zsh_path="$HOME/.local/state/dotfiles/nix-env/bin/zsh"
printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null
chsh -s "$zsh_path"
```

> [!WARNING]
> The login shell now points at a **Nix out-link**. That is the trade-off for
> having it pinned by `flake.lock` like every other package. If
> `~/.local/state/dotfiles/nix-env` is ever deleted, new shells fail to
> start — and because `sshd` and the console both invoke the login shell,
> you cannot simply SSH in to fix it. Recovery is via another account or
> GRUB recovery mode (`chsh -s /bin/bash <user>`).
>
> **Before removing or relocating `~/.local/state/dotfiles`, run
> `chsh -s /bin/bash` first.**
>
> For the same reason, both steps are skipped unless `$HOME` really is this
> account's home directory. `sudo chsh` acts on the **account**, not on
> `$HOME`, so running bootstrap against a throwaway `$HOME` is *not*
> sandboxed — one such run repointed the real login shell at a path under
> `/tmp`, which would have locked the account out of every new shell once that
> directory was cleaned up. Ordinary `nix-collect-garbage` is safe: the
> out-link is a GC root, which is exactly why `nix build --out-link` is used
> rather than a bare build.

Together with `/nix`, those are the only two places the "no sudo, ever"
property above does not hold on Linux, and neither has an alternative:
`/nix` cannot be created unprivileged, and `chsh` will not accept a shell
missing from `/etc/shells`.

#### Why Nix rather than Homebrew-on-Linux

Homebrew does run on Linux, and reusing it would have meant one manifest
instead of two. It was not worth it:

- `flake.lock` pins an **exact** nixpkgs revision, which is the property
  this repository already wants everywhere else and the one Homebrew
  [cannot provide](#what-pins-what-mise-for-tools-homebrew-for-the-rest).
  The Linux side is therefore *more* reproducible than the macOS side, not
  less.
- The environment is rebuilt **whole** on every apply, so deleting a line
  from `manifests/linux/flake.nix` removes the package. There is no Linux equivalent of
  `--prune`, and no drift to report in the "installed but undeclared"
  direction, because that state cannot persist.
- The Brewfile's cask and the `audio-cpp` tap are macOS-only anyway, so a
  shared Brewfile would have needed per-OS gating inside it regardless.

`manifests/linux/flake.nix` lives under `manifests/`, not in a stow package,
because of the rule that decides which tree anything here belongs in:

> **`manifests/<platform>/` is applied *from* the repository.
> `packages/<pkg>/` is deployed *into* `$HOME`.**

The Brewfile, the flake and the bootstrap step list are read in place by
`bootstrap.sh`/`reapply.sh`, so they are manifests. `packages/common/.config/mise/config.toml`
is the awkward one: conceptually the most "common manifest" in the repo, but
mise reads it from `~/.config/mise/config.toml`, so it must be stowed and is a
package. Getting this backwards is how a pointless `~/Brewfile` symlink and a
stray `~/nix/` directory both appeared.

#### mise comes from `nixos-unstable`, and only mise

`manifests/linux/flake.nix` takes `nixpkgs` from `nixos-26.05` but pulls `mise` from
`nixos-unstable`. Both are pinned by `flake.lock`, so this is not "track the
newest"; it is a correctness requirement. mise ships its **tool registry**
(the name → backend mapping) inside the binary, so an mise a few months old
cannot resolve a tool added to the registry since — and that is a hard
`mise ERROR <tool> not found in mise tool registry` that halts bootstrap,
not a cosmetic lag. Stable 26.05 carries mise 2026.5.12, which does not know
`herdr`; unstable carries 2026.8.6, which does. Since
`packages/common/.config/mise/config.toml` is shared with macOS, where Homebrew tracks
mise's tip, a stale mise here would mean the two machines could not run the
same manifest at all.

To bump either pin: `nix flake update --flake ./nix`, then commit the
`flake.lock` change.

### What pins what: mise for tools, Homebrew for the rest

Tooling is split between two manifests, and the split is not stylistic:

| Manifest | Owns | Pinned? | Rollback? |
| --- | --- | --- | --- |
| `packages/common/.config/mise/config.toml` | CLI tools + language runtimes | yes, exact versions | yes |
| `manifests/macos/Brewfile` (macOS) | bootstrap deps, formulae with no mise backend, docker CLI plugins, casks | no | no |
| `manifests/linux/flake.nix` (Linux) | bootstrap deps, packages with no mise backend | yes, via `flake.lock` | yes |

The split is the same on both machines; only the second row changes. mise
owns every tool it has a backend for either way, so the pinned tool
versions are identical across macOS and Linux.

Homebrew was the default here and cannot be made reproducible. Upstream is
explicit that `brew bundle` "does not and will not have a concept of a
`Brewfile` lock file"
([Brew-Bundle-and-Brewfile.md](https://docs.brew.sh/Brew-Bundle-and-Brewfile)),
there is no `brew rollback`, and the alternatives in
[Versions.md](https://docs.brew.sh/Versions) each disclaim themselves:
`brew pin` blocks dependent upgrades and stops security updates,
`HOMEBREW_NO_AUTO_UPDATE` does not stop `brew upgrade`, and `brew extract`
makes you the maintainer of a formula in your own tap. On top of that, this
account installs Homebrew to `~/.homebrew`, and the default prefix "is
required for most bottles (binary packages) to be used"
([Installation.md](https://docs.brew.sh/Installation)) — so most formulae
here were compiled from source on every fresh machine.

mise has none of those problems: exact versions in a tracked file, prebuilt
binaries from its aqua/ubi backends, side-by-side installs, no sudo. So
everything mise has a backend for moved (see
[#4](https://github.com/eklavyamirani/dotfiles/issues/4)):
`gh`, `fzf`, `ripgrep`, `tmux`, `neovim`, `tree-sitter`, `colima`, `docker`
and `python`.

#### Rolling back a tool

Side-by-side installs make this an edit, not a repair:

```bash
$EDITOR packages/common/.config/mise/config.toml   # neovim = "0.12.5" -> "0.12.4"
mise install                           # or ./reapply.sh
git commit -am 'pin neovim 0.12.4'
```

The version you rolled off stays on disk under
`~/.local/share/mise/installs/<tool>/<version>`, so rolling forward again is
instant and offline. Nothing is deduplicated, though — each version is a
full copy. `mise prune` reclaims versions no config references if disk gets
tight.

To bump a pin, `mise use -g <tool>@<version>` and commit the resulting diff.
Never write `latest` or a `~>` range in that file: an inexact pin is the
behaviour this split exists to eliminate.

#### What is still unpinned

Being honest about the remaining surface, since a table that quietly
overclaims is worse than no table:

- **`mise` itself, on macOS.** It is installed by `brew install mise`, which
  gives whatever is current — the bootstrapper cannot bootstrap itself.
  Accepted rather than solved: mise's version does not determine the tool
  versions it installs, so a drifting mise still converges the account to
  the pins in `config.toml`. **On Linux this gap does not exist**: mise
  comes from the flake and is pinned by `flake.lock` like everything else.
- **`git`, `tree`, `hf`, `audio-cpp`** — no mise backend exists (checked
  against mise's registry), so on macOS they stay unpinned Homebrew
  formulae. On Linux the ones that apply (`git`, `tree`) are in
  `manifests/linux/flake.nix` and *are* pinned; `hf` and `audio-cpp` are macOS-only
  concerns and are simply absent there.
- **`docker-buildx`, `docker-compose`** — docker CLI *plugins*, resolved
  from `~/.docker/cli-plugins` rather than `PATH`, wired there from the
  Homebrew prefix by `packages/macos/.local/bin/link-docker-cli-plugins`. `buildx` has
  no mise backend; `docker-compose` does, but moving it alone would break
  `docker compose` unless that script learned a second source directory.
  macOS only: both the formulae and the linking step are gated to Darwin,
  since on Linux the distribution's own docker packaging already puts the
  plugins where the CLI looks.
- **Casks.** `brew bundle` is the only thing here that manages `.app`
  bundles at all. macOS only by definition.
- **External repos.** `sync-external-repos` tracks branch tips with no
  commit pinning (see below) — a separate, still-open gap.

`packages/unix/.zprofile.d/55-mise.zsh` activates mise after whichever package manager
supplied it — Homebrew at `50-` on macOS, Nix at `45-` on Linux — so pinned
tools win over a same-named formula or nixpkgs package, appends mise's shims
directory as a fallback
for processes that never source `.zprofile`, and carries its own tripwire
warning if a pinned tool resolves outside `$HOME`.

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
declared in `packages/common/.config/external-repos.json` (stowed to
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

### `packages/*/.config` is allowlisted, not blocklisted

`.gitignore` ignores all of `packages/*/.config/*` by default and explicitly
un-ignores only the specific configs meant to be tracked (currently
`terminal/`, `llama-server/`, `mise/config.toml`, `external-repos.json`). This is deliberate:
many CLI tools write credential/token files into their `~/.config/<tool>`
directory over time (OAuth tokens, API keys, session state), and a
blocklist approach requires remembering to add every such path -- one
missed entry and a `git add -A` silently commits a secret. To track a new
tool's config, add explicit `!packages/<pkg>/.config/<tool>/` and
`!packages/<pkg>/.config/<tool>/**` un-ignore lines to `.gitignore`.

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

Three scenarios cover the deploy end to end -- a full apply from scratch, a
re-apply of new changes onto an already-configured account, and the step
runner's own contract (including the `os` gate). They run the real
`bootstrap.sh` and `reapply.sh` against the real manifests, with local git
repositories standing in for the Homebrew and external-repo remotes, so the
whole suite runs offline (`--network none` in CI).

Both package managers are stubbed, and the scenarios branch on the platform
the same way the scripts do: the Linux container exercises the Nix path, the
macOS runner exercises the Homebrew path, and each asserts that the *other*
platform's steps were skipped rather than silently running.

```bash
docker build -f tests/Dockerfile -t dotfiles-ci tests/
docker run --rm --network none -v "$PWD:/repo:ro" -e SOURCE_REPO=/repo \
  dotfiles-ci /repo/tests/run-tests.sh
```

Both run on every push and pull request (`.github/workflows/ci.yml`). The
workflow also has an `apply tests` job that passes only if every scenario in
the matrix passed -- mark that one as the required status check on `main`
rather than the individual `apply (...)` jobs, so adding or renaming a
scenario can't leave a required check that never reports. See
`tests/README.md` for what is real, what is stubbed, and why.
