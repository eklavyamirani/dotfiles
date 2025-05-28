export PS1='%n@%m %1~ %# '

# set nvim as the default editor
export EDITOR='nvim'

# Increase Bash history size. Allow 32³ entries; the default is 500.
export HISTSIZE='32768';
export HISTFILESIZE="${HISTSIZE}";
# Omit duplicates and commands that begin with a space from history.
export HISTCONTROL='ignoreboth';

alias nvim-kickstart="NVIM_APPNAME=nvim-kickstart; nvim"
export NVIM_APPNAME=nvim

alias ls="ls -a"
alias custom_dockerlast="docker ps -lq"

# custom helper functions
my-add-path-directory() {
    if [[ -d "$1" ]]; then
        export PATH="$1:$PATH"
        echo "Added $1 to PATH"
    else
        echo "$1 is not a valid directory"
    fi
}

eval "$(/opt/homebrew/bin/brew shellenv)"
