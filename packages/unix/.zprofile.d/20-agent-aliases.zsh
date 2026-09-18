# Local Qwen3.8 via pi coding agent
#
# These dotfiles deploy to the VM only. Inference runs on the Mac host, which
# the VM reaches at 192.168.64.1 over the host-only bridge; the provider name
# comes from packages/common/.pi/agent/models.json. Both variables are
# overridable for the unusual case (a different host address, a second model),
# but there is no per-machine switching to do -- nothing here runs on the host.
: "${PI_LLAMA_MODEL:=llama/qwen3.8-27b}"
: "${PI_LLAMA_URL:=http://192.168.64.1:8001}"
export PI_LLAMA_MODEL PI_LLAMA_URL

# The one-shot (-p) helpers redirect stdin from /dev/null. Without it, pi
# blocks reading stdin whenever it has no TTY -- backgrounded, in a cron job,
# under CI -- despite -p meaning non-interactive. It does not time out or warn:
# it hangs with the model server completely idle, which is indistinguishable
# from a slow generation. Measured once at 3m22s of hang for 0.42s of CPU.
#
# pi-local and pi-fast are interactive and must NOT redirect stdin.
#
# Thinking costs real time on a local model (~16 tok/s here), and it is spent
# before any answer appears -- a small max-tokens budget can be consumed
# entirely by reasoning, returning empty content. So thinking is off for the
# quick helpers and for pi-fast, and left on where the reasoning is the point.
ask()       { pi --model "$PI_LLAMA_MODEL" --thinking off -p "$@" < /dev/null; }
ask-think() { pi --model "$PI_LLAMA_MODEL" -p "$@" < /dev/null; }
pi-local()  { pi --model "$PI_LLAMA_MODEL" "$@"; }
pi-fast()   { pi --model "$PI_LLAMA_MODEL" --thinking off "$@"; }

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
