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

eval "$(/opt/homebrew/bin/brew shellenv)"

if [ -s $(brew --prefix nvm)/nvm.sh ]; then
  # Setup NVM
  export NVM_DIR="$HOME/.nvm"
  # This loads nvm
  [ -s "$(brew --prefix nvm)/nvm.sh" ] && \. "$(brew --prefix nvm)/nvm.sh"

  # This loads nvm bash_completion
  [ -s "$(brew --prefix nvm)/etc/bash_completion.d/nvm" ] && \. "$(brew --prefix nvm)/etc/bash_completion.d/nvm"
else
  # Display a warning if nvm is not installed via Homebrew
  echo "Warning: nvm (Node Version Manager) not found."
  echo "To install nvm using Homebrew, run: brew install nvm"
fi

# custom helper functions
my-add-path-directory() {
    if [[ -d "$1" ]]; then
        export PATH="$1:$PATH"
        echo "Added $1 to PATH"
    else
        echo "$1 is not a valid directory"
    fi
}

my-add-path-directory ~/.docker/bin
