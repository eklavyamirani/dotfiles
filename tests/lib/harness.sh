# shellcheck shell=bash
# Assertions + sandbox construction shared by the scenarios in tests/scenarios/.
#
# A "sandbox" is a throwaway $HOME plus a set of local git repositories that
# stand in for the remotes bootstrap would otherwise fetch over the network
# (Homebrew and the external nvim config). Everything a scenario touches lives
# under that directory, so scenarios never see each other's state and the whole
# suite runs offline.
#
# The suite runs on both platforms the dotfiles target, and bootstrap.sh's
# manifest gates its package-manager steps on the OS, so the sandbox stands up
# whichever manager this machine's run will actually reach for: the Homebrew
# stub on macOS, the Nix stub on Linux. $PLATFORM below is the same value
# bootstrap.sh and reapply.sh compute for themselves, so a scenario branching
# on it is branching the way the code under test just did.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_REPO="${SOURCE_REPO:-$(cd "$TESTS_DIR/.." && pwd)}"

# Sourced, not recomputed: the suite must branch on exactly the value the
# scripts under test branch on, and lib/platform.sh is the only place that
# reads `uname`. A second copy here is how a test starts passing for the wrong
# reason after the mapping changes.
# shellcheck source=../../lib/platform.sh
. "$TESTS_DIR/../lib/platform.sh"

# The package set a scenario expects to be deployed on this machine.
PACKAGE_SET=()
while IFS= read -r _pkg; do PACKAGE_SET+=("$_pkg"); done < <(platform_package_set)
# The platform package that must NOT be deployed here.
case "$PLATFORM" in
  macos) FOREIGN_PACKAGE=linux ;;
  *)     FOREIGN_PACKAGE=macos ;;
esac
export PLATFORM FOREIGN_PACKAGE

CHECKS=0
FAILURES=0
CURRENT_SCENARIO="${CURRENT_SCENARIO:-scenario}"

_pass() { CHECKS=$((CHECKS + 1)); printf '  ok   %s\n' "$1"; }
_fail() {
  CHECKS=$((CHECKS + 1))
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$1"
  [ $# -gt 1 ] && printf '       %s\n' "$2"
  return 0
}

section() { printf '\n== %s\n' "$*"; }

assert_true() { # desc, command...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _pass "$desc"; else _fail "$desc" "command failed: $*"; fi
}

assert_false() { # desc, command...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _fail "$desc" "command unexpectedly succeeded: $*"; else _pass "$desc"; fi
}

assert_eq() { # desc, expected, actual
  if [ "$2" = "$3" ]; then _pass "$1"; else _fail "$1" "expected [$2], got [$3]"; fi
}

assert_symlink_to() { # desc, link, expected target
  local desc="$1" link="$2" want="$3" got
  if [ ! -L "$link" ]; then
    _fail "$desc" "$link is not a symlink"
    return 0
  fi
  got="$(readlink -f "$link")"
  if [ "$got" = "$(readlink -f "$want")" ]; then
    _pass "$desc"
  else
    _fail "$desc" "$link -> $(readlink "$link") (resolves to ${got:-nothing}), expected $want"
  fi
}

assert_real_dir() { # desc, path
  if [ -d "$2" ] && [ ! -L "$2" ]; then _pass "$1"; else _fail "$1" "$2 is not a real (non-symlink) directory"; fi
}

assert_exists()  { if [ -e "$2" ]; then _pass "$1"; else _fail "$1" "$2 does not exist"; fi; }
assert_missing() { if [ ! -e "$2" ]; then _pass "$1"; else _fail "$1" "$2 exists but should not"; fi; }

assert_file_has() { # desc, file, extended regex
  if [ -f "$2" ] && grep -Eq -- "$3" "$2"; then
    _pass "$1"
  else
    _fail "$1" "no match for /$3/ in $2"
  fi
}

assert_file_lacks() { # desc, file, extended regex
  if [ -f "$2" ] && grep -Eq -- "$3" "$2"; then
    _fail "$1" "unexpected match for /$3/ in $2"
  else
    _pass "$1"
  fi
}

finish() {
  printf '\n-- %s: %d checks, %d failures\n' "$CURRENT_SCENARIO" "$CHECKS" "$FAILURES"
  [ "$FAILURES" -eq 0 ] || exit 1
  exit 0
}

# ---------------------------------------------------------------------------
# Sandbox
# ---------------------------------------------------------------------------

sandbox_create() {
  # ${TMPDIR%/}: on macOS TMPDIR ends with a slash, which would put a doubled
  # slash inside $HOME ("/tmp//sandbox/home"). Anything that compares $HOME
  # against a normalised path (`cd ... && pwd`) then mismatches -- which is
  # exactly how the Homebrew stub once concluded its own prefix was outside
  # HOME, silently fell back to PATH, and let the real brew run.
  local tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  SANDBOX="$(mktemp -d "$tmp_root/dotfiles-ci.XXXXXXXX")"
  export SANDBOX
  export HOME="$SANDBOX/home"
  export ORIGINS="$SANDBOX/origins"
  export BREW_CALL_LOG="$SANDBOX/brew-calls.log"
  export BREW_SHIM_LOG="$SANDBOX/shim-calls.log"
  export NIX_CALL_LOG="$SANDBOX/nix-calls.log"
  export NIX_SHIM_LOG="$SANDBOX/nix-shim-calls.log"
  export NIX_STORE_ROOT="$SANDBOX/nix-store"
  export NIX_ENV="$HOME/.local/state/dotfiles/nix-env"
  REPO="$HOME/dotfiles"
  mkdir -p "$HOME" "$ORIGINS" "$NIX_STORE_ROOT"
  : >"$BREW_CALL_LOG"
  : >"$NIX_CALL_LOG"

  # Safety net. bootstrap.sh calls plain `brew` after loading the stub's
  # shellenv; if that eval ever fails, PATH still holds the developer's (or the
  # runner's) real Homebrew and the run would quietly install and upgrade real
  # packages on the real machine. This guard sits ahead of them on PATH, so the
  # stub is used or the scenario fails loudly -- never the real thing.
  mkdir -p "$SANDBOX/guardbin"
  cat >"$SANDBOX/guardbin/brew" <<'GUARD'
#!/bin/sh
printf 'test guard: the real brew was invoked (%s).\n' "$*" >&2
printf 'The sandbox stub should have been on PATH first -- refusing.\n' >&2
exit 127
GUARD
  chmod +x "$SANDBOX/guardbin/brew"

  # The same safety net for Nix, and it matters more here than for brew: a
  # developer running this suite on Linux very likely has a real Nix, and a
  # leaked `nix build` would reach the network the container job forbids and
  # write into the real /nix store.
  cat >"$SANDBOX/guardbin/nix" <<'GUARD'
#!/bin/sh
printf 'test guard: the real nix was invoked (%s).\n' "$*" >&2
printf 'The sandbox stub should have been on PATH first -- refusing.\n' >&2
exit 127
GUARD
  chmod +x "$SANDBOX/guardbin/nix"

  sandbox_seed_nix

  git config --global user.name  'Dotfiles CI'
  git config --global user.email 'ci@example.invalid'
  git config --global init.defaultBranch main
  git config --global advice.detachedHead false
  git config --global --add safe.directory '*'

  # Stand-ins for the two remotes bootstrap clones. Rewriting the URLs rather
  # than editing the manifests keeps bootstrap-steps.json and
  # external-repos.json under test exactly as they ship.
  origin_from_dir homebrew "$TESTS_DIR/stubs/homebrew"
  origin_new nvim-config
  git config --global "url.file://$ORIGINS/homebrew.insteadOf" 'https://github.com/Homebrew/brew'
  git config --global "url.file://$ORIGINS/nvim-config.insteadOf" 'https://github.com/eklavyamirani/nvim-config'

  sandbox_checkout_repo
}

# Stand in for bootstrap's "install Nix (single-user)" step.
#
# That step is the one thing here that cannot be faked by rewriting a git URL
# the way the Homebrew clone is: it is `curl https://nixos.org/nix/install |
# sh`, which needs the network and would create a real /nix using sudo. So the
# sandbox produces the state that step declares instead -- a profile script at
# ~/.nix-profile/etc/profile.d/nix.sh -- and the runner then skips the step
# through its own `state` predicate, which is itself worth exercising.
#
# The limitation is deliberate and documented in tests/README.md: the
# installer's own command line is never executed by the suite. Everything
# downstream of it -- loading the profile, building the flake, the out-link,
# the PATH ordering in 45-nix.zsh -- runs for real against the stub.
sandbox_seed_nix() {
  local profile_dir="$HOME/.nix-profile/etc/profile.d"
  mkdir -p "$profile_dir" "$HOME/.nix-profile/bin"
  ln -sfn "$TESTS_DIR/stubs/nix/bin/nix" "$HOME/.nix-profile/bin/nix"
  cat >"$profile_dir/nix.sh" <<'PROFILE'
# Stand-in for the profile script a single-user Nix install writes. It mirrors
# the one thing about the real script these tests depend on: it puts nix on
# PATH, ahead of the guard that would otherwise refuse the call.
export PATH="$HOME/.nix-profile/bin:$PATH"
PROFILE
}

sandbox_destroy() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# Copy the tree under test into the sandbox HOME and make it a git repo, so
# scenarios can commit changes to it (and assert the deploy never writes back
# into it). Copying rather than `git clone` means the working tree as it
# currently sits on disk is what gets tested, uncommitted edits included.
sandbox_checkout_repo() {
  mkdir -p "$REPO"
  tar -C "$SOURCE_REPO" --exclude=./.git -cf - . | tar -C "$REPO" -xf -
  git -C "$REPO" init --quiet
  git -C "$REPO" add -A
  git -C "$REPO" commit --quiet -m 'checkout under test'
}

origin_new() { # name -- an empty-ish repo with one commit
  local name="$1" dir="$ORIGINS/$1"
  git init --quiet "$dir"
  printf -- '-- %s, stand-in remote for the dotfiles CI tests\n' "$name" >"$dir/README.md"
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m 'initial'
}

origin_from_dir() { # name, source dir
  local dir="$ORIGINS/$1"
  mkdir -p "$dir"
  tar -C "$2" -cf - . | tar -C "$dir" -xf -
  git -C "$dir" init --quiet
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m 'initial'
}

origin_commit() { # name, file, contents
  local dir="$ORIGINS/$1"
  mkdir -p "$(dirname "$dir/$2")"
  printf '%s\n' "$3" >"$dir/$2"
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m "add $2"
}

origin_head() { git -C "$ORIGINS/$1" rev-parse HEAD; }

# ---------------------------------------------------------------------------
# Running bootstrap
# ---------------------------------------------------------------------------

# Runs the real bootstrap.sh with a clean environment, capturing its transcript.
# Returns bootstrap's exit status; the combined output is left in $BOOTSTRAP_OUT.
# An argument is passed through as bootstrap's manifest path, which is how the
# step-contract scenario drives the real runner over throwaway manifests
# instead of the shipping one.
run_bootstrap() { # [manifest path]
  _RUN_SEQ=$((${_RUN_SEQ:-0} + 1))
  BOOTSTRAP_OUT="$SANDBOX/bootstrap-$_RUN_SEQ.out"
  local status=0
  ( cd "$REPO" && env -u HOMEBREW_PREFIX -u HOMEBREW_CELLAR -u HOMEBREW_REPOSITORY \
      PATH="$SANDBOX/guardbin:$PATH" ./bootstrap.sh "$@" ) \
    >"$BOOTSTRAP_OUT" 2>&1 || status=$?
  printf '   (bootstrap exit %s, output: %s)\n' "$status" "$BOOTSTRAP_OUT"
  return "$status"
}

# Runs the real reapply.sh -- the steady-state path a user takes after
# `git pull`, as opposed to bootstrap.sh's fresh-machine path. --yes is always
# passed because reapply refuses to act unattended without it (there is no tty
# here); everything else is up to the caller. Output lands in $REAPPLY_OUT.
run_reapply() { # extra reapply.sh arguments
  _RUN_SEQ=$((${_RUN_SEQ:-0} + 1))
  REAPPLY_OUT="$SANDBOX/reapply-$_RUN_SEQ.out"
  local status=0
  # Unlike bootstrap.sh, reapply.sh does not install Homebrew and then load its
  # shellenv -- it expects to be run from a shell the deployed .zprofile has
  # already set up. Putting the isolated prefix on PATH here reproduces that,
  # and is what makes brew/stow/mise resolvable the way they are in real use.
  # HOMEBREW_* is scrubbed for the same reason PATH is rewritten: running the
  # suite natively on a Mac leaves the developer's own prefix in the
  # environment, and link-docker-cli-plugins would then wire the sandbox's
  # plugin directory to the real Homebrew instead of the stub.
  #
  # No Nix equivalent is needed: reapply.sh sources
  # $HOME/.nix-profile/etc/profile.d/nix.sh itself, and $HOME is the sandbox,
  # so it finds the stub before the guard either way. That self-hosting is
  # exactly what makes reapply runnable from a non-login shell on Linux, so
  # letting it happen here tests it rather than papering over it.
  ( cd "$REPO" && env -u HOMEBREW_PREFIX -u HOMEBREW_CELLAR -u HOMEBREW_REPOSITORY \
      PATH="$HOME/.homebrew/bin:$SANDBOX/guardbin:$PATH" \
      ./reapply.sh --yes "$@" ) >"$REAPPLY_OUT" 2>&1 || status=$?
  printf '   (reapply exit %s, output: %s)\n' "$status" "$REAPPLY_OUT"
  return "$status"
}

# ---------------------------------------------------------------------------
# What stow is expected to deploy
# ---------------------------------------------------------------------------

# Files in the package that stow ignores by default. Stow's built-in list
# anchors README/LICENSE/COPYING to the package root ("^/README.*") but matches
# VCS/backup patterns at any depth.
_stow_ignored() { # relative path
  local path="$1" base
  base="$(basename "$path")"
  case "$path" in
    README.*|LICENSE.*|COPYING) return 0 ;;
  esac
  case "$base" in
    .git|.gitignore|.gitmodules|.hg|.svn|CVS|RCS|_darcs|.cvsignore|*~|\#*\#) return 0 ;;
  esac
  case "$path" in
    */.git/*|.git/*) return 0 ;;
  esac
  return 1
}

package_files() { # package dir... -- paths stow should link, relative to $HOME
  local pkg rel
  for pkg in "$@"; do
    [ -d "$pkg" ] || continue
    while IFS= read -r rel; do
      rel="${rel#./}"
      _stow_ignored "$rel" || printf '%s\n' "$rel"
    done < <(cd "$pkg" && find . -type f -o -type l | sort)
  done | sort -u
}

package_dirs() { # package dir... -- directories that must exist for real in HOME
  local pkg rel
  for pkg in "$@"; do
    [ -d "$pkg" ] || continue
    while IFS= read -r rel; do
      rel="${rel#./}"
      [ "$rel" = "." ] && continue
      printf '%s\n' "$rel"
    done < <(cd "$pkg" && find . -type d | sort)
  done | sort -u
}

# The directories of the packages this machine deploys, as arguments for the
# two helpers above.
deployed_package_dirs() {
  local pkg
  for pkg in "${PACKAGE_SET[@]}"; do printf '%s\n' "$REPO/packages/$pkg"; done
}

# Snapshot helpers used to prove reruns don't churn the deployed tree or write
# back into the repository.
# GNU and BSD stat disagree on flags; the suite runs on both (Linux container
# and the macOS CI runner), so ask each in turn.
inode() { stat -c %i "$1" 2>/dev/null || stat -f %i "$1"; }

home_link_snapshot() {
  # `find -printf` is GNU-only; readlink per link keeps this working on the
  # macOS runner too.
  #
  # The two Nix paths are pruned for the same reason ~/.homebrew is: they are
  # the package manager's own state, not something stow deployed. The out-link
  # in particular is *expected* to be repointed whenever nix/flake.nix changes,
  # so leaving it in would make "no previously deployed link was repointed"
  # fail on exactly the runs that are working correctly.
  find "$HOME" -path "$HOME/dotfiles" -prune -o -path "$HOME/.homebrew" -prune -o \
       -path "$HOME/.nix-profile" -prune -o -path "$NIX_ENV" -prune -o \
       -path "$HOME/.config/nvim" -prune -o -type l -print 2>/dev/null |
    while IFS= read -r link; do
      printf '%s -> %s\n' "${link#"$HOME"/}" "$(readlink "$link")"
    done | sort
}

# One "<type> <path relative to $REPO>" line per entry, sorted. The type marker
# matches what GNU find's `%y` produced here before: l/d/f, symlinks reported as
# links rather than as whatever they point at.
#
# `-printf` is GNU-only -- the same reason home_link_snapshot() above spells its
# output out by hand. macOS find rejects it outright ("unknown primary or
# operator"), so on the macOS runner this used to yield an empty string, and the
# callers, which only ever compare one snapshot against another, compared "" to
# "" and passed without checking anything.
#
# Deliberately not `2>/dev/null`: swallowing find's stderr is what let that
# failure look like a clean tree for as long as it did. If find cannot read the
# tree, the scenario should say so.
repo_tree_snapshot() {
  find "$REPO" -path "$REPO/.git" -prune -o -print |
    while IFS= read -r path; do
      rel="${path#"$REPO"}"
      rel="${rel#/}"
      # -L first: a symlink to a directory answers yes to -d as well.
      if   [ -L "$path" ]; then type=l
      elif [ -d "$path" ]; then type=d
      elif [ -f "$path" ]; then type=f
      else                      type=?
      fi
      printf '%s %s\n' "$type" "$rel"
    done | sort
}
