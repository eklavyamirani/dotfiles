# llama-server Configuration

Local LLM server configs for llama.cpp.

The current model is **Qwen3.8-27B**. `qwen3.6-27b.sh` and the top-level
`profiles/*.env` it reads are the previous generation, kept only so an
existing 3.6 download keeps working; new work should use the 3.8 script.

## Quick Start

```bash
# Run Qwen3.8-27B for coding (default), loopback only
~/.config/llama-server/models/qwen3.8-27b.sh

# Run with thinking profile
~/.config/llama-server/models/qwen3.8-27b.sh thinking

# Override context size
~/.config/llama-server/models/qwen3.8-27b.sh coding --ctx-size 131072

# Override port
LLAMA_PORT=9000 ~/.config/llama-server/models/qwen3.8-27b.sh

# Serve the local VM (see "Serving the VM" below)
LLAMA_HOST=192.168.64.1 ~/.config/llama-server/models/qwen3.8-27b.sh coding
```

## Structure

```
profiles/       Reusable parameter presets
  coding.env    Qwen3.6: precise coding (temp=0.6, no presence penalty)
  thinking.env  Qwen3.6: general reasoning (temp=1.0, presence penalty=1.5)
  instruct.env  Qwen3.6: non-thinking mode (temp=0.7)
  qwen3.8/      Qwen3.8 sampling sets (different from 3.6 -- see below)
    coding.env
    thinking.env
    instruct.env
models/         Per-model launcher scripts
  qwen3.6-27b.sh
  qwen3.8-27b.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LLAMA_SERVER` | auto-detect | Path to llama-server binary |
| `LLAMA_HOST` | `127.0.0.1` | Bind address (3.8 script only) |
| `LLAMA_PORT` | 8001 | Server port |
| `LLAMA_CTX_SIZE` | 65536 | Context window size |
| `LLAMA_QUANT` | `UD-Q4_K_XL` | Quant to load (3.8 script only) |
| `LLAMA_MTP` | 1 | Set to 0 to disable MTP speculative decoding |
| `LLAMA_MODEL_DIR` | `~/.huggingface/Qwen` | Where the GGUFs live (3.8 script only) |
| `LLAMA_KV_Q8` | 0 | Set to 1 for a q8_0 KV cache (slower here; see below) |

## Models Location

Models are stored in `~/.huggingface/Qwen` (separate from this config), which
is what the host actually uses. Override with `LLAMA_MODEL_DIR` if a machine
fetched them elsewhere.

### KV cache

The launcher leaves the KV cache at f16. Measured on the M3 Max, the `q8_0`
cache inherited from the Qwen3.6 script cost about 30% of generation
throughput (7.1 vs 9.3 tok/s) to save memory this machine has to spare. Set
`LLAMA_KV_Q8=1` only when context size is genuinely memory-constrained.

### Downloading Qwen3.8-27B

```bash
hf download unsloth/Qwen3.8-27B-GGUF \
    --include "*UD-Q4_K_XL*" --include "*mmproj-BF16*" --include "MTP/*" \
    --local-dir ~/.huggingface/Qwen
```

That is ~20 GB: the 17.6 GB weights, a 0.9 GB vision projector, and the
1.4 GB MTP draft model.

### Quant choice on the 96 GB M3 Max

`UD-Q4_K_XL` is the default because it is the fastest to decode and leaves
plenty of headroom. All of these fit; set `LLAMA_QUANT` to switch.

| Quant | Size | Notes |
|-------|------|-------|
| `UD-Q4_K_XL` | 17.6 GB | Default. Best tokens/sec. |
| `UD-Q5_K_XL` | 20.9 GB | |
| `UD-Q6_K_XL` | 25.3 GB | Noticeably better on code, still comfortable. |
| `UD-Q8_K_XL` | 31.5 GB | Near-lossless; slowest of the four. |

Decode speed on this machine is bound by memory bandwidth, so the size column
is roughly inversely proportional to tokens/sec.

### MTP (speculative decoding)

Unlike Qwen3.6, where the MTP head was baked into the main GGUF, Qwen3.8
ships it as a **separate draft model** under `MTP/`. The launcher passes it as
`--model-draft ... --spec-type draft-mtp --spec-draft-n-max 2`. It is enabled
by default, costs 1-2 GB, and is skipped automatically if the `MTP/` file was
not downloaded. Set `LLAMA_MTP=0` to disable.

## Serving the VM

The VM reaches the host over the host-only bridge, where the host is
`192.168.64.1`. The server has **no authentication**, so it binds loopback
unless told otherwise:

```bash
LLAMA_HOST=192.168.64.1 ~/.config/llama-server/models/qwen3.8-27b.sh coding
```

Bind to `192.168.64.1` rather than `0.0.0.0`: it exposes the server on the VM
bridge only, not on Wi-Fi/Ethernet. The script prints a warning whenever it
binds a non-loopback address.

On the VM side, pi selects the `llama-host` provider (which points at
`http://192.168.64.1:8001/v1`) via `PI_LLAMA_PROVIDER`, set in an untracked
`~/.zprofile.d/25-local-llama-provider.zsh`. See the repository README.

## Parameter Reference (Qwen3.8)

Source: https://unsloth.ai/docs/models/qwen3.8

| Use Case | temp | top_p | top_k | presence_penalty |
|----------|------|-------|-------|-----------------|
| Thinking / coding | 1.0 | 0.95 | 20 | 0.0 |
| Instruct (non-thinking) | 0.7 | 0.80 | 20 | 1.5 |

Qwen3.8 publishes only these two sampling sets, so the `coding` profile uses
the thinking values verbatim. This differs from Qwen3.6 in two ways worth
noting: 3.6's coding profile lowered temp to 0.6, and 3.6's thinking profile
used `presence_penalty=1.5` where 3.8 wants `0.0`.

Native context is 262144 tokens (extendable to 1M via YaRN); the launcher
defaults to 65536 to keep the KV cache small, and `contextWindow` in pi's
`models.json` is set to match.

## Parameter Reference (Qwen3.6, legacy)

Source: https://unsloth.ai/docs/models/qwen3.6

| Use Case | temp | top_p | presence_penalty |
|----------|------|-------|-----------------|
| Coding (thinking) | 0.6 | 0.95 | 0.0 |
| General (thinking) | 1.0 | 0.95 | 1.5 |
| Instruct (non-thinking) | 0.7 | 0.8 | 1.5 |
