# Apply tests

Two container scenarios that run the real `bootstrap.sh` against the real
manifests and assert on what actually lands in `$HOME`:

| Scenario | What it covers |
| --- | --- |
| `scenarios/01-fresh-apply.sh` | Full apply from scratch: empty `$HOME`, one `./bootstrap.sh`, everything deployed. |
| `scenarios/02-reapply.sh` | Re-apply onto an existing configuration: new snippets/dirs/Brewfile entries/external repos, upstream moving forward, a third no-op run, and the two ways a re-apply is supposed to fail. |

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
directory. It is macOS-hostile only in that `stat -c` and `find -printf` are
GNU-only, so run it in the container on a Mac.

## How the sandbox works

Each scenario builds a self-contained world:

- **`$HOME`** is a fresh empty directory; the repository under test is copied
  (working tree as it sits on disk, uncommitted edits included) to
  `$HOME/dotfiles` and committed, so scenarios can mutate and re-commit it and
  assert the deploy never writes back into it.
- **Remotes are local.** `git config --global url.<file://…>.insteadOf` rewrites
  `https://github.com/Homebrew/brew` and the external-repo URLs to git repos in
  the sandbox. Nothing is edited in `bootstrap-steps.json` or
  `external-repos.json` — the manifests under test ship exactly as they run in
  CI, and the suite passes with `--network none`.
- **Homebrew is stubbed** (`stubs/homebrew/bin/brew`, cloned in place of the
  real Homebrew repo). It logs every call to `$BREW_CALL_LOG`, implements
  `shellenv`/`--prefix`/`install`/`bundle`, creates shims in
  `$HOMEBREW_PREFIX/bin` (exec'ing the container's real binary when there is
  one, so `stow` is the real `stow`), and **fails hard if its prefix is ever
  outside `$HOME`** — the isolation invariant is an assertion, not a comment.

## What is real and what is not

Real: `bootstrap.sh`'s step runner, ordering, `skip_if` handling and halt-on-
failure; `bootstrap-steps.json`; `prepare-stow-targets.sh`; GNU `stow`;
`sync-external-repos` with real `git clone` / `git pull --ff-only`; the deployed
`.zprofile` chain loaded by real `zsh`; the `Brewfile` parsed into the package
list bootstrap asks Homebrew for.

Not real: Homebrew itself, and therefore the packages. Installing real Homebrew
in CI would download hundreds of MB and build Linux bottles for formulae
(`colima`, `hf`, …) that this macOS-only setup never uses on Linux — slow and
flaky enough to make the signal worse, not better. What the tests do assert is
that bootstrap asks Homebrew for exactly the right things (`install stow mise`,
`bundle --file=<repo>/dev/Brewfile`, every non-commented `Brewfile` entry) and
that it does so against `~/.homebrew`. macOS-only behaviour
(`60-terminal-appearance.zsh`'s Terminal.app import, `.macos` defaults) is not
covered — it no-ops off macOS.

## Adding to them

The file-level assertions walk `dev/` and derive what stow should deploy, so a
new managed file or directory is covered automatically — no test edit needed.
A new `scenarios/NN-name.sh` (source `lib/harness.sh`, call `sandbox_create`,
`trap sandbox_destroy EXIT`, end with `finish`) is picked up by
`run-tests.sh` automatically; add it to the matrix in
`.github/workflows/ci.yml` to give it its own CI check.
