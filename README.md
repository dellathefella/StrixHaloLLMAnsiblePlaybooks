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

- **Qwen38-27B (UD-Q8_K_XL)** — Qwen3.8-27B (UD-Q8_K_XL, ~27 GB) via Podman
  Vulkan container with **KyaniteLabs Strix Halo MTP speculation profile**
  (`draft-mtp,ngram-mod`, n-max 12, n-min 24, q4_0 KV cache). Port 8084, ctx 262144.

### Multi-Node Tracks (`ansible/multi-node/`)
Cluster-based inference across multiple machines:

- **Qwen35-397B-GPTQ-RCCL** — Qwen3.5-397B-A10B-GPTQ-Int4 across two nodes via
  vLLM + Ray + RCCL.

### Shared Setup Playbooks (`ansible/shared/`)
Host-level setup shared by both tracks (imported by each track's bootstrap):

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
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen38-27b-ud-q8-k-xl-podman.yml

# Skip base (already provisioned):
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/bootstrap.yml --skip-tags base
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
│   │   ├── install-podman.yml     Podman installation (Fedora/Debian/Arch)
│   │   ├── install-hf-cli.yml     HuggingFace CLI installation
│   │   ├── set-grub-ttm.yml       GRUB TTM kernel args
│   │   └── set-limine-ttm.yml     Limine bootloader TTM settings
│   │
│   ├── single-node/               Single-node tracks (all run on localhost)
│   │   ├── bootstrap.yml          ORCHESTRATOR: single-node playbooks
│   │   ├── base.yml               base preflight, packages, toolchain, GRUB   [base]
│   │   ├── summary.yml            final per-host completion summary           [summary]
│   │   ├── qwen36-35b-ud-q8-k-xl-podman.yml  Qwen3.6-35B-A3B (Podman Vulkan)
│   │   ├── qwen38-27b-ud-q8-k-xl-podman.yml  Qwen3.8-27B (Podman Vulkan + MTP)
│   │   ├── inventory/
│   │   │   ├── hosts              single-node inventory (localhost)
│   │   │   └── group_vars/
│   │   │       └── all.yml        shared vars for single-node tracks
│   │   ├── templates/             Jinja templates (rendered by each track)
│   │   │   ├── scripts/           Launch script templates
│   │   │   │   ├── qwen36-35b-vulkan-start.sh.j2   Qwen3.6-35B Vulkan launch
│   │   │   │   └── qwen38-27b-vulkan-start.sh.j2   Qwen3.8-27B Vulkan launch (with MTP)
│   │   │   ├── pi-configs/        PI agent JSON config templates
│   │   │   │   ├── pi-qwen36-35b-ud-q8-k-xl-podman.json.j2
│   │   │   │   └── pi-qwen38-27b-ud-q8-k-xl-podman.json.j2
│   │   └── rendered/              Rendered output (gitignored)
│   │       ├── scripts/           Rendered launch scripts
│   │       └── pi-configs/        Rendered pi agent configs
│   │
│   ├── multi-node/                Multi-node cluster tracks
│   │   ├── bootstrap.yml          ORCHESTRATOR: shared/ setup + multi-node playbooks
│   │   ├── base.yml               base preflight, packages, toolchain, GRUB   [base]
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

### DS4-C-IQ2XXS
- **Engine**: `ds4.c` (Dwarf Star 4)
- **Model**: DeepSeek V4 Flash IQ2XXS imatrix quant (~80.8 GB)
- **Context**: 126k (single-node), 262k (multi-node)
- **Port**: 8000
- **Backend**: ROCm

### Qwen36-35B-A3B (UD-Q8_K_XL) — Podman Vulkan
- **Container**: `ghcr.io/ggml-org/llama.cpp:server-vulkan-b10644`
- **Model**: Qwen3.6-35B-A3B UD-Q8_K_XL (~38.5 GB)
- **Context**: 262k (native ceiling)
- **Port**: 8080
- **Backend**: Vulkan/RADV

### Qwen38-27B (UD-Q8_K_XL) — Podman Vulkan + MTP
- **Container**: `ghcr.io/ggml-org/llama.cpp:server-vulkan-b10644`
- **Model**: Qwen3.8-27B UD-Q8_K_XL (~27 GB)
- **Context**: 262k (native ceiling)
- **Port**: 8084
- **Backend**: Vulkan/RADV + KyaniteLabs MTP speculation
- **MTP Profile**: `draft-mtp,ngram-mod`, n-max 12, n-min 24, q4_0 KV cache

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

# Qwen3.8-27B (UD-Q8_K_XL, ~27 GB)
hf download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-Q8_K_XL-unsloth.gguf \
  --local-dir ~/models
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
  - `pi-qwen38-27b-ud-q8-k-xl-podman.json` — provider `qwen38-27b-ud-q8-k-xl` → `http://<node_ip>:8084/v1`

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
- `QWEN38_27B_VULKAN_*` (CONTAINER/PORT/MODEL/IMAGE/CTX/BATCH/GPU_LAYERS/CACHE_K/CACHE_V/SPEC_TYPE/SPEC_N_MAX/SPEC_N_MIN)
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
- **Token generation is memory-bandwidth bound** (~215 GB/s). Qwen3.6 ~3B active
  ≈ 3 GB/token ≈ 65-70 t/s at 8-bit UD-Q8_K_XL.

**Network note:** host NICs are 2.5Gbe (HP Z2 G1a), below the guide's 10Gbps;
tensor-parallel KV exchange is the bottleneck. The playbook warns on this but
treats 2.5Gbe as acceptable — there is no 10Gbps requirement.

**TTM:** the shared-memory pool is configured by the GRUB kernel args
(`ttm.pages_limit=32505856 ttm.page_pool_size=32505856` ⇒ ~124GB). **No
`amd-ttm --set` is used** anywhere in the ansible — set BIOS UMA VRAM to
Auto/minimum, append the GRUB args, reboot.

**ROCm version:** PLAY 1 installs **ROCm 7.2.4** via AMD's `repo.radeon.com`
(noble packages, used on this resolute/26.04 host) — *not* the Ubuntu `rocm`
package (7.1.0). ROCm is needed for DS4-C-IQ2XXS and qwen36-35b tracks. Vulkan is needed for the qwen38-27b Podman track.

**Podman tracks:** The new `*-podman.yml` playbooks are **self-contained** — all
vars are defined inline (no dependency on `group_vars/all.yml`), they skip the
local llama.cpp build step, and use the official `ghcr.io/ggml-org/llama.cpp:server-vulkan-b10644`
Vulkan container instead. MTP speculation args are baked into both the container
`run` command and the rendered launch script.

**Architecture:** the ansible playbook is **bootstrap-only**. It installs
packages, sets GRUB, creates containers/toolboxes, builds llama.cpp, and
downloads model weights. It NEVER launches servers.