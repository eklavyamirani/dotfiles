#!/usr/bin/env bash
# Generic, declarative bootstrap runner for a fresh isolated dev account.
# The actual steps live in bootstrap-steps.json (same directory) -- this
# script just executes them in order. To change what bootstrap does, edit
# that manifest; this file should stay generic and not need touching.
#
# Run directly from a freshly cloned checkout:
#
#   git clone https://github.com/eklavyamirani/dotfiles ~/dotfiles
#   cd ~/dotfiles
#   ./bootstrap.sh
#
# This intentionally does NOT live in dev/.local/bin: that directory only
# lands on PATH after `stow -t ~ dev` runs, and this script is what runs
# `stow` in the first place -- it can't depend on its own output.
#
# Manifest fields per step (see bootstrap-steps.json):
#   name     (required) -- shown in logs
#   command  (required) -- a shell string, run via `eval` in THIS process
#                          (not a subshell), so exports/PATH changes (e.g.
#                          the Homebrew shellenv step) persist to later
#                          steps, the way sourcing would in an interactive
#                          shell.
#   skip_if  (optional) -- a shell condition string; if it exits 0, the
#                          step is skipped (e.g. "already installed" checks)
#   purpose  (optional) -- human-readable note, shown in logs
#
# Failure handling: steps are sequentially dependent (stow-ing before
# Homebrew/mise exist, or syncing repos before PATH includes
# ~/.local/bin, is meaningless), so this HALTS on the first failing step.
# Every step's full output is captured to a transcript log file regardless
# of outcome, so a failure always leaves complete detail to diagnose nothing
# is reverted or cleaned up automatically. Every step here is idempotent
# (or guarded by skip_if), so it's always safe to fix the issue and rerun.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${1:-$REPO_DIR/bootstrap-steps.json}"
LOG_DIR="$HOME/.local/state/dotfiles"
LOG_FILE="$LOG_DIR/setup-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "$LOG_DIR"

# Redirect all of this script's stdout/stderr through tee once, up front,
# via process substitution -- NOT a pipe. This is deliberate: piping each
# step's `eval` individually (`eval "$command" | tee ...`) would run the
# eval in a subshell, silently discarding any exports it makes (e.g. the
# Homebrew shellenv step setting PATH) once that subshell exits. Process
# substitution keeps everything in this same process, so exports/PATH
# changes from one step really do persist to the next, the way sourcing
# would in an interactive shell.
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
fail() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

if [ ! -f "$MANIFEST" ]; then
  fail "manifest not found: $MANIFEST"
  exit 1
fi

# Parsed with whatever python3 is first on PATH; only the `json` stdlib
# module is used, so any 3.x works. On a fresh machine that is the 3.9 from
# macOS's Command Line Tools (no brew/pip install needed); on a provisioned
# one it will be the mise-pinned interpreter. Both are fine.
if ! parsed=$(python3 -c '
import json, sys

with open(sys.argv[1]) as f:
    steps = json.load(f)

for step in steps:
    name = step["name"]
    command = step["command"]
    skip_if = step.get("skip_if") or ""
    purpose = step.get("purpose") or ""
    print("\x1f".join([name, command, skip_if, purpose]))
' "$MANIFEST" 2>&1); then
  fail "could not parse manifest (invalid JSON?): $MANIFEST"
  printf '%s\n' "$parsed" >&2
  exit 1
fi

log "bootstrap started, transcript: $LOG_FILE"

while IFS=$'\x1f' read -r name command skip_if purpose; do
  [ -z "$name" ] && continue

  if [ -n "$skip_if" ] && eval "$skip_if" >/dev/null 2>&1; then
    log "==> $name (skipped, already done)"
    log "    command: $command"
    continue
  fi

  log "==> $name"
  [ -n "$purpose" ] && log "    purpose: $purpose"
  log "    command: $command"
  start=$(date +%s)
  if eval "$command"; then
    end=$(date +%s)
    log "    done ($((end - start))s)"
  else
    fail "step failed: $name -- see full transcript at $LOG_FILE"
    exit 1
  fi
done <<< "$parsed"

log "bootstrap complete, transcript saved at $LOG_FILE"
