#!/bin/bash
# =============================================================================
# ds4-setup.sh  —  Host bootstrap for DeepSeek V4 Flash (ds4) on Ubuntu/Debian
#
# Run on EACH node you want to use for ds4 (single or multi-node).
# BOOTSTRAP ONLY — installs packages, GRUB ROCm args, shared-memory pool, the
# ds4 distrobox, HF CLI, and downloads model weights. It does NOT launch the
# server; use the generated scripts/ds4-start.sh (DS4_ROLE=single|coordinator|worker)
# when you are ready to serve.
#
# Config via env (or edit below):
#   DS4_MODE          single|multi (default multi)
#   DS4_TTM_GB        shared GPU pool size (default 110)
#   DS4_MODELS_DIR    model storage dir (default ~/ds4)
#   DS4_DOWNLOAD_SINGLE 1 to download IQ2_XXS (~80.8GB)
#   DS4_DOWNLOAD_MULTI  1 to download Q4KExperts (~153GB)
#   DS4_DOWNLOAD_MTP    1 to download MTP weights (~3.6GB)
#   HF_TOKEN          HuggingFace token (gated model downloads; read from hf_token.txt if unset)
#
# Requires sudo. Run WITHOUT root (sudo is invoked as needed).
# =============================================================================
set -euo pipefail

# --- config (env overridable) ---
DS4_MODE="${DS4_MODE:-multi}"
DS4_TTM_GB="${DS4_TTM_GB:-110}"
DS4_MODELS_DIR="${DS4_MODELS_DIR:-$HOME/ds4}"
DS4_DOWNLOAD_SINGLE="${DS4_DOWNLOAD_SINGLE:-0}"
DS4_DOWNLOAD_MULTI="${DS4_DOWNLOAD_MULTI:-1}"
DS4_DOWNLOAD_MTP="${DS4_DOWNLOAD_MTP:-0}"
DS4_HF_TOKEN="${HF_TOKEN:-$(cat "$(dirname "$0")/../hf_token.txt" 2>/dev/null || true)}"

SINGLE_MODEL="DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix.gguf"
MULTI_MODEL="DeepSeek-V4-Flash-Q4KExperts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-imatrix.gguf"
MTP_MODEL="DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf"

# --- detect OS family ---
if [ -f /etc/os-release ]; then . /etc/os-release; fi
case "${ID:-}" in
    ubuntu|debian) PKG_MAN=apt ;;
    *) echo "Unsupported OS: ${ID:-unknown}. Expected Debian/Ubuntu (apt)." >&2; exit 1 ;;
esac
echo "Detected package manager: $PKG_MAN   ds4 mode: $DS4_MODE"

# --- 1. packages ---
sudo apt update
sudo apt install -y \
    python3 python3-venv python3-pip libboost-all-dev dkms podman distrobox \
    pipx gcc git rocm rocm-smi cargo

# --- 2. user-level toolchain ---
cargo install amdgpu_top --locked || true
pipx install "git+https://github.com/kyuz0/strix-halo-ds4-toolbox.git#subdirectory=ds4-strix-halo-cockpit"
pipx install amd-debug-tools
pipx install "huggingface_hub[cli]"
pipx ensurepath
source ~/.bashrc 2>/dev/null || true

# --- 3. GRUB ROCm kernel args ---
GRUB_ARGS="amd_iommu=off amdgpu.gttsize=126976 ttm.pages_limit=32505856 ttm.page_pool_size=32505856"
if grep -q "$GRUB_ARGS" /etc/default/grub 2>/dev/null; then
    echo "GRUB args already present: $GRUB_ARGS"
else
    echo "Adding GRUB args: $GRUB_ARGS"
    sudo sed -i "s/^GRUB_CMDLINE_LINUX=\"\(.*\)\"$/GRUB_CMDLINE_LINUX=\"\1 $GRUB_ARGS\"/" /etc/default/grub
    sudo update-grub
    echo "WARNING [reboot] GRUB changed — REBOOT required before serving."
fi

# --- 4. shared-memory pool ---
# TTM/shared pool is set by the GRUB kernel args above (ttm.pages_limit => ~124GB);
# no amd-ttm --set needed. Set BIOS UMA VRAM to Auto/minimum, then REBOOT.
echo "NOTE [ttm] shared pool comes from GRUB ttm.pages_limit (above); set BIOS UMA VRAM to Auto/minimum."

# --- 5. ds4 distrobox (multi-node image) ---
if [ "$DS4_MODE" = "multi" ]; then
    IMAGE="docker.io/kyuz0/strix-halo-ds4-toolbox:multi-node-rocm-7.14"
    NAME="ds4-multi-node-rocm-7.14"
else
    IMAGE="docker.io/kyuz0/strix-halo-ds4-toolbox:rocm-7.14"
    NAME="ds4-rocm-7.14"
fi
echo "Creating ds4 distrobox '$NAME' from $IMAGE ..."
distrobox create --name "$NAME" --image "$IMAGE" --additional-flags \
    "--device /dev/dri --device /dev/kfd --group-add video --group-add render \
     --group-add sudo --security-opt seccomp=unconfined"

# --- 6. model downloads ---
mkdir -p "$DS4_MODELS_DIR"
export HF_TOKEN="${DS4_HF_TOKEN:-}"
if [ -n "$HF_TOKEN" ]; then echo "HF token set (gated downloads)."; fi

if [ "$DS4_DOWNLOAD_SINGLE" = "1" ]; then
    HF_XET_HIGH_PERFORMANCE=1 hf download antirez/deepseek-v4-gguf "$SINGLE_MODEL" --local-dir "$DS4_MODELS_DIR"
fi
if [ "$DS4_DOWNLOAD_MULTI" = "1" ]; then
    HF_XET_HIGH_PERFORMANCE=1 hf download antirez/deepseek-v4-gguf "$MULTI_MODEL" --local-dir "$DS4_MODELS_DIR"
fi
if [ "$DS4_DOWNLOAD_MTP" = "1" ]; then
    HF_XET_HIGH_PERFORMANCE=1 hf download antirez/deepseek-v4-gguf "$MTP_MODEL" --local-dir "$DS4_MODELS_DIR"
fi

echo -e "\nDS4 host setup done on $(hostname). Next:"
echo "  REBOOT if GRUB args changed, then launch via scripts/ds4-start.sh:"
echo "    DS4_ROLE=coordinator ./scripts/ds4-start.sh   (multi-node, Machine 1)"
echo "    DS4_ROLE=worker      ./scripts/ds4-start.sh   (multi-node, Machine 2)"
echo "    DS4_ROLE=single      ./scripts/ds4-start.sh   (single node)"
echo "Models in: $DS4_MODELS_DIR"
echo "Docs: https://developer.amd.com/playbooks/deepseek-v4-flash-ds4/"
