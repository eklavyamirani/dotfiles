# Local Qwen3.8 via pi coding agent
#
# The same llama-server is reached under two names depending on which machine
# this snippet is running on, because dotfiles is stowed on both the M3 Max
# host and the VM it hosts:
#
#   host -> provider "llama",      http://localhost:8001
#   VM   -> provider "llama-host", http://192.168.64.1:8001
#
# The host is the default. The VM overrides these variables from an untracked
# ~/.zprofile.d/25-local-llama-provider.zsh -- the loader globs *.zsh, so a
# machine-local file sits alongside the stowed symlinks without being
# versioned. Provider names come from packages/common/.pi/agent/models.json.
: "${PI_LLAMA_PROVIDER:=llama}"
: "${PI_LLAMA_URL:=http://localhost:8001}"
: "${PI_LLAMA_MODEL:=qwen3.8-27b}"
export PI_LLAMA_PROVIDER PI_LLAMA_URL PI_LLAMA_MODEL

# Functions, not aliases: the model string is built from variables at call
# time, so a machine-local override applies without re-defining these.
ask()       { pi --model "$PI_LLAMA_PROVIDER/$PI_LLAMA_MODEL" --thinking off -p "$@"; }
ask-think() { pi --model "$PI_LLAMA_PROVIDER/$PI_LLAMA_MODEL" -p "$@"; }
pi-local()  { pi --model "$PI_LLAMA_PROVIDER/$PI_LLAMA_MODEL" "$@"; }

# GitHub Copilot with Claude Sonnet 5 at its lowest supported effort
alias ask-copilot='copilot --model claude-sonnet-5 --effort low -p --allow-all-tools'
alias claude='claude --allow-dangerously-skip-permissions'
alias codex='codex --approve-for-me'

localClaude() {
  if [[ ! "$*" =~ "--model" ]]; then
    echo "Missing --model! (try using --model unsloth/Qwen3.5-35B-A3B or unsloth/Qwen3-Coder-Next-GGUF)"
    return 1
  fi

  export ANTHROPIC_BASE_URL="$PI_LLAMA_URL"
  export ANTHROPIC_API_KEY='sk-no-key-required'
  # Explicit rather than relying on the `claude` alias above: zsh expands
  # aliases inside function bodies at parse time, so the flag would be
  # injected here silently anyway. Local model -- nothing real to protect.
  command claude --allow-dangerously-skip-permissions --settings ~/.claude-local/settings.json "$@"
}
