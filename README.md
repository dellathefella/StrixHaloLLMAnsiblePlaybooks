# ROCm / DS4-C-IQ2XXS + Qwen36-35B-UD-Q8-K-XL + Qwen35-397B-GPTQ-RCCL install — Ryzen AI Max (HP Z2 G1a)

Organized workspace for bootstrapping AMD ROCm inference on the Ryzen AI Max
"Strix Halo" APU, on **HP Z2 G1a** workstations (2.5Gbe NICs — no 10Gbps
requirement). Ubuntu/Debian only. Tracks organized by **deployment topology**
(single-node vs multi-node) with separate bootstrap orchestrators:

## Deployment Topology

### Single-Node Tracks (`ansible/single-node/`)
All llama.cpp tracks run locally on a single machine:
- **DS4-C-IQ2XXS** — DeepSeek V4 Flash via the `ds4.c` engine (ROCm-optimized). Default mode is single-node: IQ2XXS imatrix quant (~80.8 GB) at **126k context** on one 128 GB node.
- **Qwen36-35B-UD-Q8-K-XL** — Qwen3.6-35B-A3B (8-bit UD-Q8_K_XL, 38.5 GB) via llama.cpp ROCm/HIP.
- **Qwen38-27B-UD-Q4-K-XL** — Qwen3.8-27B (UD-Q8_K_XL, ~27 GB) via llama.cpp ROCm/HIP (KyaniteLabs Strix Halo profile).
- **Qwen38-Flash-Next-UD-IQ4-XS** — Qwen3.8-Flash-Next (125B/6B MoE, 3-part GGUF ~87 GB) via llama.cpp Vulkan.

### Multi-Node Tracks (`ansible/multi-node/`)
Cluster-based inference across multiple machines:
- **Qwen35-397B-GPTQ-RCCL** — Qwen3.5-397B-A10B-GPTQ-Int4 across two nodes via vLLM + Ray + RCCL.

## Quick Start

### Single-Node (recommended for this host)
```bash
# Full single-node bootstrap:
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/bootstrap.yml

# Run a single track:
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen36-35b-ud-q8-k-xl.yml

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
├── hf_token.txt                   HuggingFace token (gated model downloads)
├── reference/
│   ├── playbook.txt               AMD ds4 playbook (text extract)
│   └── notes.md                   pi local-server / DS4 config snippets
├── ansible/
│   ├── bootstrap.yml              ROOT: imports single-node/ and multi-node/ bootstraps
│   │
│   ├── single-node/               Single-node tracks (all run on localhost)
│   │   ├── bootstrap.yml          ORCHESTRATOR: single-node playbooks
│   │   ├── base.yml               base preflight, packages, toolchain, GRUB   [base]
│   │   ├── summary.yml            final per-host completion summary           [summary]
│   │   ├── ds4-c-iq2xxs.yml       DS4-C-IQ2XXS: single-node IQ2XXS default [ds4-c-iq2xxs]
│   │   ├── qwen36-35b-ud-q8-k-xl.yml  Qwen3.6-35B-A3B (llama.cpp ROCm/HIP) [qwen36-35b]
│   │   ├── qwen38-27b-ud-q8-k-xl.yml  Qwen3.8-27B (llama.cpp ROCm/HIP) [qwen38-27b]
│   │   ├── qwen38-flash-next-ud-iq4-xs.yml  Qwen3.8-Flash-Next (llama.cpp Vulkan) [qwen38-flash-next]
│   │   ├── inventory/
│   │   │   ├── hosts              single-node inventory (localhost)
│   │   │   └── group_vars/
│   │   │       └── all.yml        shared vars for single-node tracks
│   │   ├── templates/             Jinja templates (rendered by each track)
│   │   │   ├── ds4-c-iq2xxs-start.sh.j2          DS4-C-IQ2XXS launch template
│   │   │   ├── qwen36-35b-ud-q8-k-xl-start.sh.j2   Qwen3.6-35B-A3B launch
│   │   │   ├── qwen38-27b-ud-q8-k-xl-start.sh.j2   Qwen3.8-27B launch
│   │   │   ├── qwen38-flash-next-ud-iq4-xs-start.sh.j2   Qwen3.8-Flash-Next launch
│   │   │   ├── pi-ds4-c-iq2xxs.json.j2          pi agent config (DS4-C-IQ2XXS)
│   │   │   ├── pi-qwen36-35b-ud-q8-k-xl.json.j2   pi agent config (Qwen3.6-35B)
│   │   │   ├── pi-qwen38-27b-ud-q8-k-xl.json.j2   pi agent config (Qwen3.8-27B)
│   │   │   ├── pi-qwen38-flash-next-ud-iq4-xs.json.j2   pi agent config (Qwen3.8-Flash)
│   │   │   └── pi-ds4-c-iq2xxs.json.j2              pi agent config (DS4-C-IQ2XXS)
│   │   ├── tasks/                 shared task files
│   │   │   ├── rocm-build-deps.yml    ROCm runtime + dev packages
│   │   │   └── vulkan-build-deps.yml  Vulkan/RADV runtime + dev packages
│   │   └── rendered/              Rendered output (gitignored)
│   │       ├── scripts/           Rendered launch scripts
│   │       └── pi-configs/        Rendered pi agent configs
│   │
│   ├── multi-node/                Multi-node cluster tracks
│   │   ├── bootstrap.yml          ORCHESTRATOR: multi-node playbooks
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
│   │   ├── tasks/                 shared task files
│   │   │   ├── rocm-build-deps.yml    ROCm runtime + dev packages
│   │   │   └── vulkan-build-deps.yml  Vulkan/RADV runtime + dev packages
│   │   └── rendered/              Rendered output (gitignored)
│   │       ├── scripts/           Rendered launch scripts
│   │       └── pi-configs/        Rendered pi agent configs
│   │
│   ├── tasks/                     (legacy root tasks — not used, keep for reference)
│   │   ├── rocm-build-deps.yml
│   │   └── vulkan-build-deps.yml
│   ├── templates/                 (legacy root templates — not used, keep for reference)
│   └── inventory/                 (legacy root inventory — not used, keep for reference)
│       ├── hosts
│       └── hosts.example
│
├── scripts/                       Rendered launch scripts (from ansible/rendered/)
│   ├── ds4-setup.sh               DS4-C-IQ2XXS host bootstrap (DS4 itself only)
│   ├── install-pi.sh              local pi install (pi + plugins on this system)
│   └── ds4-c-iq2xxs-start.sh      rendered DS4-C-IQ2XXS launch
└── pi-configs/                    Rendered pi agent configs (from ansible/rendered/)
    ├── pi-ds4-c-iq2xxs.json
    └── pi-qwen36-35b-ud-q8-k-xl.json
```

## Track Details

### DS4-C-IQ2XXS
- **Engine**: `ds4.c` (Dwarf Star 4)
- **Model**: DeepSeek V4 Flash IQ2XXS imatrix quant (~80.8 GB)
- **Context**: 126k (single-node), 262k (multi-node)
- **Port**: 8000
- **Backend**: ROCm

### Qwen36-35B-UD-Q8-K-XL
- **Engine**: llama.cpp ROCm/HIP (independent clone in `~/llama-cpp-qwen36`)
- **Model**: Qwen3.6-35B-A3B UD-Q8_K_XL (~38.5 GB)
- **Context**: 262k (native ceiling)
- **Port**: 8081
- **Backend**: ROCm/HIP with MoE batching

### Qwen38-27B-UD-Q4-K-XL
- **Engine**: llama.cpp ROCm/HIP (independent clone in `~/llama-cpp-qwen38-27b`)
- **Model**: Qwen3.8-27B UD-Q8_K_XL (~27 GB)
- **Context**: 262k (native ceiling)
- **Port**: 8084
- **Backend**: ROCm/HIP + MTP speculation

### Qwen38-Flash-Next-UD-IQ4-XS
- **Engine**: llama.cpp Vulkan (PR #27742, independent clone in `~/llama-cpp-flash`)
- **Model**: Qwen3.8-Flash-Next UD-IQ4_XS (3-part GGUF ~87 GB)
- **Context**: 131k
- **Port**: 8085
- **Backend**: Vulkan/RADV (no ROCm kernels for this arch)

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
# Qwen3.6-35B-A3B (8-bit UD-Q8_K_XL, ~38.5 GB)
hf download unsloth/Qwen3.6-35B-A3B-GGUF Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf \
  --local-dir ~/.local/share/llama-models

# DS4-C-IQ2XXS single-node IQ2XXS (~80.8 GB) into ~/ds4-c-iq2xxs
hf download antirez/deepseek-v4-gguf DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf \
  --local-dir ~/ds4-c-iq2xxs
```

Verify integrity after download (HF publishes sha256, not md5):
```bash
sha256sum <file>.gguf   # compare against the repo's file listing
```

## Launch Scripts

After the bootstrap + REBOOT (if GRUB changed), the rendered launch scripts
are in `ansible/rendered/scripts/`. Copy them to each node and run:

### Single-Node Launch Example
```bash
# Qwen3.6-35B-A3B
./ansible/rendered/scripts/qwen36-35b-ud-q8-k-xl-start.sh

# DS4-C-IQ2XXS (single-node mode)
./ansible/rendered/scripts/ds4-c-iq2xxs-start.sh
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
- `pi-ds4-c-iq2xxs.json` — `ds4-c-iq2xxs` provider → `http://127.0.0.1:8000/v1`, model `deepseek-v4-flash` (single-node IQ2XXS).
- `pi-qwen36-35b-ud-q8-k-xl.json` — `qwen36-35b-ud-q8-k-xl` provider → `http://127.0.0.1:8081/v1`, model `qwen3.6-35b-ud-q8-k-xl`.
- `pi-qwen38-27b-ud-q8-k-xl.json` — `qwen38-27b-ud-q8-k-xl` provider → `http://127.0.0.1:8084/v1`, model `qwen3.8-27b-ud-q4-k-xl`.
- `pi-qwen38-flash-next-ud-iq4-xs.json` — `qwen38-flash-next-ud-iq4-xs` provider → `http://127.0.0.1:8085/v1`, model `qwen3.8-flash-next-ud-iq4-xs`.
- `pi-qwen35-397b-gptq-rccl.json` — `qwen35-397b-gptq-rccl` provider → `http://<head_ip>:7000/v1`, model `Qwen3.5-397B-A10B-GPTQ-Int4`.

Merge the provider block(s) into `~/.pi/agent/models.json` (pi reloads it when
you open `/model`; no restart needed). `scripts/install-pi.sh` installs pi + the pi
plugins present on this system (pi-web-access, rpiv-ask-user-question,
pi-background-tasks, pi-permission-system, pi-ds4) and merges
the pi provider configs.

## Config Variables (inventory / env)

### Single-Node Tracks
- DS4-C-IQ2XXS: `ds4_c_iq2xxs_mode` (single default), `ds4_c_iq2xxs_ctx_single` (126000), `ds4_c_iq2xxs_port` (8000), `ds4_c_iq2xxs_host` (127.0.0.1)
- Qwen36-35B: `qwen36_35b_ud_q8_k_xl_ctx` (262144), `qwen36_35b_ud_q8_k_xl_port` (8081), `qwen36_35b_ud_q8_k_xl_host/device/threads`
- Qwen38-27B: `qwen38_27b_ud_q8_k_xl_ctx` (262144), `qwen38_27b_ud_q8_k_xl_port` (8084), `qwen38_27b_ud_q8_k_xl_host/device/threads`
- Qwen38-Flash-Next: `qwen38_flash_next_ud_iq4_xs_ctx` (131072), `qwen38_flash_next_ud_iq4_xs_port` (8085), `qwen38_flash_next_ud_iq4_xs_host/device`

### Multi-Node Tracks
- Qwen35-397B-GPTQ-RCCL: `qwen35_397b_gptq_rccl_head_ip`, `qwen35_397b_gptq_rccl_worker_ip`, `qwen35_397b_gptq_rccl_max_model_len` (65536), `qwen35_397b_gptq_rccl_tp_size` (2), `qwen35_397b_gptq_rccl_port` (7000)

### Scripts
- `DS4_C_IQ2XXS_ROLE` (single|coordinator|worker), `DS4_C_IQ2XXS_USE_MTP`, `DS4_C_IQ2XXS_CTX_SINGLE`
- `QWEN36_35B_UD_Q8_K_XL_*` (BIN/MODEL/CTX/PORT/HOST/DEVICE/THREADS)
- `QWEN38_27B_UD_Q8_K_XL_*` (BIN/MODEL/CTX/PORT/HOST/DEVICE/THREADS)
- `QWEN38_FLASH_NEXT_UD_IQ4_XS_*` (BIN/MODEL/CTX/PORT/HOST/DEVICE)
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
package (7.1.0). ROCm is needed for DS4-C-IQ2XXS, qwen36-35b, and qwen38-27b tracks. Vulkan is needed for the qwen38-flash-next track.

**Architecture:** the ansible playbook is **bootstrap-only**. It installs
packages, sets GRUB, creates containers/toolboxes, builds llama.cpp, and
downloads model weights. It NEVER launches servers.
