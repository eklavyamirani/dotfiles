# set nvim as the default editor
export EDITOR='nvim'

# Increase Bash history size. Allow 32³ entries; the default is 500.
export HISTSIZE='32768';
export HISTFILESIZE="${HISTSIZE}";
# Omit duplicates and commands that begin with a space from history.
export HISTCONTROL='ignoreboth';

alias nvim-kickstart="NVIM_APPNAME=nvim-kickstart; nvim"
export NVIM_APPNAME=nvim

# Local Qwen3.6 via pi coding agent
alias ask='pi --model llama/qwen3.6-27b --thinking off -p'
alias ask-think='pi --model llama/qwen3.6-27b -p'
alias pi-local='pi --model llama/qwen3.6-27b'

localClaude() {
  if [[ ! "$*" =~ "--model" ]]; then
    echo "Missing --model! (try using --model unsloth/Qwen3.5-35B-A3B or unsloth/Qwen3-Coder-Next-GGUF)"
    return 1
  fi

  export ANTHROPIC_BASE_URL=http://localhost:8001
  export ANTHROPIC_API_KEY='sk-no-key-required'
  claude --settings ~/.claude-local/settings.json "$@"
}

alias ls="ls -a"
alias custom_dockerlast="docker ps -lq"

eval "$(/opt/homebrew/bin/brew shellenv)"
# Add Homebrew's completions to the shell path
if type brew &>/dev/null; then
  FPATH=$(brew --prefix)/share/zsh/site-functions:$FPATH
  autoload -Uz compinit
  compinit
fi

# lockdown node. Only enable when I need it.
export NVM_DIR="$HOME/.nvm"

verify-node() {
  if [ -x "$NVM_DIR" ]; then
    echo "$NVM_DIR is accessible. Run:"
    echo ""
    echo "sudo chmod -R a-x \"\$NVM_DIR\""
  else
    echo "NVM_DIR is locked down."
  fi
}

# Double check lockdown
verify-node

enable-node() {
  if [ ! -x "$NVM_DIR" ]; then
    echo "$NVM_DIR is not executable. Run:"
    echo ""
    echo "  sudo chmod -R a+x \"\$NVM_DIR\""
    echo ""
    echo "Then run 'enable-node' again."
    return 1
  fi

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
}

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
