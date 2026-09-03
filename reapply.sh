#!/usr/bin/env bash
# Re-apply the deployed stow package after pulling new changes.
#
#   cd ~/repositories/dotfiles && git pull && ./reapply.sh
#
# bootstrap.sh is for a *fresh* account: it installs Homebrew, stow, mise
# and the Brewfile. This script is the steady-state counterpart -- it only
# reconciles $HOME with what the package currently contains, which is what
# an ordinary `git pull` actually needs. `stow -R` alone is not enough:
# stow unstows using the package's *current* contents, so a file that was
# renamed or deleted upstream (e.g. 40-mise.zsh -> 55-mise.zsh) leaves a
# dangling symlink behind in $HOME that stow will never clean up. Since
# .zprofile globs .zprofile.d/*.zsh, such a leftover breaks every new shell.
#
# Like bootstrap.sh, this lives at the repo root rather than in
# dev/.local/bin: it runs stow, so it must not depend on stow having
# already linked it onto PATH.
#
# Failsafes -- this script never destroys anything you could not recreate:
#   * It only ever removes SYMLINKS that point into this repository and
#     whose target no longer exists. Real files, real directories, and
#     symlinks to anywhere else are never touched.
#   * Real files that block a link (stow "conflicts") are MOVED into a
#     timestamped backup directory, never overwritten or deleted, and the
#     path is printed so you can diff and restore.
#   * It prints the full plan and asks for confirmation before changing
#     anything. --dry-run stops after the plan; --yes skips the prompt for
#     unattended use.
set -uo pipefail

# pwd -P, not pwd: the dangling-link scan resolves each link's target with
# `pwd -P` and compares it against this prefix, so both sides must have their
# symlinks resolved. With a logical path here, a repository reached through a
# symlinked parent (/tmp and /var are symlinks on macOS) would never match its
# own links, and stale ones would silently survive.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGE="dev"
TARGET="$HOME"
DRY_RUN=0
ASSUME_YES=0
RUN_BREW=1
RUN_SYNC=1
PRUNE=0
NO_UPGRADE=0
RUN_MISE=1

usage() {
  cat <<'USAGE'
usage: reapply.sh [options]

  --dry-run      show the plan and exit without changing anything
  --prune        uninstall Homebrew packages that the Brewfile does not
                 declare (off by default: drift is always reported, but
                 removing software is an explicit choice)
  --yes, -y      do not prompt for confirmation
  --no-brew      skip `brew bundle`
  --no-upgrade   install missing packages but do not upgrade existing ones
                 (`brew bundle` upgrades by default)
  --no-sync      skip `sync-external-repos`
  --no-mise      skip `mise install`
  --package NAME stow package to re-apply (default: dev)
  --target DIR   stow target directory (default: $HOME)
  -h, --help     this message
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --prune)   PRUNE=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --no-brew) RUN_BREW=0 ;;
    --no-upgrade) NO_UPGRADE=1 ;;
    --no-sync) RUN_SYNC=0 ;;
    --no-mise) RUN_MISE=0 ;;
    --package) PACKAGE="${2:?--package needs a value}"; shift ;;
    --target)  TARGET="${2:?--target needs a value}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

PACKAGE_DIR="$REPO_DIR/$PACKAGE"
STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG_DIR="$HOME/.local/state/dotfiles"
LOG_FILE="$LOG_DIR/reapply-$STAMP.log"
BACKUP_DIR="$LOG_DIR/backup-$STAMP"
mkdir -p "$LOG_DIR"

# Same process-substitution trick as bootstrap.sh: tee without a pipe, so
# nothing here runs in a subshell.
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

[ -d "$PACKAGE_DIR" ] || { fail "stow package not found: $PACKAGE_DIR"; exit 1; }
command -v stow >/dev/null 2>&1 || {
  fail "stow is not on PATH -- run ./bootstrap.sh first, or open a login shell"
  exit 1
}

log "re-applying package '$PACKAGE' into $TARGET (transcript: $LOG_FILE)"

# --- plan: dangling links left behind by upstream renames/deletions ------
# A link qualifies only if it is a symlink, its target is missing, AND that
# target resolves inside this repository. Anything else is somebody else's
# business and is deliberately left alone.
STALE_LIST="$(mktemp)"
trap 'rm -f "$STALE_LIST"' EXIT

while IFS= read -r -d '' link; do
  [ -e "$link" ] && continue                      # target exists -> healthy
  raw="$(readlink "$link")"
  case "$raw" in
    /*) link_dir="" ;;
    *)  link_dir="$(dirname "$link")" ;;
  esac
  # Resolve through the target's *parent* (which still exists even though the
  # target itself does not) so that a relative link full of '..' segments is
  # compared against REPO_DIR as a real path, not as literal text.
  target_parent="$(cd "${link_dir:+$link_dir/}$(dirname "$raw")" 2>/dev/null && pwd -P)" || continue
  [ -n "$target_parent" ] || continue
  resolved="$target_parent/$(basename "$raw")"
  case "$resolved" in
    "$REPO_DIR"/*) printf '%s\n' "$link" >> "$STALE_LIST" ;;
  esac
done < <(find "$TARGET" -maxdepth 6 \
           \( -path "$TARGET/Library" -o -path "$TARGET/repositories" \
              -o -path "$TARGET/.homebrew" -o -name node_modules -o -name .git \) -prune -o \
           -type l -print0 2>/dev/null)

STALE_COUNT=$(wc -l < "$STALE_LIST" | tr -d ' ')

# --- plan: what stow itself intends to do --------------------------------
"$REPO_DIR/prepare-stow-targets.sh" "$PACKAGE" "$TARGET" >/dev/null
STOW_PLAN="$(stow -n -v -R -d "$REPO_DIR" -t "$TARGET" "$PACKAGE" 2>&1)"
NEW_LINKS="$(printf '%s\n' "$STOW_PLAN" | grep '^LINK:' | grep -v 'reverts previous action' || true)"
CONFLICTS="$(printf '%s\n' "$STOW_PLAN" | grep -F 'existing target' || true)"

# stow words conflicts two different ways depending on why the target is in
# the way ("cannot stow X over existing target Y since ..." and "existing
# target is not owned by stow: Y"); both yield the target-relative path.
conflict_paths() {
  printf '%s\n' "$CONFLICTS" \
    | sed -E -e 's|.*over existing target (.+) since .*|\1|' \
             -e 's|.*existing target is[^:]*: (.+)|\1|' \
             -e 's|^[[:space:]]*\*[[:space:]]*||' \
    | grep -v '^[[:space:]]*$' || true
}

# --- plan: Homebrew drift ------------------------------------------------
# The Brewfile is the declared closure. Two directions matter: what it
# declares but is absent (brew bundle fixes that), and what is installed
# but undeclared (only --prune fixes that). Deliberately NOT `brew bundle
# check`, which reports a merely *outdated* package as "needs to be
# installed" and would make every drift report a false alarm.
BREW_MISSING=""
BREW_UNDECLARED=""
BREWFILE="$PACKAGE_DIR/Brewfile"
if [ "$RUN_BREW" -eq 1 ] && [ -f "$BREWFILE" ] && command -v brew >/dev/null 2>&1; then
  declared_formulae="$(brew bundle list --formula --file="$BREWFILE" 2>/dev/null | sort -u)"
  declared_casks="$(brew bundle list --cask --file="$BREWFILE" 2>/dev/null | sort -u)"
  installed_formulae="$(brew list --formula --full-name 2>/dev/null | sort -u)"
  installed_casks="$(brew list --cask --full-name 2>/dev/null | sort -u)"
  # Undeclared compares against leaves-installed-on-request, not every
  # installed formula: a dependency pulled in by a declared package (hf ->
  # python@3.14) is part of the closure and must never be reported as drift.
  requested_formulae="$(brew leaves --installed-on-request 2>/dev/null | sort -u)"

  BREW_MISSING="$( { comm -23 <(printf '%s\n' "$declared_formulae") <(printf '%s\n' "$installed_formulae")
                     comm -23 <(printf '%s\n' "$declared_casks")    <(printf '%s\n' "$installed_casks"); } \
                   | grep -v '^[[:space:]]*$' || true)"
  BREW_UNDECLARED="$( { comm -13 <(printf '%s\n' "$declared_formulae") <(printf '%s\n' "$requested_formulae")
                        comm -13 <(printf '%s\n' "$declared_casks")    <(printf '%s\n' "$installed_casks"); } \
                      | grep -v '^[[:space:]]*$' || true)"
fi

echo
log "PLAN"
if [ "$STALE_COUNT" -gt 0 ]; then
  log "  remove $STALE_COUNT dangling symlink(s) into this repo:"
  sed 's/^/        /' "$STALE_LIST"
else
  log "  no dangling symlinks to remove"
fi
if [ -n "$NEW_LINKS" ]; then
  log "  create new link(s):"
  printf '%s\n' "$NEW_LINKS" | sed 's/^/        /'
else
  log "  no new links to create"
fi
if [ -n "$CONFLICTS" ]; then
  log "  conflicting real file(s) -- will be MOVED to $BACKUP_DIR, not deleted:"
  conflict_paths | sed 's/^/        /'
  log "  (stow aborts its dry run at the first conflict, so the link list"
  log "   above may be partial; the real run re-plans after backing these up)"
fi
[ "$RUN_SYNC" -eq 1 ] && log "  run sync-external-repos"
if [ "$RUN_MISE" -eq 1 ] && [ -f "$PACKAGE_DIR/.config/mise/config.toml" ]; then
  if command -v mise >/dev/null 2>&1; then
    mise_missing="$(mise ls --missing 2>/dev/null | awk '{print $1" "$2}' | grep -v '^[[:space:]]*$' || true)"
    if [ -n "$mise_missing" ]; then
      log "  mise will install missing runtime(s):"
      printf '%s\n' "$mise_missing" | sed 's/^/        /'
    else
      log "  no mise drift: every pinned runtime is installed"
    fi
  else
    log "  mise not on PATH yet, will skip runtime install"
  fi
fi
if [ "$RUN_BREW" -eq 1 ]; then
  if [ -n "$BREW_MISSING" ]; then
    log "  brew bundle will install declared-but-absent package(s):"
    printf '%s\n' "$BREW_MISSING" | sed 's/^/        /'
  else
    log "  run brew bundle (nothing declared is missing)"
  fi
  if [ -n "$BREW_UNDECLARED" ]; then
    n=$(printf '%s\n' "$BREW_UNDECLARED" | grep -c .)
    if [ "$PRUNE" -eq 1 ]; then
      log "  UNINSTALL $n package(s) installed but not declared in the Brewfile:"
    else
      log "  DRIFT: $n package(s) installed but not declared in the Brewfile"
      log "         (add them to dev/Brewfile to keep them, or rerun with --prune)"
    fi
    printf '%s\n' "$BREW_UNDECLARED" | sed 's/^/        /'
  else
    log "  no Homebrew drift: every requested package is declared"
  fi
fi
echo

if [ "$DRY_RUN" -eq 1 ]; then
  log "dry run -- nothing changed"
  exit 0
fi

if [ "$ASSUME_YES" -eq 0 ]; then
  if [ ! -t 0 ]; then
    fail "not a terminal and --yes not given; refusing to act unattended"
    exit 1
  fi
  printf 'Proceed? [y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) log "aborted by user -- nothing changed"; exit 1 ;;
  esac
fi

# --- act -----------------------------------------------------------------
if [ "$STALE_COUNT" -gt 0 ]; then
  while IFS= read -r link; do
    # Re-verify at removal time: the plan is only a snapshot, and rm -f on a
    # path that turned into a real file in the meantime would be exactly the
    # destructive mistake this script exists to avoid.
    if [ -L "$link" ] && [ ! -e "$link" ]; then
      rm "$link" && log "removed dangling link: $link"
    else
      log "skipped (no longer a dangling link): $link"
    fi
  done < "$STALE_LIST"
fi

if [ -n "$CONFLICTS" ]; then
  mkdir -p "$BACKUP_DIR"
  # Conflict lines name a target-relative path; back the real file up there
  # under the same relative path so restoring is a plain copy back.
  conflict_paths | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    src="$TARGET/$rel"
    [ -e "$src" ] && [ ! -L "$src" ] || continue
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    mv "$src" "$BACKUP_DIR/$rel" && log "backed up conflicting file: $rel -> $BACKUP_DIR/$rel"
  done
fi

log "==> stow -R $PACKAGE"
if ! stow -v -R -d "$REPO_DIR" -t "$TARGET" "$PACKAGE"; then
  fail "stow failed -- see $LOG_FILE"
  [ -d "$BACKUP_DIR" ] && fail "files backed up this run are in $BACKUP_DIR"
  exit 1
fi

if [ "$RUN_SYNC" -eq 1 ] && [ -x "$TARGET/.local/bin/sync-external-repos" ]; then
  log "==> sync-external-repos"
  "$TARGET/.local/bin/sync-external-repos" || { fail "sync-external-repos failed"; exit 1; }
fi

# Runtimes come after stow (which links the mise config into place) and
# after brew would have installed mise itself on a fresh machine.
if [ "$RUN_MISE" -eq 1 ] && [ -f "$PACKAGE_DIR/.config/mise/config.toml" ] \
   && command -v mise >/dev/null 2>&1; then
  log "==> mise install"
  mise install || { fail "mise install failed"; exit 1; }
fi

if [ "$RUN_BREW" -eq 1 ] && [ "$PRUNE" -eq 1 ] && [ -n "$BREW_UNDECLARED" ]; then
  # Failsafe: an unreadable or mis-parsed Brewfile yields an empty declared
  # set, which would make *everything installed* look like drift and prune
  # the whole account. Refuse to act on that rather than trust the diff.
  if [ -z "$(brew bundle list --formula --file="$BREWFILE" 2>/dev/null)" ]; then
    fail "refusing to prune: dev/Brewfile declares no formulae (unreadable or empty?)"
    exit 1
  fi
  log "==> pruning undeclared packages"
  printf '%s\n' "$BREW_UNDECLARED" | while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    if brew list --cask --full-name 2>/dev/null | grep -qxF "$pkg"; then
      brew uninstall --cask "$pkg" && log "    uninstalled cask: $pkg"
    else
      brew uninstall "$pkg" && log "    uninstalled: $pkg"
    fi
  done
fi

if [ "$RUN_BREW" -eq 1 ] && [ -f "$PACKAGE_DIR/Brewfile" ]; then
  if command -v brew >/dev/null 2>&1; then
    bundle_args=(--file="$PACKAGE_DIR/Brewfile")
    [ "$NO_UPGRADE" -eq 1 ] && bundle_args+=(--no-upgrade)
    log "==> brew bundle ${bundle_args[*]}"
    brew bundle "${bundle_args[@]}" || { fail "brew bundle failed"; exit 1; }
  else
    log "==> brew not on PATH, skipping brew bundle"
  fi
fi

# Must run after brew bundle: it links the plugin binaries brew installs.
if [ -x "$TARGET/.local/bin/link-docker-cli-plugins" ]; then
  log "==> link docker cli plugins"
  "$TARGET/.local/bin/link-docker-cli-plugins" || { fail "linking docker cli plugins failed"; exit 1; }
fi

log "re-apply complete, transcript saved at $LOG_FILE"
[ -d "$BACKUP_DIR" ] && log "files moved aside this run: $BACKUP_DIR"
exit 0
