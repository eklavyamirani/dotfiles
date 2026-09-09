# Thin loader: source every snippet in ~/.zprofile.d/ in filename order.
# Snippets are prefixed with numbers (10-, 20-, ...) to control load order.
# Numbering sorts globally across packages, because stow merges every
# package's .zprofile.d/ into this one directory.
#
# The sentinel is exported for ~/.zshrc, which sources this file when zsh did
# not. zsh reads .zprofile for LOGIN shells only, and while macOS Terminal.app
# starts login shells by default, most Linux terminal emulators start non-login
# interactive ones -- where, without that fallback, none of this runs and the
# entire deployment is invisible. Exported rather than plain so nested shells
# inherit it and do not repeat the work (compinit and `mise activate` are not
# free).
for _zprofile_snippet in "$HOME"/.zprofile.d/*.zsh(N); do
  source "$_zprofile_snippet"
done
unset _zprofile_snippet

_DOTFILES_PROFILE_LOADED=1
export _DOTFILES_PROFILE_LOADED
