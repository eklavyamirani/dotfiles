# Local Qwen3.6 via pi coding agent
alias ask='pi --model llama/qwen3.6-27b --thinking off -p'
alias ask-think='pi --model llama/qwen3.6-27b -p'
alias pi-local='pi --model llama/qwen3.6-27b'

# GitHub Copilot with Claude Sonnet 5 at its lowest supported effort
alias ask-copilot='copilot --model claude-sonnet-5 --effort low -p --allow-all-tools'
alias claude='claude --allow-dangerously-skip-permissions'

localClaude() {
  if [[ ! "$*" =~ "--model" ]]; then
    echo "Missing --model! (try using --model unsloth/Qwen3.5-35B-A3B or unsloth/Qwen3-Coder-Next-GGUF)"
    return 1
  fi

  export ANTHROPIC_BASE_URL=http://localhost:8001
  export ANTHROPIC_API_KEY='sk-no-key-required'
  claude --settings ~/.claude-local/settings.json "$@"
}
