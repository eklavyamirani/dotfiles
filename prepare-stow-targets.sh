#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE="${1:?usage: prepare-stow-targets.sh PACKAGE [TARGET]}"
TARGET="${2:-$HOME}"
PACKAGE_DIR="$REPO_DIR/$PACKAGE"

if [ ! -d "$PACKAGE_DIR" ]; then
  printf 'Stow package not found: %s\n' "$PACKAGE_DIR" >&2
  exit 1
fi

while IFS= read -r -d '' directory; do
  relative="${directory#"$PACKAGE_DIR"}"
  [ -n "$relative" ] && mkdir -p "$TARGET$relative"
done < <(find "$PACKAGE_DIR" -type d -print0)
