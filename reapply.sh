#!/usr/bin/env bash
# Re-apply the deployed stow package after pulling new changes.
#
#   cd ~/repositories/dotfiles && git pull && ./reapply.sh
#
# bootstrap.sh is for a *fresh* account: it installs this machine's package
# manager (Homebrew on macOS, Nix on Linux), stow and mise. This script is the
# steady-state counterpart -- it only
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
#
# Platform: the package-manager half differs by OS and nothing else does.
# On macOS that half is `brew bundle` against dev/Brewfile (plus the docker
# CLI plugin links); on Linux it is a rebuild of nix/flake.nix into
# ~/.local/state/dotfiles/nix-env. The stow, external-repo and mise halves are
# identical on both. The Homebrew block is gated on the OS, not merely on
# `command -v brew`: a Linux box may well have a Homebrew of its own on PATH,
# and handing it a Brewfile full of macOS casks is not a no-op.
set -uo pipefail

# pwd -P, not pwd: the dangling-link scan resolves each link's target with
# `pwd -P` and compares it against this prefix, so both sides must have their
# symlinks resolved. With a logical path here, a repository reached through a
# symlinked parent (/tmp and /var are symlinks on macOS) would never match its
# own links, and stale ones would silently survive.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGE="dev"
TARGET="$HOME"
case "$(uname -s)" in
  Darwin) PLATFORM=darwin ;;
  *)      PLATFORM=linux ;;
esac
DRY_RUN=0
ASSUME_YES=0
RUN_BREW=1
RUN_SYNC=1
PRUNE=0
NO_UPGRADE=0
RUN_MISE=1
RUN_NIX=1

usage() {
  cat <<'USAGE'
usage: reapply.sh [options]

  --dry-run      show the plan and exit without changing anything
  --prune        uninstall Homebrew packages that the Brewfile does not
                 declare (off by default: drift is always reported, but
                 removing software is an explicit choice). macOS only --
                 on Linux the Nix environment is rebuilt as a whole, so
                 deleting a line from nix/flake.nix already removes it
  --yes, -y      do not prompt for confirmation
  --no-brew      skip `brew bundle`
  --no-upgrade   install missing packages but do not upgrade existing ones
                 (`brew bundle` upgrades by default)
  --no-sync      skip `sync-external-repos`
  --no-mise      skip `mise install`
  --no-nix       skip rebuilding nix/flake.nix (Linux only)
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
    --no-nix)  RUN_NIX=0 ;;
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

NIX_ENV="$HOME/.local/state/dotfiles/nix-env"
# At the repo root, not inside the stow package: it is a manifest this
# script applies, not a file that gets deployed into $HOME -- the same
# reason bootstrap.sh and reapply.sh themselves live at the root.
FLAKE_DIR="$REPO_DIR/nix"
# nix-command/flakes are enabled in the stowed dev/.config/nix/nix.conf, but
# this script must work even when that file is the very thing being repaired,
# so the flags are passed explicitly here too.
NIX_FLAGS=(--extra-experimental-features "nix-command flakes")

[ -d "$PACKAGE_DIR" ] || { fail "stow package not found: $PACKAGE_DIR"; exit 1; }

# On Linux, stow and mise come out of the Nix environment this script itself
# maintains. Put it (and nix) on PATH before the precondition check below, so
# a reapply run from a plain non-login shell -- or one whose ~/.zprofile is
# mid-repair -- still finds them instead of failing on its own output. The
# macOS side needs no equivalent: `brew shellenv` there is loaded by the
# .zprofile the user is already running under.
if [ "$PLATFORM" = linux ]; then
  [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  [ -d "$NIX_ENV/bin" ] && export PATH="$NIX_ENV/bin:$PATH"
fi

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
# The Nix paths are pruned for speed, not correctness: nothing under them
# points into this repository, but ~/.nix-profile and the environment out-link
# both lead into /nix/store, where a descent would walk a very large tree.
done < <(find "$TARGET" -maxdepth 6 \
           \( -path "$TARGET/Library" -o -path "$TARGET/repositories" \
              -o -path "$TARGET/.homebrew" \
              -o -path "$TARGET/.nix-profile" -o -path "$TARGET/.nix-defexpr" \
              -o -path "$TARGET/.local/state/nix" -o -path "$NIX_ENV" \
              -o -name node_modules -o -name .git \) -prune -o \
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

# --- plan: Nix drift (Linux) ---------------------------------------------
# The flake plus its lock name exactly one store path, so drift is a string
# comparison: what the out-link points at now, versus what the manifest
# evaluates to. Unlike the Homebrew side there is no "installed but
# undeclared" direction to report -- the environment IS the manifest, rebuilt
# whole, so anything not declared is already absent from it.
NIX_CURRENT=""
NIX_WANTED=""
NIX_AVAILABLE=0
if [ "$RUN_NIX" -eq 1 ] && [ "$PLATFORM" = linux ] && [ -f "$FLAKE_DIR/flake.nix" ]; then
  if command -v nix >/dev/null 2>&1; then
    NIX_AVAILABLE=1
    [ -L "$NIX_ENV" ] && NIX_CURRENT="$(readlink "$NIX_ENV")"
    # Best-effort: a cold evaluation has to fetch nixpkgs, and offline it
    # fails outright. Either way the plan degrades to "will rebuild" rather
    # than blocking, and the build below is what actually decides.
    NIX_WANTED="$(nix "${NIX_FLAGS[@]}" eval --raw "path:$FLAKE_DIR#default.outPath" 2>/dev/null || true)"
  fi
fi

# --- plan: Homebrew drift ------------------------------------------------
# The Brewfile is the declared closure. Two directions matter: what it
# declares but is absent (brew bundle fixes that), and what is installed
# but undeclared (only --prune fixes that). Deliberately NOT `brew bundle
# check`, which reports a merely *outdated* package as "needs to be
# installed" and would make every drift report a false alarm.
BREW_MISSING=""
BREW_UNDECLARED=""
BREWFILE="$PACKAGE_DIR/Brewfile"
if [ "$RUN_BREW" -eq 1 ] && [ "$PLATFORM" = darwin ] && [ -f "$BREWFILE" ] \
   && command -v brew >/dev/null 2>&1; then
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
if [ "$RUN_NIX" -eq 1 ] && [ "$PLATFORM" = linux ] && [ -f "$FLAKE_DIR/flake.nix" ]; then
  if [ "$NIX_AVAILABLE" -eq 0 ]; then
    log "  nix not on PATH yet, will skip the environment rebuild"
  elif [ -z "$NIX_WANTED" ]; then
    log "  rebuild the Nix environment (could not evaluate the flake ahead of time)"
  elif [ "$NIX_WANTED" = "$NIX_CURRENT" ]; then
    log "  no Nix drift: $NIX_ENV already matches nix/flake.nix"
  else
    log "  rebuild the Nix environment ($NIX_ENV):"
    log "        from: ${NIX_CURRENT:-<not built yet>}"
    log "        to:   $NIX_WANTED"
  fi
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
if [ "$RUN_BREW" -eq 1 ] && [ "$PLATFORM" = darwin ]; then
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

# Before stow, not after: stow itself comes out of this environment, so a
# package added to flake.nix in the commit being applied has to exist by the
# time the rest of this script runs. (The Homebrew half is the mirror image
# and runs last, because there `brew bundle` only follows a Brewfile that stow
# has just linked -- and brew, unlike nix here, was already on PATH.)
if [ "$RUN_NIX" -eq 1 ] && [ "$PLATFORM" = linux ] && [ -f "$FLAKE_DIR/flake.nix" ]; then
  if [ "$NIX_AVAILABLE" -eq 1 ]; then
    log "==> nix build $FLAKE_DIR"
    mkdir -p "$(dirname "$NIX_ENV")"
    nix "${NIX_FLAGS[@]}" build --out-link "$NIX_ENV" "path:$FLAKE_DIR#default" \
      || { fail "nix build failed -- see $LOG_FILE"; exit 1; }
    export PATH="$NIX_ENV/bin:$PATH"
    log "    environment: $(readlink "$NIX_ENV")"
  else
    log "==> nix not on PATH, skipping the environment rebuild"
  fi
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

if [ "$RUN_BREW" -eq 1 ] && [ "$PLATFORM" = darwin ] && [ "$PRUNE" -eq 1 ] \
   && [ -n "$BREW_UNDECLARED" ]; then
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

if [ "$RUN_BREW" -eq 1 ] && [ "$PLATFORM" = darwin ] && [ -f "$PACKAGE_DIR/Brewfile" ]; then
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
# macOS only, for the same reason the bundle above is: the plugins it wires up
# are Homebrew formulae, and on Linux docker's own packaging already puts
# buildx and compose where the CLI looks for them.
if [ "$PLATFORM" = darwin ] && [ -x "$TARGET/.local/bin/link-docker-cli-plugins" ]; then
  log "==> link docker cli plugins"
  "$TARGET/.local/bin/link-docker-cli-plugins" || { fail "linking docker cli plugins failed"; exit 1; }
fi

log "re-apply complete, transcript saved at $LOG_FILE"
[ -d "$BACKUP_DIR" ] && log "files moved aside this run: $BACKUP_DIR"
exit 0
