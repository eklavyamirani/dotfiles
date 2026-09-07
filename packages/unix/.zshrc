# Managed by GNU Stow. Keep this file limited to interactive Zsh setup;
# put environment, aliases, and helper functions in numbered .zprofile.d snippets.

# Load the profile chain if zsh has not already done it.
#
# zsh sources .zprofile for LOGIN shells only. On macOS that is nearly always
# what you get -- Terminal.app starts login shells. On Linux most terminal
# emulators (GNOME Terminal, Konsole, and the rest) start a non-login
# interactive shell, which reads this file and never touches .zprofile. The
# result is a machine that is fully deployed and appears to have nothing
# installed: no mise, no pinned tools, no aliases.
#
# Guarded by the sentinel .zprofile exports, so a login shell does not source
# it twice and a subshell does not repeat it.
if [[ -z "${_DOTFILES_PROFILE_LOADED:-}" && -r "$HOME/.zprofile" ]]; then
  source "$HOME/.zprofile"
fi

# %n - Displays the current username.
# @  - Literal "@" character separator.
# %m - Displays the short hostname (up to the first ".").
# %~ - Displays the relative path of the current directory.
# %# - Displays a "%" for regular users or a "#" if running as root.
export PS1="|%F{green}%n@%m%f|%F{green}%~%f|"$'\n'" %# > "

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
