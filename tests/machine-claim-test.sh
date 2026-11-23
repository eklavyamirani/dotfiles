#!/usr/bin/env bash
# Run: tests/machine-claim-test.sh. Exercises packages/unix/.local/bin/machine-claim
# against a temporary state directory; touches nothing else on the machine.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
mc="$here/packages/unix/.local/bin/machine-claim"
export MACHINE_CLAIM_DIR; MACHINE_CLAIM_DIR=$(mktemp -d)
trap 'rm -rf "$MACHINE_CLAIM_DIR"' EXIT
fails=0 n=0
t() { # t <name> <expected exit> <expected text (regex)> -- command...
  local name=$1 want=$2 re=$3 out rc; shift 4
  out=$("$@" 2>&1); rc=$?; n=$((n + 1))
  if [[ $rc == "$want" && $out =~ $re ]]; then echo "ok   $name"; else echo "FAIL $name (exit $rc, want $want): $out"; fails=$((fails + 1)); fi
}
expire() { printf 'who %s\nuntil %s\nowner 0\n' "$2" "$(( $(date +%s) - 5 ))" >"$MACHINE_CLAIM_DIR/$1.claim"; }

t "status when empty" 0 "nothing is claimed" -- "$mc" status
t "take a free resource" 0 "docker: yours until" -- "$mc" take docker alpha 10
t "a second session is refused, holder named" 1 "held by alpha until" -- "$mc" take docker beta 10
t "the holder extends" 0 "still yours" -- "$mc" take docker alpha 20
t "check by the holder" 0 "yours until" -- "$mc" check docker alpha
t "check by another" 1 "held by alpha" -- "$mc" check docker beta
t "another resource is independent" 0 "cluster: yours" -- "$mc" take cluster beta 5
t "status lists both" 0 "docker: held by alpha.*cluster: held by beta|cluster: held by beta.*docker: held by alpha" -- "$mc" status
t "release by a non-holder refused" 1 "held by alpha, not by beta" -- "$mc" release docker beta
t "release by the holder" 0 "released" -- "$mc" release docker alpha
t "release when free" 1 "was not held" -- "$mc" release docker alpha
t "free again" 0 "yours until" -- "$mc" take docker beta 10
expire docker beta
t "an expired claim counts as free" 0 "yours until" -- "$mc" take docker gamma 10
t "owner asks while held: marked wanted" 2 "held by gamma.*marked as wanted for boss" -- "$mc" take docker boss 30 --owner
t "the holder is told on check" 3 "wanted by the owner's session boss" -- "$mc" check docker gamma
t "status shows the wish" 0 "docker: held by gamma.*wanted by the owner's session boss" -- "$mc" status
"$mc" release docker gamma >/dev/null
t "others cannot jump in" 1 "wanted by the owner's session boss" -- "$mc" take docker beta 10
t "the owner's session takes it" 0 "yours until" -- "$mc" take docker boss 30 --owner
t "the wish is cleared" 0 "docker: held by boss until [0-9:]+ \(owner's session\)$" -- "$mc" status
"$mc" release docker boss >/dev/null; "$mc" release cluster beta >/dev/null
t "bad resource name" 64 "short lowercase name" -- "$mc" take 'Docker/../x' alpha 5
t "bad minutes" 64 "1 to 240" -- "$mc" take docker alpha 999
t "no command prints usage" 64 "machine-claim take" -- "$mc"

# Twenty sessions take the same resource at the same moment: exactly one wins.
for i in $(seq 1 20); do ( "$mc" take race "s$i" 5 >"$MACHINE_CLAIM_DIR/race.$i.out" 2>&1; echo $? >"$MACHINE_CLAIM_DIR/race.$i.rc" ) & done; wait
wins=$(grep -lx 0 "$MACHINE_CLAIM_DIR"/race.*.rc | wc -l | tr -d ' ')
n=$((n + 1)); if [[ $wins == 1 ]]; then echo "ok   20 at once: exactly one wins"; else echo "FAIL 20 at once: $wins winners"; fails=$((fails + 1)); fi
# The same when the claim they race for is an expired one.
rm -f "$MACHINE_CLAIM_DIR"/race.*.out "$MACHINE_CLAIM_DIR"/race.*.rc; expire race old
for i in $(seq 1 20); do ( "$mc" take race "s$i" 5 >/dev/null 2>&1; echo $? >"$MACHINE_CLAIM_DIR/race.$i.rc" ) & done; wait
wins=$(grep -lx 0 "$MACHINE_CLAIM_DIR"/race.*.rc | wc -l | tr -d ' ')
n=$((n + 1)); if [[ $wins == 1 ]]; then echo "ok   20 at once over an expired claim: exactly one wins"; else echo "FAIL 20 at once over an expired claim: $wins winners"; fails=$((fails + 1)); fi

echo; echo "$((n - fails)) passed, $fails failed"
exit $((fails > 0))
