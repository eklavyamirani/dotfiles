# shellcheck shell=bash
# Assertions + sandbox construction shared by the scenarios in tests/scenarios/.
#
# A "sandbox" is a throwaway $HOME plus a set of local git repositories that
# stand in for the remotes bootstrap would otherwise fetch over the network
# (Homebrew and the external nvim config). Everything a scenario touches lives
# under that directory, so scenarios never see each other's state and the whole
# suite runs offline.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_REPO="${SOURCE_REPO:-$(cd "$TESTS_DIR/.." && pwd)}"

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
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ci.XXXXXXXX")"
  export SANDBOX
  export HOME="$SANDBOX/home"
  export ORIGINS="$SANDBOX/origins"
  export BREW_CALL_LOG="$SANDBOX/brew-calls.log"
  export BREW_SHIM_LOG="$SANDBOX/shim-calls.log"
  REPO="$HOME/dotfiles"
  mkdir -p "$HOME" "$ORIGINS"
  : >"$BREW_CALL_LOG"

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
run_bootstrap() {
  BOOTSTRAP_OUT="$SANDBOX/bootstrap-$(date +%s%N).out"
  local status=0
  ( cd "$REPO" && ./bootstrap.sh ) >"$BOOTSTRAP_OUT" 2>&1 || status=$?
  printf '   (bootstrap exit %s, output: %s)\n' "$status" "$BOOTSTRAP_OUT"
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

package_files() { # package dir -- paths stow should link, relative to it
  local pkg="$1" rel
  while IFS= read -r rel; do
    rel="${rel#./}"
    _stow_ignored "$rel" || printf '%s\n' "$rel"
  done < <(cd "$pkg" && find . -type f -o -type l | sort)
}

package_dirs() { # package dir -- directories that must exist for real in HOME
  local pkg="$1" rel
  while IFS= read -r rel; do
    rel="${rel#./}"
    [ "$rel" = "." ] && continue
    printf '%s\n' "$rel"
  done < <(cd "$pkg" && find . -type d | sort)
}

# Snapshot helpers used to prove reruns don't churn the deployed tree or write
# back into the repository.
home_link_snapshot() {
  find "$HOME" -path "$HOME/dotfiles" -prune -o -path "$HOME/.homebrew" -prune -o \
       -path "$HOME/.config/nvim" -prune -o -type l -printf '%P -> %l\n' 2>/dev/null | sort
}

repo_tree_snapshot() {
  find "$REPO" -path "$REPO/.git" -prune -o -printf '%y %P\n' 2>/dev/null | sort
}
