#!/usr/bin/env bash
# Qwen3.8-27B server launcher
# Usage: ./qwen3.8-27b.sh [profile] [extra args...]
# Profiles: coding (default), thinking, instruct
#
# Examples:
#   ./qwen3.8-27b.sh                            # coding profile, loopback only
#   ./qwen3.8-27b.sh thinking                   # general reasoning
#   ./qwen3.8-27b.sh coding --ctx-size 131072   # coding + 128K context
#   LLAMA_HOST=192.168.64.1 ./qwen3.8-27b.sh    # reachable from the local VM
#   LLAMA_QUANT=UD-Q6_K_XL ./qwen3.8-27b.sh     # higher-quality quant
#
# Sized for a 96 GB M3 Max: UD-Q4_K_XL (17.6 GB) leaves room for a 64K KV
# cache and the MTP draft model. Q5/Q6/Q8 also fit -- see LLAMA_QUANT below.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"

# Model paths
# Where `hf download --local-dir` put the files. Override with LLAMA_MODEL_DIR
# if a machine fetched them somewhere else.
MODEL_DIR="${LLAMA_MODEL_DIR:-$HOME/.huggingface/Qwen}"
QUANT="${LLAMA_QUANT:-UD-Q4_K_XL}"
MODEL="$MODEL_DIR/Qwen3.8-27B-${QUANT}.gguf"
MMPROJ="$MODEL_DIR/mmproj-BF16.gguf"
# Qwen3.8 ships MTP as a SEPARATE draft model, unlike Qwen3.6 where the MTP
# head was baked into the main GGUF. It must be passed via --model-draft.
MTP_MODEL="$MODEL_DIR/MTP/mtp-Qwen3.8-27B-Q4_0.gguf"

# Defaults
PROFILE="${1:-coding}"
shift 2>/dev/null || true

# Load profile (Qwen3.8 has its own sampling sets; see profiles/qwen3.8/)
PROFILE_FILE="$CONFIG_DIR/profiles/qwen3.8/${PROFILE}.env"
if [[ ! -f "$PROFILE_FILE" ]]; then
    echo "Error: Unknown profile '$PROFILE'"
    echo "Available profiles: $(ls "$CONFIG_DIR/profiles/qwen3.8/" | sed 's/\.env//g' | tr '\n' ' ')"
    exit 1
fi
source "$PROFILE_FILE"

# Verify model exists
if [[ ! -f "$MODEL" ]]; then
    echo "Error: Model not found at $MODEL"
    echo "Download with:"
    echo "  hf download unsloth/Qwen3.8-27B-GGUF \\"
    echo "      --include '*${QUANT}*' --include '*mmproj-BF16*' --include 'MTP/*' \\"
    echo "      --local-dir $MODEL_DIR"
    exit 1
fi

# Find llama-server binary
LLAMA_SERVER="${LLAMA_SERVER:-$(which llama-server 2>/dev/null || echo "$HOME/repositories/llama.cpp/build/bin/llama-server")}"

# Bind address. Defaults to loopback: this server has no authentication, so it
# is never exposed to a network unless asked. Set LLAMA_HOST=192.168.64.1 to
# serve the local VM over the host-only bridge (preferred over 0.0.0.0, which
# would also expose it on Wi-Fi/Ethernet).
HOST="${LLAMA_HOST:-127.0.0.1}"

echo "=== Qwen3.8-27B ==="
echo "Profile: $PROFILE"
echo "Quant:   $QUANT"
echo "Model:   $MODEL"
echo "Binary:  $LLAMA_SERVER"
echo "Listen:  http://${HOST}:${LLAMA_PORT:-8001}"
if [[ "$HOST" != "127.0.0.1" && "$HOST" != "localhost" ]]; then
    echo "WARNING: serving on a non-loopback address with no authentication."
fi
echo "==================="

# Build command
CMD=(
    "$LLAMA_SERVER"
    --model "$MODEL"
    --temp "$LLAMA_TEMP"
    --top-p "$LLAMA_TOP_P"
    --top-k "$LLAMA_TOP_K"
    --min-p "$LLAMA_MIN_P"
    --presence-penalty "$LLAMA_PRESENCE_PENALTY"
    --repeat-penalty "$LLAMA_REPEAT_PENALTY"
    --ctx-size "${LLAMA_CTX_SIZE:-65536}"
    --host "$HOST"
    --port "${LLAMA_PORT:-8001}"
)

# KV cache stays at f16. Qwen3.6's script used q8_0, but measured on the M3 Max
# that cost ~30% generation throughput (7.1 -> 9.3 tok/s when dropped) for a
# memory saving this machine does not need. Set LLAMA_KV_Q8=1 to trade back.
if [[ "${LLAMA_KV_Q8:-0}" != "0" ]]; then
    CMD+=(--cache-type-k q8_0 --cache-type-v q8_0)
fi

# Vision. Skipped if the projector was not downloaded -- passing --mmproj for a
# missing file aborts startup rather than disabling image input.
if [[ -f "$MMPROJ" ]]; then
    CMD+=(--mmproj "$MMPROJ")
fi

# MTP speculative decoding. Opt out with LLAMA_MTP=0; skipped automatically if
# the draft model was not downloaded. Costs ~1-2 GB extra.
if [[ "${LLAMA_MTP:-1}" != "0" && -f "$MTP_MODEL" ]]; then
    CMD+=(--model-draft "$MTP_MODEL" --spec-type draft-mtp --spec-draft-n-max 2)
fi

# Add extra args from profile
if [[ -n "${LLAMA_EXTRA_ARGS:-}" ]]; then
    eval CMD+=($LLAMA_EXTRA_ARGS)
fi

# Add any remaining CLI args
CMD+=("$@")

exec "${CMD[@]}"
