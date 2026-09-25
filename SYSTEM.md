# ROCm Inference Bootstrap — Conventions

## Target platform

- **CachyOS (Arch-based) first — current fleet — Ubuntu 26.04 (noble) second.**
  Distro-gated shared plays say so in their headers (e.g. `install-amdgpu.yml`
  is Ubuntu-gated; `setup-thunderbolt-net.yml` is distro-agnostic).
- Primary hardware: HP Z2 G1a (Ryzen AI Max "Strix Halo", gfx1151, 128 GB UMA).
- Local ansible runs use `ansible_connection=local` + `ansible_become_exe=/usr/bin/sudo.ws` (classic C sudo, not sudo-rs) with password-fed `become` via `-K`.

## Directory layout

The repo is organized **topology-first**: `single-node/` and `multi-node/` each
carry their own bootstrap, tracks, inventory, and templates. There is **no**
top-level `ansible/tasks/` or `ansible/templates/` — shared pieces live either
under `shared/` (host setup plays) or under each topology's own `tasks/` /
`templates/`.

```
ansible/
  shared/                      host-level setup plays (imported by both bootstraps)
    install-amdgpu.yml           Ubuntu base: apt upgrade + ROCm (Ubuntu-gated)
    install-podman.yml           cross-distro Podman install
    install-hf-cli.yml           HuggingFace CLI install
    set-grub-ttm.yml             GRUB TTM / IOMMU / GTT kernel args
    set-limine-ttm.yml           Limine TTM kernel args (Limine hosts only)
  single-node/                 one box, one model at a time
    bootstrap.yml                ORCHESTRATOR: shared/ + all single-node tracks
    summary.yml                  final per-host completion summary
    <track>-podman.yml           per-track playbook (see track naming below)
    containerfiles/              Containerfiles for the built-from-source tracks
    tasks/                       shared task files included by the tracks:
      podman-models-dir.yml                models dir + ownership
      hf-download-files.yml                HF download loop (skip if present, optional rename)
      podman-build-image.yml               podman build from a Containerfile (skip if tag exists)
      podman-remove-container.yml          podman rm -f before (re)launch
      podman-check-running.yml             start result + running check
      podman-wait-health.yml               sleep + poll /health
      podman-render-launch-artifacts.yml   launch script + opencode config render
    inventory/
      hosts                      real inventory (vulkan / rocm → aiservers)
      hosts.example              sample inventory template
      group_vars/all.yml         placeholder (empty) — tracks define vars inline
    templates/
      scripts/<track_stem>-start.sh.j2                 launch script template
      opencode-configs/opencode-<track_stem>-podman.json.j2  opencode config template
    rendered/                    rendered output (gitignored)
  multi-node/                  2-node cluster tracks
    bootstrap.yml, summary.yml
    setup-thunderbolt-net.yml    TB4 node-to-node link (multinode group only)
    vllm-rccl-moe.yml            vLLM + Ray + RCCL MoE track
    ds4-deepseek-v4-flash-mtp.yml  2-node ds4 pipeline parallel + MTP track
    ds4-deepseek-v41-flash-tp.yml  2-node ds4 V4.1 Flash resident tensor-parallel track
    inventory/                   hosts (halo0 head + halo1 worker; + multinode for TB)
    templates/                   *.sh.j2, opencode-*.json.j2, tb-net-diag.sh.j2
    rendered/                    rendered output (gitignored)
  opencode-configs/            committed rendered opencode configs (controller-side)
  scripts/                     committed rendered launch scripts (controller-side)
  secrets/                     hf_token.txt (gitignored) + PUT_HF_TOKEN_HERE placeholder
```

## Track naming convention

### File naming

Playbooks and templates use the **descriptive model + quant name**. Plays target a
**capability group** (GPU backend) rather than one model — `aiservers` is the union of
all inference hosts, with `vulkan` and `rocm` underneath. A host runs one model at a
time, so hosts are placed **directly** in their backend group (`vulkan`/`rocm`); the
model is chosen by which track playbook you run, not by group membership.

| Playbook | Play targets (`hosts:`) | Track tag (`tags:`) |
| --- | --- | --- |
| `qwen36-35b-ud-q8-k-xl-mtp-podman.yml` | `vulkan` | `qwen36-35b-ud-q8-k-xl-mtp-podman` |
| `qwen38-27b-q38rocm-podman.yml` (prebuilt q38rocm image, MTP speed profile, port 8080) | `vulkan` | `qwen38-27b-q38rocm-podman` |
| `qwen38-flash-next-halogen-podman.yml` (prebuilt halogen-flash-server ROCm image, port 8731) | `rocm` | `qwen38-flash-next-halogen-podman` |
| `qwen38-flash-next-halogen-ablit-podman.yml` (halogen + Ae55667 abliteration patch kit, gated, port 8731) | `rocm` | `qwen38-flash-next-halogen-ablit-podman` |
| `gemma-4-26b-a4b-ud-q8-k-xl-podman.yml` | `vulkan` | `gemma-4-26b-a4b-ud-q8-k-xl-podman` |
| `vllm-rccl-moe.yml` (multi-node) | `rocm` | `vllm-rccl-moe` |
| `ds4-deepseek-v4-flash-mtp.yml` (multi-node) | `rocm` | `ds4-deepseek-v4-flash-mtp` |
| `ds4-deepseek-v41-flash-tp.yml` (multi-node, V4.1 Q2 resident TP) | `ds4-deepseek-v41-flash-tp` | `ds4-deepseek-v41-flash-tp` |
| `setup-thunderbolt-net.yml` (multi-node) | `multinode` | `thunderbolt` | TB4 node-to-node cluster link |

### Template naming

Templates live under the topology's `templates/` dir and are rendered by
`tasks/podman-render-launch-artifacts.yml` using `track_stem`:

- Launch script: `templates/scripts/<track_stem>-start.sh.j2` → renders to the
  **target host's** `~/scripts/<track_stem>-start.sh`
- OpenCode config: `templates/opencode-configs/opencode-<track_stem>-podman.json.j2`
  → renders to the **controller's** `rendered/opencode-configs/opencode-<track_stem>-podman.json`

Note the `-podman` suffix on the opencode config template/filename (the
`track_stem` itself does not carry it).

### Variable conventions

Each track playbook is **self-contained** — it defines its own `vars:` block and uses
**no `group_vars`**. Common per-track vars:

- `track_stem` — model stem; basis for the container name and rendered script/config names
- `image_repo` / `image_tag` — container image to pull (`docker_image: "{{ image_repo }}:{{ image_tag }}"`)
- `model` / `hf_repo` — model file and the HF repo
- `port` / `ctx` / `parallel` — host port, context window, and slot count

Tracks that may serve more than one model group the model-specific knobs into a
**profile dict** selected by `active_profile` (see `vllm-rccl-moe.yml`):

```yaml
active_profile: "minimax-m2.7-awq-4bit"
vllm_moe_profiles:
  minimax-m2.7-awq-4bit:
    hf_repo: "cyankiwi/MiniMax-M2.7-AWQ-4bit"
    display: "MiniMax M2.7 (AWQ-4bit)"
    max_model_len: 196608
    max_tokens: 32768
    dtype: "bfloat16"
```

Flat vars are derived from `{{ vllm_moe_profiles[active_profile] }}`, so a new
model only adds an entry to the dict.

## Playbook structure

### Single-play pattern (Podman tracks)

Each `*-podman.yml` track is a **single play** (`hosts: vulkan|rocm`,
`gather_facts: yes`, `become: yes`) that does everything in order by including
shared task files from `tasks/`:

1. `podman-models-dir.yml` — ensure the models dir exists + is user-owned
2. `hf-download-files.yml` — download weights (skips files already present)
3. `podman-remove-container.yml` → `podman run` → `podman-check-running.yml`
4. `podman-wait-health.yml` — sleep + poll `/health`
5. `podman-render-launch-artifacts.yml` — render the launch script to the
   target's `~/scripts/` and the opencode config to the controller's
   `rendered/opencode-configs/`

The render tasks use `delegate_to: localhost` + `become: no` **inline** — there
is no separate render play. (The old bootstrap/render split belonged to the
retired host-source-build tracks.)

### Tags

- Play: `[<track>-podman]` (e.g. `qwen36-35b-ud-q8-k-xl-mtp-podman`)
- Models dir + download: `[podman, model]`
- Container run + health: `[podman, deploy]`
- Render artifacts: `[podman, launch]`

Run one whole track with its play tag: `--tags <track>-podman`. The shared host
plays carry their own tags (`install-amdgpu`, `install-podman`, `install-hf-cli`,
`grub-ttm`, `limine-ttm`), so `--skip-tags install-amdgpu` skips base
provisioning on an already-built host.

## Per-track directories

The Podman tracks are self-contained (no `group_vars`); each defines its own
`_user_home` / `_models_dir` inline:

- **Vulkan llama.cpp tracks** (qwen36-35b, qwen38-27b-q38rocm, gemma)
  share `~/models`. Files are renamed on download via `dest_name` so two tracks
  never collide on a generic name like `mmproj-F16.gguf`.
- **halogen** uses a dedicated `~/halogen-models` (bind-mounted at `/models:ro`)
  because its `.hgn` checkpoint + overlay + tokenizer set is engine-specific and
  shouldn't mix with the GGUF pool.
- **ds4** uses `~/ds4` on both nodes (bind-mounted at the same path).

There is no shared `llama_common_*` var set and no per-track llama.cpp clone dir —
those belonged to the retired host-source-build tracks.

## Build conventions

Most tracks **pull** a prebuilt image (`--pull=newer`) and never build — this
includes the q38rocm 27B track (`ghcr.io/julianmb/q38rocm`). The remaining
built-from-source track (ornith15-ciru) builds via a
**Containerfile** in `single-node/containerfiles/`, driven by
`tasks/podman-build-image.yml` (skips the build if the tag already exists).
The build is pinned by a commit/build arg (e.g. `LLAMA_CPP_COMMIT=<sha>`)
passed as `_build_arg`.

- **Pull tracks** (qwen36-35b, gemma, halogen): no build step; the launch
  script re-pulls only if the registry tag is newer.
- **Build tracks**: `podman build -f containerfiles/<track>.Containerfile` with
  the pinned commit arg; the playbook checks `podman image exists` before
  running so a re-run is a no-op.

(There are no CMake / `*-build-deps.yml` conventions anymore — the retired
tracks that compiled llama.cpp directly on the host are gone.)

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
VAR_NAME="${VAR_NAME:-{{ var_prefix_value }}}"
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

### OpenCode config JSON format

All config templates follow the same structure (opencode config schema at
`https://opencode.ai/config.json`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "<track-tag>": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "<Model Name> (<Quant>, <Profile>)",
      "options": {
        "baseURL": "http://{{ <var>_host }}:{{ <var>_port }}/v1",
        "apiKey": "<track-tag>-local"
      },
      "models": {
        "<model-id>": {
          "name": "<Model Name> (<Quant>, ~<size> GB)",
          "reasoning": true,
          "limit": {
            "context": {{ <var>_ctx }},
            "output": 65536
          },
          "cost": { "input": 0, "output": 0, "cache_read": 0, "cache_write": 0 }
        }
      }
    }
  }
}
```

### OpenCode config for vision tracks

Multimodal tracks (image input) declare
`"modalities": { "input": ["text", "image"] }` on the model (text-only tracks
omit it), and must ship the llama.cpp vision projector next to the quant
(`--mmproj`) or the server answers text only — see
`gemma-4-26b-a4b-ud-q8-k-xl-podman.yml` + its launch script, which fetches
`mmproj-F16.gguf` and renames it to `gemma-4-26B-A4B-it-mmproj-F16.gguf`.

## Ansible gotchas

### become on local runs

Ubuntu 26.04's default `sudo-rs` reformats ansible's `-p` prompt, causing timeout. Always use:

```yaml
localhost ansible_connection=local ansible_user=jdella ansible_become_exe=/usr/bin/sudo.ws
```

### include_tasks for shared steps

Shared steps live in the topology's `tasks/` dir and are included with
`ansible.builtin.include_tasks` (not `import_tasks`) so they respect tags and
can be conditionally skipped:

```yaml
- name: Set up models directory
  ansible.builtin.include_tasks: tasks/podman-models-dir.yml
```

### git clone with PR refs

Only relevant if a track clones engine source directly (the current build tracks
build inside a Containerfile instead). For a PR-based clone:

```yaml
- name: Clone llama.cpp PR #NNNNN
  ansible.builtin.git:
    repo: "https://github.com/ggml-org/llama.cpp.git"
    dest: "{{ _engine_repo }}"
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
   the `active_profile` + profile-dict pattern (see `vllm-rccl-moe.yml`).

2. Create `ansible/single-node/<track_stem>-podman.yml` as a **single play**
   (`hosts: vulkan|rocm`, `become: yes`) that includes the shared
   `tasks/podman-*.yml` files, following the single-play pattern above.

3. Create templates under the topology dir:
   - `ansible/single-node/templates/scripts/<track_stem>-start.sh.j2`
   - `ansible/single-node/templates/opencode-configs/opencode-<track_stem>-podman.json.j2`

4. Add the host to its capability group (`vulkan` or `rocm`, under `aiservers`) in the
   track's `inventory/hosts`; mirror it in `hosts.example`. A host runs one model at a
   time, so there is no per-model group to add.

5. Add `import_playbook` to the topology's bootstrap (`ansible/single-node/bootstrap.yml`
   or `ansible/multi-node/bootstrap.yml`).

6. Update `README.md` layout tree and quick-start sections.

7. Put `tags: [<track_stem>-podman]` on the play and `[podman, <phase>]` on the
   tasks so `--tags <track_stem>-podman` runs the whole track.
