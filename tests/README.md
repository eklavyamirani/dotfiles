# Apply tests

Three scenarios that run the real `bootstrap.sh` and `reapply.sh` against the
real manifests and assert on what actually lands in `$HOME`:

| Scenario | What it covers |
| --- | --- |
| `scenarios/01-fresh-apply.sh` | Full apply from scratch: empty `$HOME`, one `./bootstrap.sh`, everything deployed. |
| `scenarios/02-reapply.sh` | Re-apply onto an existing configuration with `./reapply.sh` (the path a user takes after `git pull`): new snippets/dirs/package entries/external repos, upstream moving forward, a no-op rerun, links stranded by an upstream rename, package-manager drift, the prune guard, and the ways a re-apply is supposed to fail. |
| `scenarios/03-step-contract.sh` | The step runner's own semantics, driven over throwaway manifests: skip, halt, the exit-code-vs-state distinction, the stdin guard, and the `os` gate. |

## Two platforms, one suite

`bootstrap.sh` and `reapply.sh` gate their package-manager steps on the OS, so
the suite does the same. `lib/harness.sh` exports `$PLATFORM` (computed exactly
as the scripts compute it), stands up the stub for whichever manager this run
will reach for, and the scenarios branch on it:

| | macOS (`apply-macos` job) | Linux (container `apply` job) |
| --- | --- | --- |
| Stub | `stubs/homebrew/bin/brew` | `stubs/nix/bin/nix` |
| Packages deployed | `common unix macos` | `common unix linux` |
| Package refused | `linux` | `macos` |
| Call log | `$BREW_CALL_LOG` | `$NIX_CALL_LOG` |
| Drift model | Brewfile vs installed, `--prune` | flake package list vs the linked store path |

Each branch also asserts that the *other* platform's steps were **skipped**,
not silently run — a gate that let both through would install Homebrew on
Linux, and one that let neither through would leave a half-applied account
that still reported success.

Both stubs are guarded: `$SANDBOX/guardbin` holds a `brew` and a `nix` that
refuse and exit 127. If the stub ever fails to land ahead of them on `PATH`,
the scenario fails loudly instead of quietly driving the real package manager
on the developer's machine.

## Running them

```bash
docker build -f tests/Dockerfile -t dotfiles-ci tests/
docker run --rm --network none -v "$PWD:/repo:ro" -e SOURCE_REPO=/repo \
  dotfiles-ci /repo/tests/run-tests.sh            # both scenarios
docker run --rm --network none -v "$PWD:/repo:ro" -e SOURCE_REPO=/repo \
  dotfiles-ci /repo/tests/run-tests.sh 02-reapply # just one
```

`tests/run-tests.sh` also runs directly on any Linux box with `bash`, `git`,
`python3`, `stow` and `zsh`; the container just guarantees a bare account.
Everything a scenario touches lives in a throwaway sandbox under `$TMPDIR`, and
`$HOME` is redirected there — running the suite never touches your real home
directory. The suite is portable: it runs natively on macOS too (that is what
the `apply-macos` CI job does), so it avoids GNU-only `stat -c` and
`find -printf`. Running it natively needs `stow` on PATH.

## How the sandbox works

Each scenario builds a self-contained world:

- **`$HOME`** is a fresh empty directory; the repository under test is copied
  (working tree as it sits on disk, uncommitted edits included) to
  `$HOME/dotfiles` and committed, so scenarios can mutate and re-commit it and
  assert the deploy never writes back into it.
- **Remotes are local.** `git config --global url.<file://…>.insteadOf` rewrites
  `https://github.com/Homebrew/brew` and the external-repo URLs to git repos in
  the sandbox. Nothing is edited in `manifests/common/bootstrap-steps.json` or
  `external-repos.json` — the manifests under test ship exactly as they run in
  CI, and the suite passes with `--network none`.
- **Homebrew is stubbed** (`stubs/homebrew/bin/brew`, cloned in place of the
  real Homebrew repo). It logs every call to `$BREW_CALL_LOG`, implements
  `shellenv`/`--prefix`/`install`/`bundle`, creates shims in
  `$HOMEBREW_PREFIX/bin` (exec'ing the container's real binary when there is
  one, so `stow` is the real `stow`), and **fails hard if its prefix is ever
  outside `$HOME`** — the isolation invariant is an assertion, not a comment.
- **Nix is stubbed** (`stubs/nix/bin/nix`). It derives a fake store path from
  the package list in `manifests/linux/flake.nix`, so the same list yields the same path
  and any edit yields a different one — which is what makes `reapply.sh`'s
  drift comparison testable from the real manifest rather than from a
  hardcoded answer. `build --out-link` creates the symlink-into-the-store
  shape that `45-nix.zsh` and the scripts depend on; `eval --raw …outPath`
  answers without building, which is what lets `reapply.sh` plan before it
  acts.
- **The Nix *installer* is not run.** It is `curl https://nixos.org/nix/install
  | sh`, which needs the network and would create a real `/nix` with `sudo`.
  Unlike the Homebrew clone, there is no URL to rewrite. So `sandbox_seed_nix`
  produces the state that step *declares* — a profile script at
  `~/.nix-profile/etc/profile.d/nix.sh` — and the runner then skips the step
  through its own `state` predicate, which the scenario asserts. Everything
  downstream of the installer (loading the profile, building the flake, the
  out-link, `45-nix.zsh`'s `PATH` ordering) runs for real against the stub.

## What is real and what is not

Real: `bootstrap.sh`'s step runner, ordering, `skip_if` handling and halt-on-
failure; `reapply.sh`'s plan/prune/backup logic and its failsafes;
`manifests/common/bootstrap-steps.json`; `prepare-stow-targets.sh`; `stow`;
`sync-external-repos` with real `git clone` / `git pull --ff-only`; the deployed
`.zprofile` chain loaded by real `zsh`; the `Brewfile` parsed into the package
list bootstrap asks Homebrew for; `link-docker-cli-plugins`.

Not real: the package managers themselves, and therefore the packages.
Installing real Homebrew in CI would download hundreds of MB and build Linux
bottles for formulae (`colima`, `hf`, …) that the macOS side never uses on
Linux; a real `nix build` would fetch a nixpkgs revision and its whole closure
from `cache.nixos.org`, which `--network none` forbids outright. Both are slow
and flaky enough to make the signal worse, not better. What the tests do assert is
that bootstrap asks Homebrew for exactly the right things (`install stow mise`,
`bundle --file=<repo>/manifests/macos/Brewfile`, every non-commented `Brewfile` entry) and
that it does so against `~/.homebrew`, and — for `reapply.sh` — that drift is
computed from what the stub records as installed versus what the Brewfile
declares. On Linux the equivalent assertions are that `nix build` was pointed at
`manifests/linux/flake.nix` and the expected out-link, that `--extra-experimental-features`
was passed on the command line (the stowed `nix.conf` does not exist yet at
that point in a fresh apply), and that every package the flake declares came
out in the built environment.

`mise` is a no-op shim, so the tests assert that `mise install` is invoked and
that no manifest claims a tool mise pins — checked against the Brewfile *and*
the flake on both platforms, since both files ship to both machines — not that
anything is downloaded. macOS-only behaviour
(`60-terminal-appearance.zsh`'s Terminal.app import, `.macos` defaults) is not
covered — it no-ops off macOS.

One asymmetry worth knowing: the container reports `OSTYPE=linux*` to `zsh`
even if `uname` is faked, so the `$OSTYPE`-guarded snippets
(`50-homebrew-isolated.zsh`, `45-nix.zsh`) can only be exercised on the runner
whose OS they are actually for. The `apply-macos` job is what covers the
Homebrew snippet; the container covers the Nix one.

## Adding to them

The file-level assertions walk the package set this platform deploys
(`packages/{common,unix,<platform>}`) and derive what stow should link, so a
new managed file or directory is covered automatically — no test edit needed.
They also walk the *other* platform's package and assert every file in it is
absent, which is what catches a foreign package leaking into `$HOME`.
A new `scenarios/NN-name.sh` (source `lib/harness.sh`, call `sandbox_create`,
`trap sandbox_destroy EXIT`, end with `finish`) is picked up by
`run-tests.sh` automatically; add it to the matrix in
`.github/workflows/ci.yml` — to **both** the `apply` (Linux container) and
`apply-macos` (native) jobs — to give it its own CI check.
