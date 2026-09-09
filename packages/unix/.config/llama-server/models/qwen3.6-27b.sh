#!/usr/bin/env bash
# Qwen3.6-27B MTP server launcher
# Usage: ./qwen3.6-27b.sh [profile] [extra args...]
# Profiles: coding (default), thinking, instruct
#
# Examples:
#   ./qwen3.6-27b.sh                    # coding profile
#   ./qwen3.6-27b.sh thinking           # general reasoning
#   ./qwen3.6-27b.sh coding --ctx-size 131072  # coding + 128K context

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"

# Model paths
MODEL_DIR="$HOME/.huggingface/unsloth/Qwen3.6-27B-MTP-GGUF"
MODEL="$MODEL_DIR/Qwen3.6-27B-UD-Q4_K_XL.gguf"
MMPROJ="$MODEL_DIR/mmproj-BF16.gguf"

# Defaults
PROFILE="${1:-coding}"
shift 2>/dev/null || true

# Load profile
PROFILE_FILE="$CONFIG_DIR/profiles/${PROFILE}.env"
if [[ ! -f "$PROFILE_FILE" ]]; then
    echo "Error: Unknown profile '$PROFILE'"
    echo "Available profiles: $(ls "$CONFIG_DIR/profiles/" | sed 's/\.env//g' | tr '\n' ' ')"
    exit 1
fi
source "$PROFILE_FILE"

# Verify model exists
if [[ ! -f "$MODEL" ]]; then
    echo "Error: Model not found at $MODEL"
    echo "Download with:"
    echo "  hf download unsloth/Qwen3.6-27B-MTP-GGUF --include '*UD-Q4_K_XL*' '*mmproj*' --local-dir $MODEL_DIR"
    exit 1
fi

# Find llama-server binary
LLAMA_SERVER="${LLAMA_SERVER:-$(which llama-server 2>/dev/null || echo "$HOME/repositories/llama.cpp/build/bin/llama-server")}"

echo "=== Qwen3.6-27B MTP ==="
echo "Profile: $PROFILE"
echo "Model:   $MODEL"
echo "Binary:  $LLAMA_SERVER"
echo "========================"

# Build command
CMD=(
    "$LLAMA_SERVER"
    --model "$MODEL"
    --mmproj "$MMPROJ"
    --temp "$LLAMA_TEMP"
    --top-p "$LLAMA_TOP_P"
    --top-k "$LLAMA_TOP_K"
    --min-p "$LLAMA_MIN_P"
    --presence-penalty "$LLAMA_PRESENCE_PENALTY"
    --repeat-penalty "$LLAMA_REPEAT_PENALTY"
    --spec-type draft-mtp
    --spec-draft-n-max 2
    --cache-type-k q8_0
    --cache-type-v q8_0
    --ctx-size "${LLAMA_CTX_SIZE:-65536}"
    --port "${LLAMA_PORT:-8001}"
)

# Add extra args from profile
if [[ -n "${LLAMA_EXTRA_ARGS:-}" ]]; then
    eval CMD+=($LLAMA_EXTRA_ARGS)
fi

# Add any remaining CLI args
CMD+=("$@")

exec "${CMD[@]}"
