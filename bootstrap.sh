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
#                          shell. The corollary: a command must not call
#                          `exit` itself -- that would terminate this runner
#                          rather than fail its step. Steps are external
#                          programs; wrap anything else in `sh -c`.
#   skip_if  (optional) -- a shell condition string meaning "this step has no
#                          work to do"; if it exits 0, the step is skipped.
#   state    (optional) -- a shell condition string describing the state the
#                          step exists to produce. Checked TWICE: before the
#                          command (holds => skip, nothing to do) and again
#                          after it, but only if the command reported failure.
#                          If the state holds then, the step is treated as a
#                          success with a WARNING, because the command's exit
#                          code and the outcome are not the same question --
#                          see the failure-handling note below.
#   os       (optional) -- "darwin" or "linux"; the step only runs on that
#                          platform and is skipped elsewhere. Omit it for the
#                          steps that are the same everywhere (stow, mise,
#                          external repos). This is what lets one manifest
#                          describe both machines: the package manager differs
#                          (Homebrew in ~/.homebrew on macOS, Nix on Linux) but
#                          everything downstream of it does not.
#   purpose  (optional) -- human-readable note, shown in logs
#
# Failure handling: steps are sequentially dependent (stow-ing before
# Homebrew/mise exist, or syncing repos before PATH includes
# ~/.local/bin, is meaningless), so this HALTS on the first failing step.
# "Failing" means the declared `state` was not reached -- falling back to a
# non-zero exit code only for steps that declare no state. The distinction is
# not pedantic: `brew install` exits 1 when a formula's post-install hook
# flakes, having installed everything it was asked for, and Homebrew has a
# single failure code (`exit Homebrew.failed? ? 1 : 0`) shared with a genuinely
# missing formula. Keying success off the exit code alone once halted a
# bootstrap after a 92-minute build over a cert symlink that had nothing to do
# with what the step was for.
# Every step's full output is captured to a transcript log file regardless
# of outcome, so a failure always leaves complete detail to diagnose nothing
# is reverted or cleaned up automatically. Every step here is idempotent
# (or guarded by skip_if), so it's always safe to fix the issue and rerun.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${1:-$REPO_DIR/bootstrap-steps.json}"
# Matches the `os` field a step may declare. Anything that is not Darwin is
# treated as linux: those are the only two this repository is deployed on, and
# a wrong guess here surfaces immediately as a skipped package-manager step
# rather than as a silent half-apply.
case "$(uname -s)" in
  Darwin) PLATFORM=darwin ;;
  *)      PLATFORM=linux ;;
esac
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
    state = step.get("state") or ""
    purpose = step.get("purpose") or ""
    os_ = step.get("os") or ""
    print("\x1f".join([name, command, skip_if, state, purpose, os_]))
' "$MANIFEST" 2>&1); then
  fail "could not parse manifest (invalid JSON?): $MANIFEST"
  printf '%s\n' "$parsed" >&2
  exit 1
fi

log "bootstrap started on $PLATFORM, transcript: $LOG_FILE"

# The manifest is fed in on fd 3, not stdin. A step's command inherits this
# process's stdin, and any command that reads it -- `brew bundle` does -- would
# otherwise consume the rest of the manifest from the here-string, so the loop
# would end early and report "bootstrap complete" having silently skipped every
# remaining step. That is exactly how the `wire docker CLI plugins` step went
# missing while the run still exited 0. Keeping the steps on their own
# descriptor also leaves stdin free for a step that legitimately needs to prompt.
while IFS=$'\x1f' read -r name command skip_if state purpose step_os <&3; do
  [ -z "$name" ] && continue

  # Platform gate first: a step for the other OS has no work to do here by
  # definition, and its skip_if/state predicates may not even be evaluable
  # (`brew shellenv` on Linux, `nix build` on a Mac without Nix).
  if [ -n "$step_os" ] && [ "$step_os" != "$PLATFORM" ]; then
    log "==> $name (skipped, declared for $step_os, this is $PLATFORM)"
    continue
  fi

  # Either predicate holding up front means there is nothing to do. They are
  # checked together here but mean different things: skip_if is "this step has
  # no work", state is "the outcome this step exists to produce is already
  # true".
  if [ -n "$skip_if" ] && eval "$skip_if" >/dev/null 2>&1; then
    log "==> $name (skipped, nothing to do)"
    log "    skip_if: $skip_if"
    continue
  fi
  if [ -n "$state" ] && eval "$state" >/dev/null 2>&1; then
    log "==> $name (skipped, already in the declared state)"
    log "    state: $state"
    continue
  fi

  log "==> $name"
  [ -n "$purpose" ] && log "    purpose: $purpose"
  log "    command: $command"
  start=$(date +%s)
  status=0
  eval "$command" || status=$?
  end=$(date +%s)

  if [ "$status" -eq 0 ]; then
    log "    done ($((end - start))s)"
    continue
  fi

  # The command reported failure. That is not the same question as "did this
  # step achieve what it exists for", and for some tools it is not even
  # correlated: `brew install` exits 1 when a formula's post-install hook
  # flakes, having installed everything asked of it. Homebrew has exactly one
  # failure code (brew.rb: `exit Homebrew.failed? ? 1 : 0`), so the exit status
  # cannot distinguish that from a genuinely missing formula -- only the
  # resulting state can. When a step declares that state and it now holds, the
  # step succeeded; say so loudly and carry on rather than halting a
  # multi-hour bootstrap over a cosmetic symlink.
  if [ -n "$state" ] && eval "$state" >/dev/null 2>&1; then
    log "    WARNING: command exited $status, but the declared state was reached"
    log "    state: $state"
    log "    treating as success -- review the transcript above if this is unexpected"
    log "    done ($((end - start))s, with warnings)"
    continue
  fi

  fail "step failed: $name (exit $status) -- see full transcript at $LOG_FILE"
  exit 1
done 3<<< "$parsed"

log "bootstrap complete, transcript saved at $LOG_FILE"
