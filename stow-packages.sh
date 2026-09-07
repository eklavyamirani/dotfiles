#!/usr/bin/env bash
# Deploy this machine's stow packages into $HOME.
#
# The single place that knows how the package set becomes symlinks, so
# bootstrap.sh (via its manifest) and reapply.sh cannot drift apart on it. Both
# validate through lib/platform.sh first: a package belonging to another
# platform is refused rather than linked, because once linked its target still
# exists and reapply.sh's stale-link scan -- which only reclaims links whose
# target is *gone* -- would never take it back.
#
#   ./stow-packages.sh                 # the set for this platform
#   ./stow-packages.sh common unix     # an explicit subset
#
# Lives at the repo root for the same reason bootstrap.sh and reapply.sh do: it
# runs stow, so it cannot depend on stow having already linked it onto PATH.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
. "$REPO_DIR/lib/platform.sh"

TARGET="${STOW_TARGET:-$HOME}"

if [ "$#" -gt 0 ]; then
  packages=("$@")
else
  # `read -a` rather than a bare expansion so this still works under `set -u`
  # when the set is empty for an unexpected platform.
  packages=()
  while IFS= read -r pkg; do packages+=("$pkg"); done < <(platform_package_set)
fi

platform_assert_packages "${packages[@]}"

for pkg in "${packages[@]}"; do
  [ -d "$REPO_DIR/packages/$pkg" ] || {
    printf 'stow package not found: packages/%s\n' "$pkg" >&2
    exit 1
  }
  # Real target directories first, so stow links managed files individually
  # instead of folding a whole stateful directory (~/.pi) into the repository.
  "$REPO_DIR/prepare-stow-targets.sh" "$pkg" "$TARGET"
done

printf 'stowing %s into %s\n' "${packages[*]}" "$TARGET"
stow -d "$REPO_DIR/packages" -t "$TARGET" "${packages[@]}"
