# Thin loader: source every snippet in ~/.zprofile.d/ in filename order.
# Snippets are prefixed with numbers (10-, 20-, ...) to control load order.
for _zprofile_snippet in "$HOME"/.zprofile.d/*.zsh(N); do
  source "$_zprofile_snippet"
done
unset _zprofile_snippet
