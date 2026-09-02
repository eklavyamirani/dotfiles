# Managed by GNU Stow. Keep this file limited to interactive Zsh setup;
# put environment, aliases, and helper functions in numbered .zprofile.d snippets.

# %n - Displays the current username.
# @  - Literal "@" character separator.
# %m - Displays the short hostname (up to the first ".").
# %~ - Displays the relative path of the current directory.
# %# - Displays a "%" for regular users or a "#" if running as root.
export PS1="|%F{green}%n@%m%f|%F{green}%~%f|"$'\n'" %# > "

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
