#!/usr/bin/env bash
# Runs the apply scenarios. Meant to run inside the container built from
# tests/Dockerfile (see tests/README.md), but it works on any Linux box that
# has bash, git, python3, stow and zsh.
#
#   tests/run-tests.sh                # every scenario
#   tests/run-tests.sh 01-fresh-apply # one scenario, by file name prefix
#
# SOURCE_REPO selects the checkout under test (default: this repository).
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SOURCE_REPO="${SOURCE_REPO:-$(cd "$TESTS_DIR/.." && pwd)}"

missing=()
for tool in bash git python3 stow zsh tar find; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ "${#missing[@]}" -gt 0 ]; then
  printf 'missing required tools: %s\n' "${missing[*]}" >&2
  exit 1
fi

selector="${1:-}"
scenarios=()
for scenario in "$TESTS_DIR"/scenarios/*.sh; do
  [ -n "$selector" ] && case "$(basename "$scenario")" in "$selector"*) ;; *) continue ;; esac
  scenarios+=("$scenario")
done

if [ "${#scenarios[@]}" -eq 0 ]; then
  printf 'no scenarios matched: %s\n' "$selector" >&2
  exit 1
fi

printf 'repository under test: %s\n' "$SOURCE_REPO"
failed=()
for scenario in "${scenarios[@]}"; do
  name="$(basename "$scenario" .sh)"
  printf '\n########## %s\n' "$name"
  if bash "$scenario"; then
    printf '########## %s PASSED\n' "$name"
  else
    printf '########## %s FAILED\n' "$name"
    failed+=("$name")
  fi
done

printf '\n===== %d/%d scenarios passed\n' \
  "$(( ${#scenarios[@]} - ${#failed[@]} ))" "${#scenarios[@]}"
if [ "${#failed[@]}" -gt 0 ]; then
  printf 'failed: %s\n' "${failed[*]}" >&2
  exit 1
fi
