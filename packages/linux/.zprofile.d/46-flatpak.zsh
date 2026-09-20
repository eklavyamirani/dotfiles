# Flatpak: put the exported .desktop files somewhere the desktop environment
# can actually find them. Linux-only by virtue of living in packages/linux/,
# the same way 45-nix.zsh is.
#
# Distributions ship /etc/profile.d/flatpak.sh to do exactly this, and on a
# stock Ubuntu it gets reached because the distro's zsh package installs
# /etc/zsh/zprofile, which runs `emulate sh -c 'source /etc/profile'`. Neither
# half of that holds on this account. zsh comes from the flake, so Ubuntu's zsh
# package -- the thing that would have supplied /etc/zsh/zprofile -- is not
# installed, and /etc/zsh does not exist at all; and the Nix zsh looks for its
# global rc files in its own /nix/store prefix rather than in /etc. So nothing
# sources /etc/profile, flatpak.sh never runs, and 45-nix.zsh then has nix.sh
# seed XDG_DATA_DIRS from its bare "/usr/local/share:/usr/share" default --
# cementing a value with no flatpak exports in it.
#
# The symptom is not a broken binary, which is what makes it confusing to
# diagnose: `flatpak run org.chromium.Chromium` keeps working fine. It is that
# Plasma's launcher shows no flatpak app at all, because SDDM starts the
# session through `$SHELL --login` (its wayland-session script re-execs itself
# that way for zsh) and so the whole graphical session inherits this same
# XDG_DATA_DIRS.
#
# Numbered 46 so it lands immediately after 45-nix.zsh. Order matters in one
# direction only: nix.sh rewrites XDG_DATA_DIRS wholesale when it finds it
# unset, so running before it would work but leaves the result depending on
# which branch of nix.sh happened to be taken.
if (( $+commands[flatpak] )); then
  _flatpak_prefix=

  # User installation ahead of the system one -- the same precedence
  # /etc/profile.d/flatpak.sh applies, so that a `flatpak install --user` copy
  # of an app wins over a system-wide one.
  #
  # Only the two standard locations are consulted, rather than shelling out to
  # `flatpak --installations` the way the distro script does. That call costs a
  # process on every login shell, and this account has no custom installation
  # configured in /etc/flatpak/installations.d. Add the query here if that ever
  # stops being true.
  for _flatpak_exports in \
    "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share" \
    /var/lib/flatpak/exports/share
  do
    # Skip what does not exist -- there is no user export directory until the
    # first `flatpak install --user` -- and skip what is already present.
    # .zprofile is re-sourced by .zshrc in non-login interactive shells, so a
    # snippet that is not idempotent grows a duplicate entry per shell.
    [[ -d "$_flatpak_exports" ]] || continue
    case ":${XDG_DATA_DIRS}:" in
      (*":$_flatpak_exports:"*) continue ;;
    esac
    _flatpak_prefix="${_flatpak_prefix:+$_flatpak_prefix:}$_flatpak_exports"
  done

  if [[ -n "$_flatpak_prefix" ]]; then
    export XDG_DATA_DIRS="$_flatpak_prefix${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
  fi

  unset _flatpak_exports _flatpak_prefix
fi
