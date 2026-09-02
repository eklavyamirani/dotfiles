# set nvim as the default editor
export EDITOR='nvim'

# Increase Bash history size. Allow 32³ entries; the default is 500.
export HISTSIZE='32768';
export HISTFILESIZE="${HISTSIZE}";
# Omit duplicates and commands that begin with a space from history.
export HISTCONTROL='ignoreboth';

export NVIM_APPNAME=nvim

nvim() {
  if [[ -n "$SSH_CONNECTION" && -z "$TERM_PROGRAM" ]]; then
    TERM_PROGRAM=Apple_Terminal command nvim "$@"
  else
    command nvim "$@"
  fi
}

alias ls="ls -la"

# custom helper functions
my-add-path-directory() {
    if [[ -d "$1" ]]; then
        export PATH="$1:$PATH"
        echo "Added $1 to PATH"
    else
        echo "$1 is not a valid directory"
    fi
}
