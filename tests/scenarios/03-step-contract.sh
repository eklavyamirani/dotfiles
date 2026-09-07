#!/usr/bin/env bash
# Scenario 3: the step contract in bootstrap-steps.json.
#
# Scenarios 01 and 02 drive the shipping manifest end to end. This one pins
# down the runner's own semantics -- when a step is skipped, when a failure
# halts the run, and when it does not -- by handing the real bootstrap.sh
# throwaway manifests built here. No Homebrew, no stow, no network: each step
# is a few lines of shell whose success or failure the scenario dictates.
#
# Those stand-ins run their failures through `sh -c` rather than a bare
# `exit 1`. A step's command is eval'd in the runner's own process -- that is
# deliberate, it is what lets the Homebrew shellenv step export PATH to later
# steps -- so a bare `exit` in a command would terminate bootstrap.sh itself
# rather than fail its step. Real steps are external programs and exit the way
# these subshells do.
#
# The case that matters is the third one. `brew install` exits 1 when a
# formula's post-install hook flakes even though every requested formula was
# installed, and Homebrew has exactly one failure exit code
# (brew.rb: `exit Homebrew.failed? ? 1 : 0`), shared with a genuinely missing
# formula. So the exit status cannot answer "did this step do its job" -- only
# the state it was supposed to produce can. A step that declares that state and
# reaches it has succeeded, whatever the command's exit code said.

CURRENT_SCENARIO="03-step-contract"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/harness.sh"

sandbox_create
trap sandbox_destroy EXIT

printf 'sandbox: %s\n' "$SANDBOX"

# Writes a manifest to $SANDBOX/<name>.json from the JSON on stdin, and echoes
# its path. $MARKER stands in for whatever a real step leaves behind.
manifest() { # name
  local path="$SANDBOX/$1.json"
  cat >"$path"
  printf '%s\n' "$path"
}
MARKER="$SANDBOX/marker"
export MARKER
rm -f "$MARKER"

section "a step whose state already holds is skipped before it runs"
rm -f "$MARKER"
m="$(manifest skip-when-state-holds <<'JSON'
[
  {
    "name": "create the marker",
    "command": "touch \"$MARKER\"",
    "state": "[ -e \"$MARKER\" ]"
  },
  {
    "name": "fail loudly if this step is not skipped",
    "command": "sh -c 'rm -f \"$MARKER\"; exit 1'",
    "state": "[ -e \"$MARKER\" ]"
  }
]
JSON
)"
assert_true "bootstrap exits 0" run_bootstrap "$m"
out="$BOOTSTRAP_OUT"
assert_file_has "the first step ran"      "$out" '==> create the marker$'
assert_file_has "the second was skipped"  "$out" '==> fail loudly if this step is not skipped \(skipped, already in the declared state\)'
assert_file_lacks "and never executed"    "$out" 'ERROR: step failed'
assert_exists "the marker survives" "$MARKER"

section "a step that fails with no state declared still halts the run"
rm -f "$MARKER"
m="$(manifest fail-without-state <<'JSON'
[
  { "name": "exit non-zero", "command": "sh -c 'exit 3'" },
  { "name": "must never run", "command": "touch \"$MARKER\"" }
]
JSON
)"
assert_false "bootstrap exits non-zero" run_bootstrap "$m"
out="$BOOTSTRAP_OUT"
assert_file_has "the failure is reported with its exit code" "$out" 'ERROR: step failed: exit non-zero \(exit 3\)'
assert_file_lacks "later steps did not run" "$out" '==> must never run'
assert_missing "and left nothing behind" "$MARKER"

section "a step that fails but reaches its declared state is a success"
# This is the openssl@3 post-install case in miniature: the command does the
# work it was asked to do, then exits non-zero over something incidental.
rm -f "$MARKER"
m="$(manifest fail-but-state-reached <<'JSON'
[
  {
    "name": "do the work, then flake",
    "command": "sh -c 'touch \"$MARKER\"; echo Warning: the post-install step did not complete successfully; exit 1'",
    "state": "[ -e \"$MARKER\" ]"
  },
  { "name": "the next step still runs", "command": "true" }
]
JSON
)"
assert_true "bootstrap exits 0" run_bootstrap "$m"
out="$BOOTSTRAP_OUT"
assert_file_has "the discrepancy is reported, not swallowed" \
  "$out" 'WARNING: command exited 1, but the declared state was reached'
assert_file_has "the step counts as done"      "$out" 'done \([0-9]+s, with warnings\)'
assert_file_lacks "the run did not halt"       "$out" 'ERROR: step failed'
assert_file_has "later steps still ran"        "$out" '==> the next step still runs'
assert_file_has "and the run completed"        "$out" 'bootstrap complete'

section "a step that fails without reaching its declared state still halts"
# The other half of the contract: `state` must not become a way for a real
# failure to pass. Same shape as above, minus the part that does the work.
rm -f "$MARKER"
m="$(manifest fail-and-state-missed <<'JSON'
[
  {
    "name": "flake without doing the work",
    "command": "sh -c 'echo Warning: the post-install step did not complete successfully; exit 1'",
    "state": "[ -e \"$MARKER\" ]"
  },
  { "name": "must never run", "command": "touch \"$MARKER\"" }
]
JSON
)"
assert_false "bootstrap exits non-zero" run_bootstrap "$m"
out="$BOOTSTRAP_OUT"
assert_file_has "the failure is reported"   "$out" 'ERROR: step failed: flake without doing the work \(exit 1\)'
assert_file_lacks "no success warning"      "$out" 'WARNING: command exited'
assert_file_lacks "later steps did not run" "$out" '==> must never run'

section "skip_if still means 'no work to do', independent of state"
rm -f "$MARKER"
m="$(manifest skip-if-guard <<'JSON'
[
  {
    "name": "guarded out",
    "command": "touch \"$MARKER\"",
    "skip_if": "true"
  }
]
JSON
)"
assert_true "bootstrap exits 0" run_bootstrap "$m"
assert_file_has "reported as having no work" "$BOOTSTRAP_OUT" '==> guarded out \(skipped, nothing to do\)'
assert_missing "the command did not run" "$MARKER"

section "a step that reads stdin cannot swallow the rest of the manifest"
# `brew bundle` reads stdin. When the runner fed the step list in on stdin too,
# that consumed every remaining step from the here-string: the loop ended early
# and the run reported "bootstrap complete", exit 0, having silently skipped the
# tail of the manifest. That is how `wire docker CLI plugins` -- the last step
# -- stopped running without anyone noticing. The steps now arrive on fd 3.
rm -f "$MARKER"
m="$(manifest stdin-eater <<'JSON'
[
  { "name": "a step that reads stdin", "command": "cat >/dev/null" },
  { "name": "the step after it", "command": "touch \"$MARKER\"" }
]
JSON
)"
assert_true "bootstrap exits 0" run_bootstrap "$m"
out="$BOOTSTRAP_OUT"
assert_file_has "the stdin-reading step ran" "$out" '==> a step that reads stdin'
assert_file_has "and the step after it ran too" "$out" '==> the step after it'
assert_exists "which really executed" "$MARKER"
assert_file_has "the run completed" "$out" 'bootstrap complete'

# --------------------------------------------------------------------------
section "a step declaring another OS is skipped, and one declaring this OS runs"
# --------------------------------------------------------------------------
# The `os` field is what lets a single manifest describe both machines. It is
# checked ahead of skip_if and state on purpose: a step for the other platform
# may have predicates that cannot even be evaluated here (`brew shellenv` on
# Linux), so the gate has to come first rather than fall out of a failing test.
if [ "$PLATFORM" = macos ]; then other_os=linux; else other_os=macos; fi
rm -f "$MARKER" "$MARKER.other"
os_manifest="$(manifest os-gate <<JSON
[
  {
    "name": "a step for this OS",
    "os": "$PLATFORM",
    "command": "touch \\"$MARKER\\""
  },
  {
    "name": "a step for the other OS",
    "os": "$other_os",
    "command": "touch \\"$MARKER.other\\"",
    "skip_if": "false",
    "state": "false"
  },
  {
    "name": "an ungated step",
    "command": "touch \\"$MARKER.both\\""
  }
]
JSON
)"
assert_true "bootstrap exits 0 with a mixed-OS manifest" run_bootstrap "$os_manifest"
out="$BOOTSTRAP_OUT"
assert_exists "the step for this OS ran" "$MARKER"
assert_missing "the step for the other OS did not" "$MARKER.other"
assert_exists "an ungated step runs on both" "$MARKER.both"
assert_file_has "and says why it was skipped" "$out" \
  "a step for the other OS \\(skipped, declared for $other_os, this is $PLATFORM\\)"
# The gate must win over the predicates rather than race them: both are false
# here, so a step evaluated in the wrong order would have run.
assert_file_lacks "the other OS's predicates were never consulted" "$out" \
  'a step for the other OS \(skipped, nothing to do\)'

section "the shipping manifest still parses under the step contract"
# Cheap guard against a manifest edit that adds an unknown field or renames one
# of these: every step must have a name and a command, and the predicate and
# platform fields must be the only other keys.
assert_true "bootstrap-steps.json matches the documented schema" python3 -c '
import json, sys
steps = json.load(open(sys.argv[1]))
allowed = {"name", "command", "skip_if", "state", "purpose", "os"}
for step in steps:
    assert step.get("name"), step
    assert step.get("command"), step
    extra = set(step) - allowed
    assert not extra, (step["name"], extra)
    assert step.get("os") in (None, "macos", "linux"), (step["name"], step.get("os"))
' "$REPO/manifests/common/bootstrap-steps.json"

# Both platforms must actually be served: a manifest whose every step is gated
# to one OS would leave the other with nothing but the shared steps, which is
# precisely the half-applied account the gate exists to avoid.
assert_true "the manifest has steps for both platforms" python3 -c '
import json, sys
steps = json.load(open(sys.argv[1]))
declared = {s.get("os") for s in steps if s.get("os")}
assert declared == {"macos", "linux"}, declared
shared = [s["name"] for s in steps if not s.get("os")]
assert shared, "no OS-independent steps left"
' "$REPO/manifests/common/bootstrap-steps.json"

finish
