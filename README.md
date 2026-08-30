# StrixHalo LLM Ansible Playbooks — Ryzen AI Max (HP Z2 G1a)

Organized workspace for bootstrapping AMD ROCm / Vulkan LLM inference on the
Ryzen AI Max "Strix Halo" APU, on **HP Z2 G1a** workstations (2.5Gbe NICs —
no 10Gbps requirement). Ubuntu/Debian only. Tracks organized by **deployment
topology** (single-node vs multi-node) with separate bootstrap orchestrators:

## Deployment Topology

### Single-Node Tracks (`ansible/single-node/`)
All llama.cpp tracks run locally on a single machine:

- **Qwen36-35B-A3B (UD-Q8_K_XL)** — Qwen3.6-35B-A3B (8-bit UD-Q8_K_XL, ~38.5 GB)
  via Podman Vulkan container (`ghcr.io/ggml-org/llama.cpp:server-vulkan-b10644`).
  Port 8080, ctx 262144.

- **Qwen38-27B (UD-Q4_K_XL)** — Qwen3.8-27B (UD-Q4_K_XL) via Podman Vulkan
  container with **MTP speculative decoding** via the repo drafter
  `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` (`draft-mtp`, draft n-max 3, f16 KV cache,
  batch 2048 / ubatch 512, flash-attn on, mmap loading, single slot).
  Port 8084, ctx 262144.

- **Qwen38-Flash-Next (UD-Q2_K_XL)** — Qwen3.8-Flash-Next (UD-Q2_K_XL, ~89 GB) via Podman
  Vulkan container. Port 8080, ctx 262144.

- **Qwen38-Flash-Next IQ4 (UD-IQ4_XS)** — Qwen3.8-Flash-Next 125B-A6B (UD-IQ4_XS,
  3 shards, ~87 GiB on disk) via Podman Vulkan container. Second Flash-Next
  profile: ctx 131072 (~91 GB resident), `--load-mode none`, KV cache f16
  (quantized KV asserts on the `qwen4exp` arch), `--jinja`, `--reasoning on`,
  single slot, sampler defaults temp 1.0 / top-p 0.95 / top-k 20 / min-p 0.0.
  Port 8080. Measured on a 128 GB Strix Halo: ~23 t/s decode, ~390 t/s pp512.

- **Gemma 4 26B A4B (UD-Q8_K_XL)** — Gemma 4 26B A4B it (UD-Q8_K_XL, ~27.6 GB) via
  Podman Vulkan container, with **image recognition**: the `mmproj-F16.gguf` vision
  projector is downloaded and passed as `--mmproj`, so `/v1/chat/completions`
  accepts `image_url` content parts. Port 8080, ctx 262144 — same profile as
  Qwen36-35B-A3B.

### Multi-Node Tracks (`ansible/multi-node/`)
Cluster-based inference across multiple machines:

- **Qwen35-397B-GPTQ-RCCL** — Qwen3.5-397B-A10B-GPTQ-Int4 across two nodes via
  vLLM + Ray + RCCL.

### Shared Setup Playbooks (`ansible/shared/`)
Host-level setup shared by both tracks (imported by each track's bootstrap):

- `install-amdgpu.yml` — Ubuntu base: apt upgrade + ROCm via amdgpu-install (Ubuntu-gated)
- `install-podman.yml` — cross-distro Podman installation (Fedora/Debian/Arch)
- `install-hf-cli.yml` — HuggingFace CLI installation
- `set-grub-ttm.yml` — GRUB kernel args: TTM, IOMMU, GTT size
- `set-limine-ttm.yml` — Limine bootloader TTM kernel args (Limine hosts only)

## Quick Start

### Single-Node (recommended for this host)
```bash
# Full single-node bootstrap:
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/bootstrap.yml

# Run a single Podman track:
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen36-35b-ud-q8-k-xl-podman.yml
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen38-27b-ud-q4-k-xl-podman.yml
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen38-flash-next-ud-q2-k-xl-podman.yml
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen38-flash-next-ud-iq4-xs-podman.yml
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/gemma-4-26b-a4b-ud-q8-k-xl-podman.yml

# Skip base (already provisioned):
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/bootstrap.yml --skip-tags install-amdgpu
```

### Multi-Node (cluster)
```bash
# Full multi-node bootstrap:
ansible-playbook -i ansible/multi-node/inventory/hosts ansible/multi-node/bootstrap.yml
```

### Root Bootstrap (imports both)
```bash
# Convenience wrapper (not recommended for production use):
ansible-playbook -i ansible/inventory/hosts ansible/bootstrap.yml
```

## Layout

```
├── README.md                      this file
├── SYSTEM.md                      hardware spec & design rules
├── reference/
│   ├── cachyos-notes.md           CachyOS installation notes
│   └── playbook.txt               AMD ds4 playbook (text extract)
├── ansible/
│   ├── bootstrap.yml              ROOT: imports single-node/ and multi-node/ bootstraps
│   │
│   ├── shared/                    Shared setup playbooks (imported by both tracks)
│   │   ├── install-amdgpu.yml     Ubuntu base: apt upgrade + ROCm (Ubuntu-gated)
│   │   ├── install-podman.yml     Podman installation (Fedora/Debian/Arch)
│   │   ├── install-hf-cli.yml     HuggingFace CLI installation
│   │   ├── set-grub-ttm.yml       GRUB TTM kernel args
│   │   └── set-limine-ttm.yml     Limine bootloader TTM settings
│   │
│   ├── single-node/               Single-node tracks (all run on localhost)
│   │   ├── bootstrap.yml          ORCHESTRATOR: single-node playbooks
│   │   ├── summary.yml            final per-host completion summary           [summary]
│   │   ├── qwen36-35b-ud-q8-k-xl-podman.yml  Qwen3.6-35B-A3B (Podman Vulkan)
│   │   ├── qwen38-27b-ud-q8-k-xl-podman.yml  Qwen3.8-27B (Podman Vulkan + MTP)
│   │   ├── qwen38-flash-next-ud-q2-k-xl-podman.yml  Qwen3.8-Flash-Next (Podman Vulkan)
│   │   ├── qwen38-flash-next-ud-iq4-xs-podman.yml  Qwen3.8-Flash-Next IQ4 (Podman Vulkan)
│   │   ├── gemma-4-26b-a4b-ud-q8-k-xl-podman.yml  Gemma 4 26B A4B (Podman Vulkan + vision)
│   │   ├── inventory/
│   │   │   ├── hosts              single-node inventory (localhost)
│   │   │   └── group_vars/
│   │   │       └── all.yml        shared vars for single-node tracks
│   │   ├── templates/             Jinja templates (rendered by each track)
│   │   │   ├── scripts/           Launch script templates
│   │   │   │   ├── qwen36-35b-vulkan-start.sh.j2   Qwen3.6-35B Vulkan launch
│   │   │   │   ├── qwen38-27b-vulkan-start.sh.j2   Qwen3.8-27B Vulkan launch (with MTP)
│   │   │   │   ├── qwen38-flash-next-vulkan-start.sh.j2   Flash-Next Q2 launch (3 shards)
│   │   │   │   ├── qwen38-flash-next-iq4-xs-vulkan-start.sh.j2   Flash-Next IQ4 launch (3 shards)
│   │   │   │   └── gemma-4-26b-a4b-vulkan-start.sh.j2   Gemma 4 Vulkan launch (model + mmproj)
│   │   │   ├── pi-configs/        PI agent JSON config templates
│   │   │   │   ├── pi-qwen36-35b-ud-q8-k-xl-podman.json.j2
│   │   │   │   ├── pi-qwen38-27b-ud-q8-k-xl-podman.json.j2
│   │   │   │   ├── pi-qwen38-flash-next-ud-q2-k-xl-podman.json.j2
│   │   │   │   ├── pi-qwen38-flash-next-ud-iq4-xs-podman.json.j2
│   │   │   │   └── pi-gemma-4-26b-a4b-ud-q8-k-xl-podman.json.j2
│   │   └── rendered/              Rendered output (gitignored)
│   │       ├── scripts/           Rendered launch scripts
│   │       └── pi-configs/        Rendered pi agent configs
│   │
│   ├── multi-node/                Multi-node cluster tracks
│   │   ├── bootstrap.yml          ORCHESTRATOR: shared/ setup + multi-node playbooks
│   │   ├── summary.yml            final per-host completion summary           [summary]
│   │   ├── qwen35-397b-gptq-rccl.yml  Qwen3.5-397B GPTQ RCCL cluster [qwen35-397b]
│   │   ├── inventory/
│   │   │   ├── hosts              multi-node inventory (localhost + workers)
│   │   │   └── group_vars/
│   │   │       └── all.yml        shared vars for multi-node tracks
│   │   ├── templates/             Jinja templates
│   │   │   ├── qwen35-397b-gptq-rccl-start.sh.j2   Qwen3.5-397B RCCL launch
│   │   │   └── pi-qwen35-397b-gptq-rccl.json.j2   pi agent config (Qwen3.5-397B)
│   │   └── rendered/              Rendered output (gitignored)
│   │       ├── scripts/           Rendered launch scripts
│   │       └── pi-configs/        Rendered pi agent configs
│   │
│   └── secrets/                   Secret files (gitignored)
│       └── hf_token.txt           HuggingFace token for gated model downloads
```

## Track Details

### Qwen36-35B-A3B (UD-Q8_K_XL) — Podman Vulkan
- **Container**: `ghcr.io/ggml-org/llama.cpp:server-vulkan-b10644`
- **Model**: Qwen3.6-35B-A3B UD-Q8_K_XL (~38.5 GB)
- **Context**: 262k (native ceiling)
- **Port**: 8080
- **Backend**: Vulkan/RADV

### Qwen38-27B (UD-Q4_K_XL) — Podman Vulkan + MTP
- **Container**: `ghcr.io/ggml-org/llama.cpp:server-vulkan-b10666`
- **Model**: Qwen3.8-27B UD-Q4_K_XL (`Qwen3.8-27B-UD-Q4_K_XL.gguf`)
- **Drafter**: `MTP/mtp-Qwen3.8-27B-Q4_0.gguf`, passed as `--model-draft`
  (`draft-mtp` is only auto-discovered with `-hf`, never from a local `--model`)
- **Context**: 262144 (native ceiling), `--parallel 1` (single slot)
- **Port**: 8084
- **Backend**: Vulkan/RADV
- **Speculation**: `--spec-type draft-mtp --spec-draft-n-max 3`, KV cache f16 (K+V)
- **Batching / loading**: `-b 2048`, `-ub 512`, `-fa on`, `--load-mode mmap`, `-ngl 999`

### Qwen38-Flash-Next (UD-Q2_K_XL) — Podman Vulkan
- **Container**: `ghcr.io/ggml-org/llama.cpp:server-vulkan-b10666`
- **Model**: Qwen3.8-Flash-Next 125B-A6B UD-Q2_K_XL (~89 GB), 3 shards under
  `UD-Q2_K_XL/`, renamed locally to `Qwen3.8-Flash-Next-UD-Q2_K_XL/`
- **Context**: 262144 (native ceiling)
- **Port**: 8080
- **Backend**: Vulkan/RADV (`qwen4exp` arch)

### Qwen38-Flash-Next IQ4 (UD-IQ4_XS) — Podman Vulkan
- **Container**: `ghcr.io/ggml-org/llama.cpp:server-vulkan-b10666`
- **Model**: Qwen3.8-Flash-Next 125B-A6B UD-IQ4_XS (~87 GiB on disk), 3 shards
  under `UD-IQ4_XS/`, renamed locally to `Qwen3.8-Flash-Next-UD-IQ4_XS/`.
  llama.cpp loads the set from part 1, so the shard directory is mounted.
- **Context**: 131072 (~91 GB resident — the native 262144 does not fit
  alongside an f16 KV cache in 128 GB)
- **Port**: 8080
- **Backend**: Vulkan/RADV — `qwen4exp` is Gated DeltaNet + sparse attention
  (QSA), 125B total / 6B active plus a 51B n-gram embedding table
- **Loading**: `--load-mode none` (no mmap); KV cache stays **f16** (`-ctk/-ctv`)
  because quantized KV asserts and dies on this arch
- **Sampling**: `--jinja`, `--reasoning on`, defaults temp 1.0 / top-p 0.95 /
  top-k 20 / min-p 0.0, `--parallel 1` (single slot), `-ngl 999`, `-fa on`
- **Engine**: `qwen4exp` landed in llama.cpp via PR #27742 (merged 2026-08-27)
  together with the `LLM_ARCH_QWEN4EXP` entry in `graph_max_nodes()`; the pinned
  b10666 image already contains both, so no PR-branch build or local patch.
- **Measured** on a 128 GB Strix Halo (llama-bench, fa on): pp512 ~390 t/s,
  pp4096 ~357 t/s, tg128 ~23 t/s.

### Gemma 4 26B A4B (UD-Q8_K_XL) — Podman Vulkan + image input
- **Container**: `ghcr.io/ggml-org/llama.cpp:server-vulkan-b10666`
- **Model**: Gemma 4 26B A4B it UD-Q8_K_XL (~27.6 GB), single GGUF at the repo root
- **Vision projector**: `mmproj-F16.gguf` (~1.19 GB) → stored as
  `gemma-4-26B-A4B-it-mmproj-F16.gguf`, passed as `--mmproj` (llama.cpp
  `libmtmd`; the projector is GPU-offloaded by default)
- **Context**: 262144 (native ceiling)
- **Port**: 8080 (shared with the other Podman tracks — one server at a time)
- **Backend**: Vulkan/RADV
- **Note**: no MTP speculation wired up, although `MTP/mtp-gemma-4-26B-A4B-it-*.gguf`
  exists in the repo and could follow the qwen38-27b pattern later.

### Qwen35-397B-GPTQ-RCCL (Multi-Node)
- **Engine**: vLLM + RCCL
- **Model**: Qwen3.5-397B-A10B-GPTQ-Int4
- **Context**: 65536 (cluster-wide)
- **Port**: 7000 (head node)
- **Backend**: ROCm (tensor parallel across nodes)

## Model Downloads (hf CLI)

The bootstrap downloads GGUF weights via **hf** (the Hugging Face CLI), which
handles caching, resumption, and authentication natively. The llama track
**skips a download when its GGUF is already present** (`stat` check + `when:`
guard), so re-running the play or `--tags model` won't re-fetch an existing
model. The same commands work manually if you want to re-fetch a model outside
ansible:

```bash
# Qwen3.6-35B-A3B (UD-Q8_K_XL, ~38.5 GB)
hf download unsloth/Qwen3.6-35B-A3B-GGUF Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf \
  --local-dir ~/models

# Qwen3.8-27B (UD-Q4_K_XL) + MTP drafter
hf download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-Q4_K_XL.gguf \
  --local-dir ~/models
hf download unsloth/Qwen3.8-27B-GGUF MTP/mtp-Qwen3.8-27B-Q4_0.gguf \
  --local-dir ~/models    # lands as ~/models/MTP/mtp-Qwen3.8-27B-Q4_0.gguf

# Gemma 4 26B A4B it (UD-Q8_K_XL, ~27.6 GB) + vision projector
hf download unsloth/gemma-4-26B-A4B-it-GGUF gemma-4-26B-A4B-it-UD-Q8_K_XL.gguf \
  --local-dir ~/models
hf download unsloth/gemma-4-26B-A4B-it-GGUF mmproj-F16.gguf \
  --local-dir ~/models       # lands as ~/models/mmproj-F16.gguf,
                             # renamed to gemma-4-26B-A4B-it-mmproj-F16.gguf

# Qwen3.8-Flash-Next (UD-IQ4_XS, 3 shards, ~87 GiB)
hf download unsloth/Qwen3.8-Flash-Next-GGUF UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf --local-dir ~/models
hf download unsloth/Qwen3.8-Flash-Next-GGUF UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00002-of-00003.gguf --local-dir ~/models
hf download unsloth/Qwen3.8-Flash-Next-GGUF UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00003-of-00003.gguf --local-dir ~/models
                             # land in ~/models/UD-IQ4_XS/, renamed by the
                             # playbook to ~/models/Qwen3.8-Flash-Next-UD-IQ4_XS/
```

## Launch Scripts

After the bootstrap, the rendered launch scripts are in `~/scripts/` on the
target host. The bootstrap also drops PI agent configs into
`ansible/rendered/pi-configs/` (rendered on the controller).

### Single-Node Launch Example
```bash
# Qwen3.6-35B-A3B (Podman Vulkan)
~/scripts/qwen36-35b-vulkan-start.sh

# Qwen3.8-27B (Podman Vulkan + MTP)
~/scripts/qwen38-27b-vulkan-start.sh

# Qwen3.8-Flash-Next (UD-Q2_K_XL, Podman Vulkan)
~/scripts/qwen38-flash-next-vulkan-start.sh

# Qwen3.8-Flash-Next IQ4 (UD-IQ4_XS, Podman Vulkan)
~/scripts/qwen38-flash-next-iq4-xs-vulkan-start.sh

# Gemma 4 26B A4B (Podman Vulkan, image input)
~/scripts/gemma-4-26b-a4b-vulkan-start.sh
```

### Multi-Node Launch Example (Qwen3.5-397B)
```bash
# Machine 1 (head — Ray head + vLLM server):
QWEN35_397B_GPTQ_RCCL_ROLE=head   ./ansible/rendered/scripts/qwen35-397b-gptq-rccl-start.sh
# Machine 2 (worker — joins Ray):
QWEN35_397B_GPTQ_RCCL_ROLE=worker ./ansible/rendered/scripts/qwen35-397b-gptq-rccl-start.sh
```

## Pi Agent Config

The bootstrap drops pi agent configs into `ansible/rendered/pi-configs/`:

- **Podman tracks:**
  - `pi-qwen36-35b-ud-q8-k-xl-podman.json` — provider `qwen36-35b-ud-q8-k-xl` → `http://<node_ip>:8080/v1`
  - `pi-qwen38-27b-ud-q4-k-xl-podman.json` — provider `qwen38-27b-ud-q4-k-xl` → `http://<node_ip>:8084/v1`
  - `pi-qwen38-flash-next-ud-q2-k-xl-podman.json` — provider `qwen38-flash-next-ud-q2-k-xl` → `http://<node_ip>:8080/v1`
  - `pi-qwen38-flash-next-ud-iq4-xs-podman.json` — provider `qwen38-flash-next-ud-iq4-xs` → `http://<node_ip>:8080/v1`
  - `pi-gemma-4-26b-a4b-ud-q8-k-xl-podman.json` — provider `gemma-4-26b-a4b-ud-q8-k-xl` → `http://<node_ip>:8080/v1`

- `pi-qwen35-397b-gptq-rccl.json` — `qwen35-397b-gptq-rccl` provider → `http://<head_ip>:7000/v1`

Merge the provider block(s) into `~/.pi/agent/models.json` (pi reloads it when
you open `/model`; no restart needed).

## Config Variables (inventory / env)

### Single-Node Tracks
(All single-node playbooks are self-contained with inline vars — no group_vars needed.)

### Multi-Node Tracks
- Qwen35-397B-GPTQ-RCCL: `qwen35_397b_gptq_rccl_head_ip`, `qwen35_397b_gptq_rccl_worker_ip`, `qwen35_397b_gptq_rccl_max_model_len` (65536), `qwen35_397b_gptq_rccl_tp_size` (2), `qwen35_397b_gptq_rccl_port` (7000)

### Scripts
- `QWEN36_35B_VULKAN_*` (CONTAINER/PORT/MODEL/IMAGE/CTX/BATCH/GPU_LAYERS)
- `QWEN38_27B_VULKAN_*` (CONTAINER/PORT/MODEL/DRAFT/IMAGE/CTX/PARALLEL/BATCH/UBATCH/GPU_LAYERS/CACHE_K/CACHE_V/FLASH_ATTN/LOAD_MODE/SPEC_TYPE/SPEC_DRAFT_N_MAX)
- `QWEN38_FLASH_NEXT_VULKAN_*` (CONTAINER/PORT/MODEL/IMAGE/CTX/BATCH/GPU_LAYERS)
- `QWEN38_FLASH_NEXT_IQ4XS_VULKAN_*` (CONTAINER/PORT/MODEL/SHARDS/MODEL_DIR/IMAGE/CTX/PARALLEL/BATCH/UBATCH/GPU_LAYERS/CACHE_K/CACHE_V/FLASH_ATTN/LOAD_MODE/REASONING/TEMP/TOP_P/TOP_K/MIN_P)
- `GEMMA4_26B_VULKAN_*` (CONTAINER/PORT/MODEL/MMPROJ/IMAGE/CTX/BATCH/GPU_LAYERS)
- `QWEN35_397B_GPTQ_RCCL_ROLE` (head|worker)

## Strix Halo Optimization Notes

The launch profiles are tuned from the Strix Halo benchmarking thread
(`community.frame.work/t/72521`, user lhl — Linux 6.15.5+, TheRock ROCm
nightlies, latest llama.cpp from source):

- **ROCm/HIP dominates prompt processing** on gfx1151 — 4.7× faster and 65%
  less energy than Vulkan. We build llama.cpp **ROCm-only** (HIP graphs
  enabled).
- **MoE models need 2^n batching** — `batch=256` for qwen36-35b-ud-q8-k-xl (38.5 GB, fits KV cache).
- **`--flash-attn on`** and **`--no-mmap`** (weights fully in the unified
  128 GB shared pool).
- **`qwen4exp` (Qwen3.8-Flash-Next) must keep an f16 KV cache** — quantized KV
  asserts and dies on that arch. The UD-IQ4_XS profile therefore pins
  `-ctk/-ctv f16`, `--load-mode none` and ctx 131072 (~91 GB resident); the
  native 262144 does not fit next to the weights in 128 GB.
- **Token generation is memory-bandwidth bound** (~215 GB/s). Qwen3.6 ~3B active
  ≈ 3 GB/token ≈ 65-70 t/s at 8-bit UD-Q8_K_XL.

**Network note:** host NICs are 2.5Gbe (HP Z2 G1a), below the guide's 10Gbps;
tensor-parallel KV exchange is the bottleneck. The playbook warns on this but
treats 2.5Gbe as acceptable — there is no 10Gbps requirement.

**TTM:** the shared-memory pool is configured by the GRUB kernel args
(`ttm.pages_limit=32505856 ttm.page_pool_size=32505856` ⇒ ~124GB). **No
`amd-ttm --set` is used** anywhere in the ansible — set BIOS UMA VRAM to
Auto/minimum, append the GRUB args, reboot.

**ROCm version:** the shared `install-amdgpu.yml` track installs ROCm via
AMD's `repo.radeon.com` `amdgpu-install` deb (currently 7.2.1, noble) with
`--usecase=rocm --no-dkms` — *not* the Ubuntu `rocm` package (7.1.0). ROCm is
needed for the qwen36-35b track. Vulkan is needed for the qwen38-27b Podman track.

**Podman tracks:** The new `*-podman.yml` playbooks are **self-contained** — all
vars are defined inline (no dependency on `group_vars/all.yml`), they skip the
local llama.cpp build step, and use the official `ghcr.io/ggml-org/llama.cpp:server-vulkan-b10644`
Vulkan container instead. MTP speculation args are baked into both the container
`run` command and the rendered launch script.

**Architecture:** the ansible playbook is **bootstrap-only**. It installs
packages, sets GRUB, creates containers/toolboxes, builds llama.cpp, and
downloads model weights. It NEVER launches servers.
