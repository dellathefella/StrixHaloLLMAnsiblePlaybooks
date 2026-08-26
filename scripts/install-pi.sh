#!/bin/bash
# =============================================================================
# install-pi.sh  —  Install pi (coding agent) + the pi plugins on this system
#
# LOCAL pi install only. Installs:
#   - pi coding agent (pi.dev install script), if not already present
#   - the pi plugins/extensions that exist on this system (permission-system,
#     web-access, background-tasks, ask-user-question, pi-ds4)
#   - merges the pi provider configs from pi-configs/ into ~/.pi/agent/models.json
#     (pi-ds4, pi-gemma, pi-qwen36, pi-qwen-rccl — whichever are present)
#
# This is NOT the DS4 host setup. It installs no ROCm/distrobox/model weights —
# those live in scripts/ds4-setup.sh (DS4 itself). Run this on the controller.
#
# Requires no sudo (pi install is user-level). Run WITHOUT root.
# =============================================================================
set -euo pipefail

# --- 1. pi coding agent ---
if command -v pi >/dev/null 2>&1; then
    echo "pi already installed: $(pi --version 2>/dev/null || echo 'present')"
else
    echo "Installing pi from https://pi.dev ..."
    curl -fsSL https://pi.dev/install.sh | sh
fi

# --- 2. pi plugins present on this system (from ~/.pi/agent/settings.json) ---
PI_PLUGINS=(
    "npm:pi-web-access"                              # pi-web-access (web search/fetch)
    "npm:@juicesharp/rpiv-ask-user-question"         # ask-user-question
    "npm:pi-background-tasks"                        # background tasks
    "npm:@gotgenes/pi-permission-system"             # permission system
    "https://github.com/mitsuhiko/pi-ds4"            # pi-ds4 (DS4 provider plugin)
)
for p in "${PI_PLUGINS[@]}"; do
    echo "Installing pi plugin: $p"
    pi install "$p" || echo "WARNING [pi] plugin '$p' install failed — install later with 'pi install $p'."
done

# --- 3. merge pi provider configs into ~/.pi/agent/models.json ---
mkdir -p ~/.pi/agent
CFG=~/.pi/agent/models.json
SCRIPTS_DIR="$(dirname "$0")"
CONFIGS_DIR="$(dirname "$0")/../pi-configs"
PY_MERGE='
import json, os, sys
def load(p):
    with open(p) as f: return json.load(f)
cfg_path = sys.argv[1]
cfgs_dir = sys.argv[2]
out = load(cfg_path) if os.path.exists(cfg_path) and os.path.getsize(cfg_path) > 0 else {"providers": {}}
providers = out.setdefault("providers", {})
merged = False
for fn in sorted(os.listdir(cfgs_dir)):
    if not fn.endswith(".json"): continue
    p = os.path.join(cfgs_dir, fn)
    try:
        d = load(p)
    except Exception as e:
        print(f"  WARNING: skipping {fn}: {e}"); continue
    for name, block in (d.get("providers") or {}).items():
        if name in providers and providers[name] == block:
            print(f"  {fn}: provider {name!r} unchanged"); continue
        providers[name] = block
        print(f"  {fn}: merged provider {name!r}")
    merged = True
if merged:
    out["providers"] = providers
    with open(cfg_path, "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"Wrote {cfg_path} with {len(providers)} provider(s).")
else:
    print("No provider configs to merge.")
'
if [ -d "$CONFIGS_DIR" ] && [ -n "$(ls -A "$CONFIGS_DIR" 2>/dev/null)" ]; then
    echo "Merging pi provider configs from $CONFIGS_DIR into $CFG ..."
    python3 -c "$PY_MERGE" "$CFG" "$CONFIGS_DIR"
else
    echo "No pi-configs present yet — run the ansible bootstrap to drop them."
fi

echo -e "\nDone. Local pi install:"
echo "  pi (coding agent) + plugins: pi-web-access, rpiv-ask-user-question, pi-background-tasks,"
echo "  pi-permission-system, pi-ds4"
echo "  providers merged into ~/.pi/agent/models.json"
echo
echo "Next: DS4 host setup is separate — run ./scripts/ds4-setup.sh for the DS4 node."
