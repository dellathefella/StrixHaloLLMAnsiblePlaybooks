#!/usr/bin/env bash
# =============================================================================
# qwen38-start.sh  —  Qwen3.8-27B llama.cpp launch (ROCm, MTP speculative decode)
#
# Templated by ansible/bootstrap.yml (PLAY 5, qwen38 group) and dropped locally
# as scripts/qwen38-start.sh. Single-node server on the Strix Halo APU.
#
# Model: Qwen3.8-27B (native ctx 262144). Quant + flags baked from inventory;
# override with env. MTP (multi-token prediction) uses the model's built-in
# draft head and ~doubles throughput — ON by default.
#
# Env overrides:
#   QWEN38_MODEL   model gguf path (default baked)
#   QWEN38_BIN     llama-server binary (default baked)
#   QWEN38_HOST    bind host (default baked)
#   QWEN38_PORT    serve port   (default baked)
#   QWEN38_CTX     context      (default baked; minimum 261k enforced)
#   QWEN38_MTP     1|0          speculative MTP on/off (default 1)
#   QWEN38_DRAFT_N draft depth  (default baked)
#   QWEN38_DRAFT_PMIN draft acceptance threshold (default baked)
# =============================================================================
set -euo pipefail

QWEN38_MODEL="${QWEN38_MODEL:-/home/jdella/.local/share/Qwen3.8-27B/Qwen3.8-27B-UD-Q4_K_XL.gguf}"
QWEN38_BIN="${QWEN38_BIN:-/home/jdella/llama.cpp/build/bin/llama-server}"
QWEN38_HOST="${QWEN38_HOST:-0.0.0.0}"
QWEN38_PORT="${QWEN38_PORT:-8082}"
QWEN38_CTX="${QWEN38_CTX:-262144}"
QWEN38_MTP="${QWEN38_MTP:-1}"
QWEN38_DRAFT_N="${QWEN38_DRAFT_N:-4}"
QWEN38_DRAFT_PMIN="${QWEN38_DRAFT_PMIN:-0.2}"

# --- HSA tuning for the APU (Strix Halo gfx1151): SDMA-off, XNACK on ---
export HSA_ENABLE_SDMA=0
export HSA_XNACK=1

# --- CPU performance profile (does not survive reboot) ---
if [ "$(powerprofilesctl get)" != "performance" ] 2>/dev/null; then
  echo "qwen38-start: switching CPU to performance power profile (sudo)..." >&2
  sudo powerprofilesctl set performance || true
fi

# --- context floor: 261k minimum (native max 262144) ---
case "$QWEN38_CTX" in
  ''|*[!0-9]*) echo "qwen38-start: QWEN38_CTX must be an integer (got '$QWEN38_CTX')" >&2; exit 2 ;;
esac
if [ "$QWEN38_CTX" -lt 261000 ]; then
  echo "qwen38-start: QWEN38_CTX=$QWEN38_CTX below 261k minimum — raising to 262144" >&2
  QWEN38_CTX=262144
fi

# --- sanity checks ---
[ -x "$QWEN38_BIN" ] || { echo "qwen38-start: llama-server not found at $QWEN38_BIN (build failed?)" >&2; exit 2; }
[ -f "$QWEN38_MODEL" ] || { echo "qwen38-start: model not found at $QWEN38_MODEL (download failed?)" >&2; exit 2; }

# --- MTP speculative decoding (ON by default) ---
MTP_ARGS=()
if [ "$QWEN38_MTP" = "1" ]; then
  MTP_ARGS=( --spec-type draft-mtp --spec-draft-n-max "$QWEN38_DRAFT_N" --spec-draft-p-min "$QWEN38_DRAFT_PMIN" )
fi

echo "qwen38-start: serving $QWEN38_MODEL ctx=$QWEN38_CTX port=$QWEN38_PORT MTP=$QWEN38_MTP" >&2

exec "$QWEN38_BIN" \
  --model "$QWEN38_MODEL" \
  --alias qwen3.8-27b \
  --host "$QWEN38_HOST" --port "$QWEN38_PORT" \
  --ctx-size "$QWEN38_CTX" \
  --n-gpu-layers 999999 \
  --parallel 1 \
  --threads 12 \
  --batch-size 512 --ubatch-size 512 \
  --flash-attn on \
  --cache-type-k f16 --cache-type-v f16 \
  --kv-unified \
  --no-mmap \
  --jinja \
  --reasoning off \
  "${MTP_ARGS[@]}" \
  "$@"
