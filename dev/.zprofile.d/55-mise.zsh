# mise: per-project language/tool version manager. Installs entirely in
# userspace (~/.local/share/mise) — no sudo required either way.
#
# Numbered after 50-homebrew-isolated.zsh on purpose: mise is installed via
# Homebrew (see Brewfile), so ~/.homebrew/bin must already be on PATH here.
eval "$(mise activate zsh)"
