# ROCm Inference Bootstrap — Conventions

## Target platform
- **Ubuntu 26.04** (noble) or newer only — bleeding-edge AMD ROCm.
- Primary hardware: HP Z2 G1a (Ryzen AI Max "Strix Halo", gfx1151, 128 GB UMA).
- Local ansible runs use `ansible_connection=local` + `ansible_become_exe=/usr/bin/sudo.ws` (classic C sudo, not sudo-rs) with password-fed `become` via `-K`.

## Directory layout
```
ansible/
  bootstrap.yml                orchestrator — static import_playbook of all tracks
  base.yml                     preflight: packages, ROCm 7.2.4+, GRUB ttm.args
  summary.yml                  final per-host completion summary
  <track>.yml                  per-track playbook (see track naming below)
  tasks/
    rocm-build-deps.yml        shared ROCm + dev packages (HIP, CMake, etc.)
    vulkan-build-deps.yml      shared Vulkan/RADV + dev packages
  templates/
    <track>-start.sh.j2        launch script — rendered to scripts/
    pi-<track>.json.j2         pi agent config — rendered to pi-configs/
  inventory/
    hosts                      real inventory (local groups + vars)
    hosts.example              sample multi-machine inventory
    group_vars/all.yml         single source of truth: defaults for all hosts
scripts/                       rendered launch scripts + local installers
pi-configs/                    rendered pi provider configs
```

## Track naming convention

### File naming
Playbooks, templates, and host groups use the **descriptive model + quant name**:

| Playbook | Host group tag | Variable prefix |
|---|---|---|
| `qwen36-35b-ud-q8-k-xl.yml` | `[qwen36-35b-ud-q8-k-xl]` | `qwen36_35b_ud_q8_k_xl_` |
| `qwen38-27b-ud-q8-k-xl.yml` | `[qwen38-27b]` | `qwen38_27b_ud_q8_k_xl_` |
| `qwen38-flash-next-ud-iq4-xs.yml` | `[qwen38-flash-next]` | `qwen38_flash_next_ud_iq4_xs_` |
| `qwen35-397b-gptq-rccl.yml` | `[qwen35-397b-gptq-rccl]` | `qwen35_397b_gptq_rccl_` |

### Template naming
- Launch script: `templates/<playbook-name>-start.sh.j2` → renders to `scripts/<playbook-name>-start.sh`
- Pi config: `templates/pi-<playbook-name>.json.j2` → renders to `pi-configs/pi-<playbook-name>.json`

### Variable prefix rules
- Replace dashes with underscores in the playbook name to form the prefix.
- `qwen36-35b-ud-q8-k-xl` → `qwen36_35b_ud_q8_k_xl_`
- `qwen38-flash-next-ud-iq4-xs` → `qwen38_flash_next_ud_iq4_xs_`

### Variable naming for llama.cpp tracks
Each llama.cpp track needs **separate** variable names for its engine clone and HF repo:

| Purpose | Variable suffix | Example |
|---|---|---|
| HF repo name (URL) | `_hf_repo` | `qwen38_27b_ud_q8_k_xl_hf_repo: "unsloth/Qwen3.8-27B-GGUF"` |
| Local engine clone path | `_engine_repo` | `qwen38_27b_ud_q8_k_xl_engine_repo: "{{ llama_common_home }}/llama-cpp-qwen38-27b"` |
| Local engine prefix | `_engine_prefix` | `qwen38_27b_ud_q8_k_xl_engine_prefix: "{{ llama_common_home }}/llama-cpp-qwen38-27b"` |
| Local engine binary | `_engine_bin` | `qwen38_27b_ud_q8_k_xl_engine_bin: "{{ llama_common_home }}/llama-cpp-qwen38-27b/bin/llama-server"` |

**Never** use bare `_repo` or `_bin` — always use the `_engine_*` variants for local paths to avoid ambiguity with HF repo names.

## Playbook structure

### Two-play pattern
Every track playbook follows a two-play structure:

1. **Bootstrap play** (`become: yes`, runs on target host):
   - Includes task file for build deps (`rocm-build-deps.yml` or `vulkan-build-deps.yml`)
   - Clones and builds llama.cpp (or other engine) into the track-specific directory
   - Downloads model weights from HuggingFace via `aria2c`
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
Defined in `group_vars/all.yml` as `llama_common_*`:
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

### Aria2 model downloads
- Always use `--file-allocation=none` for sparse allocation on high-bandwidth systems
- Include `--continue=true --allow-overwrite=true` for resumable downloads
- Wrap in `when: not <register>.stat.exists` to skip if model already present
- `changed_when: false` — aria2 exit 0 doesn't mean "changed" if file already existed

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

## Adding a new track

1. Define vars in `group_vars/all.yml`:
   - `_hf_repo`, `_engine_repo`, `_engine_prefix`, `_engine_bin`
   - `_model`, `_ctx`, `_port`, `_host`, `_device`, `_n_gpu`, `_threads`
   - Plus any track-specific flags (`_batch`, `_ubatch`, `_flash_attn`, etc.)

2. Create `ansible/<track>.yml` with two plays (bootstrap + render), following the two-play pattern above.

3. Create templates:
   - `ansible/templates/<track>-start.sh.j2`
   - `ansible/templates/pi-<track>.json.j2`

4. Add host group to `ansible/inventory/hosts` and `hosts.example`.

5. Add `import_playbook` to `ansible/bootstrap.yml`.

6. Update `README.md` layout tree and quick-start sections.

7. Ensure `tags: [<track-tag>]` on all tasks so `--tags <track-tag>` works.
