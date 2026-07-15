# llama-server Configuration

Local LLM server configs for llama.cpp.

## Quick Start

```bash
# Run Qwen3.6-27B for coding (default)
~/.config/llama-server/models/qwen3.6-27b.sh

# Run with thinking profile
~/.config/llama-server/models/qwen3.6-27b.sh thinking

# Override context size
~/.config/llama-server/models/qwen3.6-27b.sh coding --ctx-size 131072

# Override port
LLAMA_PORT=9000 ~/.config/llama-server/models/qwen3.6-27b.sh
```

## Structure

```
profiles/       Reusable parameter presets
  coding.env    Precise coding (temp=0.6, no presence penalty)
  thinking.env  General reasoning (temp=1.0, presence penalty=1.5)
  instruct.env  Non-thinking mode (temp=0.7)
models/         Per-model launcher scripts
  qwen3.6-27b.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LLAMA_SERVER` | auto-detect | Path to llama-server binary |
| `LLAMA_PORT` | 8001 | Server port |
| `LLAMA_CTX_SIZE` | 65536 | Context window size |

## Models Location

Models are stored in `~/.huggingface/` (separate from this config).

## Parameter Reference (Qwen3.6)

Source: https://unsloth.ai/docs/models/qwen3.6

| Use Case | temp | top_p | presence_penalty |
|----------|------|-------|-----------------|
| Coding (thinking) | 0.6 | 0.95 | 0.0 |
| General (thinking) | 1.0 | 0.95 | 1.5 |
| Instruct (non-thinking) | 0.7 | 0.8 | 1.5 |
