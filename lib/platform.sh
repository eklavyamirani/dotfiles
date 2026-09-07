# shellcheck shell=bash
# The one place in this repository that asks the operating system what it is.
#
# Sourced by bootstrap.sh, reapply.sh, stow-packages.sh and the test harness.
# Nothing else may call `uname` -- that is the whole point. Before this file
# existed the same `case "$(uname -s)"` was copied into three scripts, which is
# exactly the kind of duplication that drifts the moment a third platform
# arrives.
#
# TWO NAMES, DELIBERATELY:
#
#   $PLATFORM       -- this repository's own label: macos | linux
#                      Used for directory names (packages/<platform>,
#                      manifests/<platform>) and the `os` field in
#                      bootstrap-steps.json. It is a *product* name, matching
#                      how every line of prose here and the Windows milestone
#                      to come refer to these systems.
#
#   $PLATFORM_UNAME -- what the OS calls itself: Darwin | Linux
#                      For anything that must speak the OS's own vocabulary
#                      rather than ours: a download URL with a platform slug, a
#                      Nix system string (`aarch64-darwin`), a Go/Rust target
#                      triple. Nothing needs it today; it exists so that the
#                      first thing that does reaches for the right value
#                      instead of interpolating $PLATFORM and quietly building
#                      a URL containing "macos" that 404s.
#
# That split is the price of preferring `macos` over `darwin`, and it is the
# entire price: renaming back would be this file plus two directories.
case "$(uname -s)" in
  Darwin) PLATFORM=macos; PLATFORM_UNAME=Darwin ;;
  Linux)  PLATFORM=linux; PLATFORM_UNAME=Linux ;;
  *)
    printf 'unsupported platform: %s\n' "$(uname -s)" >&2
    printf 'this repository deploys on macOS and Linux; Windows is a future milestone\n' >&2
    return 1 2>/dev/null || exit 1
    ;;
esac
export PLATFORM PLATFORM_UNAME

# Every directory under packages/ that names a platform. A package NOT in this
# list (common, unix) is platform-independent and may always be stowed; one
# that IS in it may only be stowed on its own platform.
PLATFORM_PACKAGES="macos linux windows"

# The package set this machine deploys, in stow order. Widest first: common is
# every platform including the future Windows one, unix is the shell chain that
# macOS and Linux share, and the platform package holds only what is genuinely
# specific to it.
platform_package_set() {
  printf '%s\n' common unix "$PLATFORM"
}

# Refuse to deploy another platform's package.
#
# The failure this prevents is quiet rather than loud: stow would happily link
# packages/macos/.zprofile.d/50-homebrew-isolated.zsh into a Linux $HOME, and
# because the target then *exists*, reapply.sh's stale-link scan would never
# reclaim it -- that scan only removes links whose target is gone. The snippet
# would be sourced by every login shell from then on. It used to carry an
# $OSTYPE guard that made that survivable; now that a file's location declares
# its platform, that guard is gone and the same mistake would break the shell.
platform_assert_packages() { # package...
  local pkg bad=""
  for pkg in "$@"; do
    case " $PLATFORM_PACKAGES " in
      *" $pkg "*)
        [ "$pkg" = "$PLATFORM" ] || bad="${bad:+$bad }$pkg"
        ;;
    esac
  done
  [ -z "$bad" ] && return 0
  printf 'refusing to deploy package(s) for another platform: %s\n' "$bad" >&2
  printf 'this machine is %s; a foreign package linked into $HOME would be\n' "$PLATFORM" >&2
  printf 'sourced by every login shell and is not reclaimed by the stale-link scan\n' >&2
  return 1
}
