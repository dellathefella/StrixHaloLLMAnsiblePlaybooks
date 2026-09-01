# ROCm Inference Bootstrap — Conventions

## Target platform
- **Ubuntu 26.04** (noble) or newer only — bleeding-edge AMD ROCm.
- Primary hardware: HP Z2 G1a (Ryzen AI Max "Strix Halo", gfx1151, 128 GB UMA).
- Local ansible runs use `ansible_connection=local` + `ansible_become_exe=/usr/bin/sudo.ws` (classic C sudo, not sudo-rs) with password-fed `become` via `-K`.

## Directory layout
```
ansible/
  bootstrap.yml                orchestrator — static import_playbook of all tracks
  shared/                      shared setup playbooks: install-amdgpu (ROCm), install-podman,
                               install-hf-cli, set-grub-ttm, set-limine-ttm (imported by both tracks)
  summary.yml                  final per-host completion summary
  <track>.yml                  per-track playbook (see track naming below)
  tasks/
    rocm-build-deps.yml        shared ROCm + dev packages (HIP, CMake, etc.)
    vulkan-build-deps.yml      shared Vulkan/RADV + dev packages
  templates/
    <track>-start.sh.j2        launch script — rendered to scripts/
    pi-<track>.json.j2         pi agent config — rendered to pi-configs/
  single-node/ + multi-node/   per-track playbooks, bootstrap, inventory, templates
    inventory/hosts            real inventory — capability groups (vulkan / rocm → aiservers)
    inventory/hosts.example    sample multi-machine inventory (single-node only)
    inventory/group_vars/all   placeholder (empty) — tracks define their vars inline
scripts/                       rendered launch scripts + local installers
pi-configs/                    rendered pi provider configs
```

## Track naming convention

### File naming
Playbooks and templates use the **descriptive model + quant name**. Plays target a
**capability group** (GPU backend) rather than one model — `aiservers` is the union of
all inference hosts, with `vulkan` and `rocm` underneath. A host runs one model at a
time, so hosts are placed **directly** in their backend group (`vulkan`/`rocm`); the
model is chosen by which track playbook you run, not by group membership.

| Playbook | Play targets (`hosts:`) | Track tag (`tags:`) |
|---|---|---|
| `qwen36-35b-ud-q8-k-xl-podman.yml` | `vulkan` | `qwen36-35b-ud-q8-k-xl-podman` |
| `qwen38-27b-ud-q4-k-xl-podman.yml` | `vulkan` | `qwen38-27b-ud-q4-k-xl-podman` |
| `qwen38-flash-next-ud-q2-k-xl-podman.yml` | `vulkan` | `qwen38-flash-next-ud-q2-k-xl-podman` |
| `qwen38-flash-next-ud-iq4-xs-podman.yml` | `vulkan` | `qwen38-flash-next-ud-iq4-xs-podman` |
| `qwen38-flash-next-ap-q5-k-xl-podman.yml` | `vulkan` | `qwen38-flash-next-ap-q5-k-xl-podman` |
| `gemma-4-26b-a4b-ud-q8-k-xl-podman.yml` | `vulkan` | `gemma-4-26b-a4b-ud-q8-k-xl-podman` |
| `qwen38-27b-rocmfp4-podman.yml` | `rocm` | `qwen38-27b-rocmfp4-podman` |
| `qwen35-397b-gptq-rccl.yml` (multi-node) | `rocm` | `qwen35-397b-gptq-rccl` |

### Template naming
- Launch script: `templates/<playbook-name>-start.sh.j2` → renders to `scripts/<playbook-name>-start.sh`
- Pi config: `templates/pi-<playbook-name>.json.j2` → renders to `pi-configs/pi-<playbook-name>.json`

### Variable conventions
Each track playbook is **self-contained** — it defines its own `vars:` block and uses
**no `group_vars`**. Common per-track vars:
- `track_stem` — model stem; basis for the container name and rendered script/config names
- `image_repo` / `image_tag` — container image to pull (`docker_image: "{{ image_repo }}:{{ image_tag }}"`)
- `model` / `hf_repo` — model file and the HF repo
- `port` / `ctx` / `parallel` — host port, context window, and slot count

Tracks that may serve more than one model group the model-specific knobs into a
**profile dict** selected by `active_profile` (see `qwen38-27b-rocmfp4-podman.yml`):
```yaml
active_profile: "qwen38-27b-rocmfp4"
rocm_image_profiles:
  qwen38-27b-rocmfp4:
    image: "ghcr.io/julianmb/q38rocm:1.5.3"
    model: "Qwen3.8-27B-ROCmFP4-FAST.gguf"
    hf_repo: "julianmb/Qwen-3.8-27B-ROCmFP4-FAST-GGUF"
    port: 8080
    ctx: 131072
    parallel: 1
```
Flat vars (`docker_image`, `model`, `port`, ...) are derived from
`{{ rocm_image_profiles[active_profile] }}`, so `image_repo`/`image_tag` keep working.

## Playbook structure

### Two-play pattern
Every track playbook follows a two-play structure:

1. **Bootstrap play** (`become: yes`, runs on target host):
   - Includes task file for build deps (`rocm-build-deps.yml` or `vulkan-build-deps.yml`)
   - Clones and builds llama.cpp (or other engine) into the track-specific directory
   - Downloads model weights from HuggingFace via `hf`
   - Verifies binary + model files, emits summary

2. **Render play** (`become: no`, `run_once: yes`, `delegate_to: localhost`):
   - Renders `*-start.sh.j2` → `scripts/<track>-start.sh` (mode `0755`)
   - Renders `pi-<track>.json.j2` → `pi-configs/pi-<track>.json` (mode `0644`)
   - Checks binary presence on localhost, warns if missing

### Tags
- Bootstrap play: `[<track-tag>]` (matches host group name)
- Deps: `[packages, rocm]` or `[packages, vulkan]`
- Build: `[build]`
- Model: `[model, <track-tag>]`
- Info/summary: `[info]`
- Render play: `[launch, <track-tag>]`

The orchestrator tag for the whole bootstrap is the playbook's `--tags` value — use the **short track tag** (e.g., `qwen38-27b`), not the full playbook name.

## Shared vs isolated directories

### Shared (common) paths
Legacy source-build tracks shared these as `llama_common_*`; the podman tracks are
self-contained and `group_vars/all.yml` is an empty placeholder:
- `llama_common_home`: `/home/{{ ansible_user }}`
- `llama_common_models_dir`: `{{ llama_common_home }}/.local/share/llama-models`
- `llama_common_repo_url`: `https://github.com/ggml-org/llama.cpp.git`

### Isolated per-track engines
Each track clones llama.cpp into its own directory:
- `qwen36-35b-ud-q8-k-xl` → `~/llama-cpp-qwen36`
- `qwen38-27b-ud-q8-k-xl` → `~/llama-cpp-qwen38-27b`
- `qwen38-flash-next-ud-iq4-xs` → `~/llama-cpp-flash` (PR #27742 branch)

This allows independent branching/PRs per track without conflicts.

## Build conventions

### ROCm/HIP builds
- Use `rocm-build-deps.yml` (includes `libhip-dev`, `rocblas`, `hipblas`, `cmake`, etc.)
- CMake flags: `-DGGML_HIP=ON -DGGML_HIP_GRAPHS=ON -DGGML_VULKAN=OFF`
- Release build: `-DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=OFF`
- Install prefix: `{{ <track>_engine_prefix }}`
- HIP env guards in launch scripts: `HSA_ENABLE_SDMA=1`, `HSA_FORCE_FINE_GRAIN_PCIE=1`

### Vulkan builds
- Use `vulkan-build-deps.yml` (idempotent via `ignore_errors: yes`, collection install handled by shell)
- CMake flags: `-DGGML_HIP=OFF -DGGML_VULKAN=ON`
- Device: `Vulkan0` (RADV), not `ROCm0`
- Env: `VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/radeon_icd.x86_64.json"`

### PR builds (Flash track)
- Clone PR refs: `version: "refs/pull/27742/head"`
- Manual patches via `ansible.builtin.shell` with `grep -q` guard + `failed_when: false` for idempotency
- Never use `ansible.builtin.patch` — it requires `community.general` collection

## Template conventions

### Bash launch script headers
```bash
#!/bin/bash
# =============================================================================
# <track>-start.sh — <Model> (<Quant>, ~<size> GB) — <Engine> <Backend>
#
# Generated by the <playbook-name> bootstrap playbook ({{ ansible_date_time.iso8601 }}).
#
# <Model> (<params>) on <Backend> <Engine>:
#   --ctx-size {{ <var>_ctx }}   (<ctx notes>)
#   --n-gpu-layers {{ <var>_n_gpu }}  (<offload notes>)
#   ...
# =============================================================================
set -euo pipefail
```

### Environment variable defaults (Jinja2 → bash)
Use bash default-value syntax with Jinja2 variables — **never** use bare `{{ }}` without a default, as missing vars will produce empty strings:
```bash
VAR_NAME="${VAR_NAME:-{{ var_prefix_value }}}}"
```

**Jinja2 gotcha**: Bash array length syntax `${#array[@]}` starts with `{#` which Jinja2 interprets as a comment. Avoid this pattern in templates; use `${#array[@]}` only where it won't be rendered.

### LD_LIBRARY_PATH
For ROCm/HIP builds:
```bash
LIB_PATH="${<VAR>_LIB:-$(dirname "$<VAR>_BIN")/../lib}"
[ -d "$LIB_PATH" ] && export LD_LIBRARY_PATH="${LIB_PATH}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```
The `${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}` suffix preserves any existing `LD_LIBRARY_PATH` rather than replacing it entirely.

### Sanity checks
Every launch script must validate before `exec`:
```bash
[ -x "$BIN_PATH" ] || { echo "llama-server not found: $BIN_PATH (run bootstrap)" >&2; exit 1; }
[ -f "$MODEL_PATH" ] || { echo "model not found: $MODEL_PATH" >&2; exit 1; }
```

### Pi config JSON format
```json
{
  "providers": {
    "<track-tag>": {
      "name": "<Model Name> (<Quant>, <Profile>)",
      "baseUrl": "http://{{ <var>_host }}:{{ <var>_port }}/v1",
      "api": "openai-completions",
      "apiKey": "<track-tag>-local",
      "models": [{
        "id": "<model-id>",
        "name": "<Model Name> (<Quant>, ~<size> GB)",
        "input": ["text"],
        "contextWindow": {{ <var>_ctx }},
        "maxTokens": 65536,
        "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
      }]
    }
  }
}
```

### Pi config for vision tracks
Multimodal tracks (image input) declare `"input": ["text", "image"]` instead of
`["text"]`, and must ship the llama.cpp vision projector next to the quant
(`--mmproj`) or the server answers text only — see
`gemma-4-26b-a4b-ud-q8-k-xl-podman.yml` + its launch script, which fetches
`mmproj-F16.gguf` and renames it to `gemma-4-26B-A4B-it-mmproj-F16.gguf`.

## Ansible gotchas

### become on local runs
Ubuntu 26.04's default `sudo-rs` reformats ansible's `-p` prompt, causing timeout. Always use:
```yaml
localhost ansible_connection=local ansible_user=jdella ansible_become_exe=/usr/bin/sudo.ws
```

### include_tasks for deps
Shared dependency tasks live in `tasks/` and are included with `ansible.builtin.include_tasks` (not `import_tasks`) so they respect tags and can be conditionally skipped:
```yaml
- name: Include ROCm build dependencies
  ansible.builtin.include_tasks:
    file: tasks/rocm-build-deps.yml
  tags: [packages, rocm]
```

### git clone with PR refs
For PR-based builds:
```yaml
- name: Clone llama.cpp PR #NNNNN
  ansible.builtin.git:
    repo: "{{ llama_common_repo_url }}"
    dest: "{{ <track>_engine_repo }}"
    version: "refs/pull/NNNNN/head"
    force: yes
  become: no
```

### Merged PRs need no PR build
Before writing a PR-clone task, check whether the PR has since **merged**. The
`qwen38-flash-next-*` tracks originally needed PR #27742 (`qwen4exp`) built from
`refs/pull/27742/head` plus a hand-patch to `graph_max_nodes()`; that PR merged
into master on 2026-08-27, and the container tag pinned here (b10666, built
2026-08-28) already contains the arch and the patch. Track playbooks therefore
use the plain image. Verify against the merge commit (or the pinned build's
`target_commitish`) before assuming a source build is required.

## Adding a new track

1. Define the track's vars inline in its playbook `vars:` block (self-contained, no
   `group_vars`): `track_stem`, `image_repo`/`image_tag`, `model`/`hf_repo`,
   `port`/`ctx`/`parallel`, plus any track-specific flags. For multi-model tracks use
   the `active_profile` + profile-dict pattern (see `qwen38-27b-rocmfp4-podman.yml`).

2. Create `ansible/<track>.yml` with two plays (bootstrap + render), following the two-play pattern above.

3. Create templates:
   - `ansible/templates/<track>-start.sh.j2`
   - `ansible/templates/pi-<track>.json.j2`

4. Add the host to its capability group (`vulkan` or `rocm`, under `aiservers`) in the
   track's `inventory/hosts`; mirror it in `hosts.example`. A host runs one model at a
   time, so there is no per-model group to add.

5. Add `import_playbook` to `ansible/bootstrap.yml`.

6. Update `README.md` layout tree and quick-start sections.

7. Ensure `tags: [<track-tag>]` on all tasks so `--tags <track-tag>` works.
