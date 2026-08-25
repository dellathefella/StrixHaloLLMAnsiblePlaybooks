#!/bin/bash
# =============================================================================
# install-pi-ds4.sh  —  Install pi (coding agent) + all tools needed for DS4
#
# Reproduces the local pi + DS4 toolchain on Ubuntu/Debian:
#   - pi coding agent (pi.dev install script)
#   - ROCm base packages (rocm, rocm-smi, python3, git, cargo, podman, ...)
#   - pipx apps: ds4-cockpit, amd-debug-tools (amd-ttm), huggingface_hub[cli] (hf)
#   - cargo app: amdgpu_top
#   - pi agent config for the local DS4 server (merged into ~/.pi/agent/models.json)
#
# BOOTSTRAP ONLY — installs tools; it does not launch DS4. Run scripts/ds4-setup.sh
# for the per-node host config (GRUB/TTM/distrobox/models), then scripts/ds4-start.sh
# to serve.
#
# Requires sudo. Run WITHOUT root (sudo is invoked as needed).
# =============================================================================
set -euo pipefail

# --- detect OS family ---
if [ -f /etc/os-release ]; then . /etc/os-release; fi
case "${ID:-}" in
    ubuntu|debian) PKG_MAN=apt ;;
    *) echo "Unsupported OS: ${ID:-unknown}. Expected Debian/Ubuntu (apt)." >&2; exit 1 ;;
esac
echo "Installing pi + DS4 toolchain on Ubuntu/Debian ..."

# --- 1. pi coding agent ---
if command -v pi >/dev/null 2>&1; then
    echo "pi already installed: $(pi --version 2>/dev/null || echo 'present')"
else
    echo "Installing pi from https://pi.dev ..."
    curl -fsSL https://pi.dev/install.sh | sh
fi

# --- 2. system packages ---
sudo apt update
sudo apt install -y \
    python3 python3-venv python3-pip libboost-all-dev dkms podman distrobox \
    pipx gcc git rocm rocm-smi cargo curl

# --- 3. pi extension: pre-turn auto-compaction ---
echo "Installing @capyup/pi-auto-compact extension ..."
pi install npm:@capyup/pi-auto-compact || echo "WARNING [pi] auto-compact install failed — install later with 'pi install npm:@capyup/pi-auto-compact'."

# --- 4. pipx apps (DS4 + ROCm tools) ---
pipx install "git+https://github.com/kyuz0/strix-halo-ds4-toolbox.git#subdirectory=ds4-strix-halo-cockpit"   # ds4-cockpit
pipx install amd-debug-tools        # amd-ttm / amd-bios / amd-pstate / amd-s2idle
pipx install "huggingface_hub[cli]" # hf (model downloads)
pipx ensurepath
source ~/.bashrc 2>/dev/null || true

# --- 5. cargo app ---
cargo install amdgpu_top --locked || true

# --- 6. pi agent config for DS4 (merge into ~/.pi/agent/models.json) ---
mkdir -p ~/.pi/agent
CFG=~/.pi/agent/models.json
PI_DS4_JSON="$(dirname "$0")/pi-ds4.json"
if [ -f "$CFG" ]; then
    echo "Merging DS4 provider into $CFG (manual merge of $(basename "$PI_DS4_JSON"))..."
    echo "  Edit $CFG to add the 'ds4' provider block from $PI_DS4_JSON"
    echo "  (see scripts/pi-ds4.json)."
else
    echo "No $CFG yet — copying pi-ds4.json as your models.json."
    cp "$PI_DS4_JSON" "$CFG"
    echo "  Edit $CFG to add the Qwen provider block from scripts/pi-qwen.json."
fi

echo -e "\nDone. Tools now available:"
echo "  pi (coding agent)  ds4-cockpit  amd-ttm  hf  amdgpu_top"
echo "  pi extension: @capyup/pi-auto-compact (pre-turn auto-compaction)"
echo
echo "Next (per-node host config, GRUB/TTM/distrobox/models):"
echo "  ./scripts/ds4-setup.sh"
echo "Then launch DS4 when ready:"
echo "  DS4_ROLE=coordinator ./scripts/ds4-start.sh   (multi-node, Machine 1)"
echo "  DS4_ROLE=worker      ./scripts/ds4-start.sh   (multi-node, Machine 2)"
echo "  DS4_ROLE=single      ./scripts/ds4-start.sh   (single node)"
