# StrixHalo LLM Ansible Playbooks — Ryzen AI Max (HP Z2 G1a)

Organized workspace for bootstrapping AMD ROCm / Vulkan LLM inference on the
Ryzen AI Max "Strix Halo" APU, on **HP Z2 G1a** workstations (2.5Gbe NICs —
no 10Gbps requirement; optional TB4 node-to-node link, see below).
CachyOS (Arch-based) first, Ubuntu 26.04 second. Tracks organized by **deployment
topology** (single-node vs multi-node) with separate bootstrap orchestrators:

## Deployment Topology

### Single-Node Tracks (`ansible/single-node/`)
All llama.cpp tracks run locally on a single machine:

- **Qwen36-35B-A3B (UD-Q8_K_XL)** — Qwen3.6-35B-A3B (8-bit UD-Q8_K_XL, ~38.5 GB)
  via Podman Vulkan container (`ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan`).
  Port 8080, ctx 262144.

- **Qwen38-27B (UD-Q4_K_XL)** — Qwen3.8-27B (UD-Q4_K_XL) via Podman Vulkan
  container with **MTP speculative decoding** via the repo drafter
  `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` (`draft-mtp`, draft n-max 3, f16 KV cache,
  batch 2048 / ubatch 512, flash-attn on, mmap loading, single slot).
  Port 8080, ctx 262144.

- **Qwen38-27B (ROCmFP4_FAST, ROCmFPX engine)** — Qwen3.8-27B (ROCmFP4_FAST,
  ~13.5 GB) on the custom `julianmb/q38rocm` ROCmFPX llama.cpp fork — PULLED
  from `ghcr.io/julianmb/q38rocm:1.5.3` (never built). MTP is **built into the
  model** (no separate drafter file). The image's `run_server.sh` entrypoint
  builds the full "speed" profile command (ctx 131072, MTP draft-n 4, KV
  K=q8_0/V=turbo4, 128K prompt cache, auto Vulkan0/ROCm0). Port 8080, ctx 131072.

- **Qwen38-Flash-Next (UD-Q2_K_XL)** — Qwen3.8-Flash-Next (UD-Q2_K_XL, ~89 GB) via Podman
  Vulkan container. Port 8080, ctx 262144.

- **Qwen38-Flash-Next IQ4 (UD-IQ4_XS)** — Qwen3.8-Flash-Next 125B-A6B (UD-IQ4_XS,
  3 shards, ~87 GiB on disk) via Podman Vulkan container. Second Flash-Next
  profile: ctx 131072 (~91 GB resident), `--load-mode none`, KV cache f16
  (quantized KV asserts on the `qwen4exp` arch), `--jinja`, `--reasoning on`,
  single slot, sampler defaults temp 1.0 / top-p 0.95 / top-k 20 / min-p 0.0.
  Port 8080. Measured on a 128 GB Strix Halo: ~23 t/s decode, ~390 t/s pp512.

- **Qwen38-Flash-Next AP (Q5_K_XL)** — Qwen3.8-Flash-Next-AP 125B-A6B (Q5_K_XL,
  single ~112 GiB GGUF from `agentionai`) via Podman Vulkan container, with
  **image recognition** (the `unsloth` `mmproj-F16.gguf` projector is downloaded
  and passed as `--mmproj`). Third Flash-Next profile, chosen because the Q4/IQ4
  quants had quality issues: `-ngl 99`, `--n-cpu-moe 0`, `-fa on`, `--load-mode
  mmap` (112 GiB pages from disk so the KV cache fits), `--no-op-offload`,
  `--override-tensor per_layer_token_embd=CPU`, `--jinja`, `--parallel 1`, sampler
  defaults temp 1.0 / top-p 0.95 / top-k 20 / min-p 0.0. Port 8080. Reported on a
  128 GB Strix Halo: ~450 pp @ 2048 ctx, ~240 pp @ ~100k ctx, 12–20 t/s decode, no MTP.

- **Gemma 4 26B A4B (UD-Q8_K_XL)** — Gemma 4 26B A4B it (UD-Q8_K_XL, ~27.6 GB) via
  Podman Vulkan container, with **image recognition**: the `mmproj-F16.gguf` vision
  projector is downloaded and passed as `--mmproj`, so `/v1/chat/completions`
  accepts `image_url` content parts. Port 8080, ctx 262144 — same profile as
  Qwen36-35B-A3B.

### Multi-Node Tracks (`ansible/multi-node/`)
Cluster-based inference across multiple machines:

- **vllm-rccl-moe** — multi-model vLLM + Ray + RCCL track for MoE models across
  the two nodes (TP=2). Profiles via `-e active_profile=<name>`:
  `minimax-m2.7-awq-4bit` (default — `cyankiwi/MiniMax-M2.7-AWQ-4bit`),
  and `qwen3.5-122b-awq-4bit` (`cyankiwi/Qwen3.5-122B-A10B-AWQ-4bit`).
  The track **prefers the Thunderbolt link** (`tb*` from `setup-thunderbolt-net.yml`,
  ~40 Gbps) for RCCL KV exchange and falls back to the 2.5Gbe NIC with a warning.
  Reuses the `vllm_cluster` container name (one model at a time, `--replace`).
  Port 8081; head/worker IPs derive from the inventory hostvars
  (`vllm_moe_role` — TB static 172.20.0.1/.2 by default); override with
  `-e vllm_moe_head_ip=... -e vllm_moe_worker_ip=...` (e.g. LAN IPs, TB down).

- **ds4-deepseek-v4-flash-mtp** — DeepSeek V4 Flash on the dedicated `ds4`
  engine, 2-node **pipeline parallel** (head/coordinator `--layers 0:21`,
  worker `--layers 22:output`) + **MTP speculative decoding** on the head
  (`--mtp`, `--mtp-draft 1`). Toolbox container `ds4_cluster` (separate from
  `vllm_cluster`) on `docker.io/kyuz0/strix-halo-ds4-toolbox:multi-node-rocm-7.2.4`.
  The ~153 GB Q4KExperts hybrid GGUF from `antirez/deepseek-v4-gguf` lives at
  `~/ds4` on both nodes (mounted at `/root/ds4`); the ~3.6 GB MTP drafter is
  head-only. Pipeline channel on port 8081 (head listens, worker dials in)
  rides the Thunderbolt link (`tb*`, ~40 Gbps) when up; the OpenAI API is on
  port 8000 of the head. Head/worker IPs derive from the inventory hostvars
  (`ds4_role` — TB static 172.20.0.1/.2 by default); override with
  `-e ds4_head_ip=... -e ds4_worker_ip=...`. Start the head first, then the
  worker (`DS4_ROLE=head|worker`).

- **Thunderbolt networking** — `setup-thunderbolt-net.yml` sets up the
  direct TB4 cable between the two Z2 G1a nodes: loads + persists
  `thunderbolt-net`, assigns `172.20.0.<n>/24` (first inventory host = `.1`,
  second = `.2`), persists via NetworkManager (`ipv4.never-default`), and
  verifies speed (~40 Gbps) + peer ping. Distro-agnostic (CachyOS/Arch +
  Ubuntu). **Multi-node only** — targets the `multinode` capability group, so
  a single-node inventory (no such group) skips it entirely.

### Shared Setup Playbooks (`ansible/shared/`)
Host-level setup shared by both tracks (imported by each track's bootstrap):

- `install-amdgpu.yml` — Ubuntu base: apt upgrade + ROCm via amdgpu-install (Ubuntu-gated)
- `install-podman.yml` — cross-distro Podman installation (Fedora/Debian/Arch)
- `install-hf-cli.yml` — HuggingFace CLI installation
- `set-grub-ttm.yml` — GRUB kernel args: TTM, IOMMU, GTT size (+ opt-in GPU watchdog `amdgpu.lockup_timeout` via `-e lockup_timeout_enabled=true`)
- `set-limine-ttm.yml` — Limine bootloader kernel args, same set (Limine hosts only)

## Quick Start

### Single-Node (recommended for this host)
```bash
# Full single-node bootstrap:
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/bootstrap.yml

# Run a single Podman track:
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen36-35b-ud-q8-k-xl-podman.yml
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen38-27b-ud-q4-k-xl-podman.yml
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen38-27b-rocmfp4-podman.yml
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen38-flash-next-ap-q5-k-xl-podman.yml
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/gemma-4-26b-a4b-ud-q8-k-xl-podman.yml

# Skip base (already provisioned):
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/bootstrap.yml --skip-tags install-amdgpu
```

### Multi-Node (cluster)
```bash
# Full multi-node bootstrap:
ansible-playbook -i ansible/multi-node/inventory/hosts ansible/multi-node/bootstrap.yml

# Thunderbolt node-to-node link (run on both nodes, TB4 cable attached):
ansible-playbook -i ansible/multi-node/inventory/hosts ansible/multi-node/setup-thunderbolt-net.yml

# vLLM + RCCL MoE track (both nodes) — head/worker IPs come from the
# inventory hostvars (vllm_moe_role); -e overrides when TB is down:
ansible-playbook -i ansible/multi-node/inventory/hosts ansible/multi-node/vllm-rccl-moe.yml

# ds4 DeepSeek V4 Flash track (both nodes) — pipeline parallel + MTP;
# launch per-node later with DS4_ROLE=head|worker:
ansible-playbook -i ansible/multi-node/inventory/hosts ansible/multi-node/ds4-deepseek-v4-flash-mtp.yml
```

## Layout

```
├── README.md                      this file
├── SYSTEM.md                      hardware spec & design rules
├── reference/
│   ├── cachyos-notes.md           CachyOS installation notes
│   └── playbook.txt               AMD ds4 playbook (text extract)
├── ansible/
│   ├── shared/                    Shared setup playbooks (imported by both tracks)
│   │   ├── install-amdgpu.yml     Ubuntu base: apt upgrade + ROCm (Ubuntu-gated)
│   │   ├── install-podman.yml     Podman installation (Fedora/Debian/Arch)
│   │   ├── install-hf-cli.yml     HuggingFace CLI installation
│   │   ├── set-grub-ttm.yml       GRUB TTM kernel args
│   │   └── set-limine-ttm.yml     Limine bootloader TTM settings
│   │
│   ├── single-node/               Single-node tracks (one host, one model at a time)
│   │   ├── bootstrap.yml          ORCHESTRATOR: single-node playbooks
│   │   ├── summary.yml            final per-host completion summary           [summary]
│   │   ├── qwen36-35b-ud-q8-k-xl-podman.yml  Qwen3.6-35B-A3B (Podman Vulkan)
│   │   ├── qwen38-27b-ud-q4-k-xl-podman.yml  Qwen3.8-27B (Podman Vulkan + MTP)
│   │   ├── qwen38-27b-rocmfp4-podman.yml  Qwen3.8-27B (ROCmFPX engine, ROCmFP4_FAST, built-in MTP)
│   │   ├── qwen38-flash-next-ap-q5-k-xl-podman.yml  Qwen3.8-Flash-Next AP Q5_K_XL (Podman Vulkan + vision)
│   │   ├── gemma-4-26b-a4b-ud-q8-k-xl-podman.yml  Gemma 4 26B A4B (Podman Vulkan + vision)
│   │   ├── tasks/                 Shared task files included by the tracks above
│   │   │   ├── podman-models-dir.yml            models dir + ownership
│   │   │   ├── hf-download-files.yml            HF download loop (skip if present, optional rename)
│   │   │   ├── podman-remove-container.yml      podman rm -f before (re)launch
│   │   │   ├── podman-check-running.yml         start result + running check
│   │   │   ├── podman-wait-health.yml           sleep + poll /health
│   │   │   └── podman-render-launch-artifacts.yml  launch script + pi config render
│   │   ├── inventory/
│   │   │   ├── hosts              single-node inventory (vulkan/rocm → aiservers)
│   │   │   ├── hosts.example      sample multi-machine inventory
│   │   │   └── group_vars/all.yml placeholder — empty; tracks define vars inline
│   │   ├── templates/             Jinja templates (rendered by each track)
│   │   │   ├── scripts/           Launch script templates
│   │   │   │   ├── qwen36-35b-ud-q8-k-xl-start.sh.j2   Qwen3.6-35B Vulkan launch
│   │   │   │   ├── qwen38-27b-ud-q4-k-xl-start.sh.j2   Qwen3.8-27B Vulkan launch (with MTP)
│   │   │   │   ├── qwen38-27b-rocmfp4-start.sh.j2   Qwen3.8-27B ROCmFPX launch (prebuilt image)
│   │   │   │   ├── gemma-4-26b-a4b-ud-q8-k-xl-start.sh.j2   Gemma 4 Vulkan launch (model + mmproj)
│   │   │   │   └── qwen38-flash-next-ap-q5-k-xl-start.sh.j2   Flash-Next AP Q5_K_XL launch (model + mmproj)
│   │   │   ├── pi-configs/        PI agent JSON config templates
│   │   │   │   ├── pi-qwen36-35b-ud-q8-k-xl-podman.json.j2
│   │   │   │   ├── pi-qwen38-27b-ud-q4-k-xl-podman.json.j2
│   │   │   │   ├── pi-qwen38-27b-rocmfp4-podman.json.j2
│   │   │   │   ├── pi-gemma-4-26b-a4b-ud-q8-k-xl-podman.json.j2
│   │   │   │   └── pi-qwen38-flash-next-ap-q5-k-xl-podman.json.j2
│   │   └── rendered/              Rendered output (gitignored)
│   │       ├── scripts/           Rendered launch scripts
│   │       └── pi-configs/        Rendered pi agent configs
│   │
│   ├── multi-node/                Multi-node cluster tracks
│   │   ├── bootstrap.yml          ORCHESTRATOR: shared/ setup + multi-node playbooks
│   │   ├── summary.yml            final per-host completion summary           [summary]
│   │   ├── setup-thunderbolt-net.yml  TB4 node-to-node cluster link (multi-node only) + tb-net-diag
│   │   ├── vllm-rccl-moe.yml          Multi-model vLLM + RCCL MoE track, TB link preferred
│   │   ├── ds4-deepseek-v4-flash-mtp.yml  2-node ds4 DeepSeek V4 Flash (pipeline parallel + MTP), TB link preferred
│   │   ├── inventory/
│   │   │   ├── hosts              multi-node inventory (halo0 head + halo1 worker, SSH; rocm → aiservers, multinode for TB)
│   │   │   └── group_vars/all.yml placeholder — empty; tracks define vars inline
│   │   ├── templates/             Jinja templates
│   │   │   ├── vllm-rccl-moe-start.sh.j2          vLLM MoE cluster launch (head/worker)
│   │   │   ├── pi-vllm-rccl-moe.json.j2           pi agent config (active profile)
│   │   │   ├── ds4-deepseek-v4-flash-mtp-start.sh.j2  ds4 cluster launch (DS4_ROLE=head|worker)
│   │   │   ├── pi-ds4-deepseek-v4-flash-mtp.json.j2   pi agent config (deepseek thinking format)
│   │   │   └── tb-net-diag.sh.j2                   TB4 link diagnostics (iperf3 server/client/ping)
│   │   └── rendered/              Rendered output (gitignored)
│   │       ├── scripts/           Rendered launch scripts
│   │       └── pi-configs/        Rendered pi agent configs
│   │
│   └── secrets/                   Secret files (gitignored)
│       └── hf_token.txt           HuggingFace token for gated model downloads
```

## Track Details

### Qwen36-35B-A3B (UD-Q8_K_XL) — Podman Vulkan
- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan`
- **Model**: Qwen3.6-35B-A3B UD-Q8_K_XL (~38.5 GB)
- **Context**: 262k (native ceiling)
- **Port**: 8080
- **Backend**: Vulkan/RADV

### Qwen38-27B (UD-Q4_K_XL) — Podman Vulkan + MTP
- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan`
- **Model**: Qwen3.8-27B UD-Q4_K_XL (`Qwen3.8-27B-UD-Q4_K_XL.gguf`)
- **Drafter**: `MTP/mtp-Qwen3.8-27B-Q4_0.gguf`, passed as `--model-draft`
  (`draft-mtp` is only auto-discovered with `-hf`, never from a local `--model`)
- **Context**: 262144 (native ceiling), `--parallel 1` (single slot)
- **Port**: 8080
- **Backend**: Vulkan/RADV
- **Speculation**: `--spec-type draft-mtp --spec-draft-n-max 3`, KV cache f16 (K+V)
- **Batching / loading**: `-b 2048`, `-ub 512`, `-fa on`, `--load-mode mmap`, `-ngl 999`

### Qwen38-27B (ROCmFP4_FAST) — ROCmFPX engine (julianmb/q38rocm)
- **Container**: `ghcr.io/julianmb/q38rocm:1.5.3` — custom ROCmFPX llama.cpp
  fork, **pulled from GHCR (never built)**. The only track that does not use the
  Nathanw1014 image; its `run_server.sh` entrypoint builds the full server
  command, and everything after the image name on the `podman run` line is
  appended to it as `llama-server` overrides (`--ctx`/`--slots` today, plus an
  optional `extra_args` profile knob — see below).
- **Model**: `Qwen3.8-27B-ROCmFP4-FAST.gguf` (ROCmFP4_FAST, ~13.5 GB) from
  `julianmb/Qwen-3.8-27B-ROCmFP4-FAST-GGUF`.
- **MTP**: **built into the model** — `--spec-type draft-mtp` with no separate
  `--model-draft` drafter file (unlike the UD-Q4_K_XL track).
- **Speed profile defaults**: ctx 131072, MTP draft-n 4, KV K=q8_0/V=turbo4,
  batch 2048 / ubatch 1024, temperature 0, 128K prompt cache (32 GiB / 64 ckpts).
- **Port**: 8080 (host) → 8000 (container; fixed by the image)
- **GPU**: `/dev/kfd` + `/dev/dri/renderD128`, auto Vulkan0→ROCm0; Strix Halo
  env (HSA_OVERRIDE_GFX_VERSION=11.5.1, unified memory) set inside the image.
- **Slots**: 1 (override with the `parallel` playbook var).
- **DeviceLost mitigation**: the container is started with
  `GGML_VK_MAX_NODES_PER_SUBMIT=1` (profile knob `vk_max_nodes_per_submit`,
  set `""` to unset). If long prompts still abort, pass `extra_args` (appended
  to `run_server.sh`'s command), e.g. `ansible-playbook ...
  -e extra_args='--spec-type none'`; escalate to the kernel watchdog only if
  needed (`set-grub-ttm.yml` / `set-limine-ttm.yml` with
  `-e lockup_timeout_enabled=true`). See [Troubleshooting](#troubleshooting).

### Qwen38-Flash-Next (UD-Q2_K_XL) — Podman Vulkan
- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan`
- **Model**: Qwen3.8-Flash-Next 125B-A6B UD-Q2_K_XL (~89 GB), 3 shards under
  `UD-Q2_K_XL/`, renamed locally to `Qwen3.8-Flash-Next-UD-Q2_K_XL/`
- **Context**: 262144 (native ceiling)
- **Port**: 8080
- **Backend**: Vulkan/RADV (`qwen4exp` arch)

### Qwen38-Flash-Next IQ4 (UD-IQ4_XS) — Podman Vulkan
- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan`
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

### Qwen38-Flash-Next AP (Q5_K_XL) — Podman Vulkan + image input
- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan`
- **Model**: Qwen3.8-Flash-Next-AP 125B-A6B Q5_K_XL (~112 GiB), single GGUF from
  `agentionai/Qwen3.8-Flash-Next-AP-GGUF`, kept under the repo name on disk
  (`~/models/agentionai/Qwen3.8-Flash-Next-AP-GGUF/AP-Q5_K_XL/...`)
- **Vision projector**: `mmproj-F16.gguf` from `unsloth/Qwen3.8-Flash-Next-GGUF`
  → `~/models/unsloth/Qwen3.8-Flash-Next-GGUF/mmproj-F16.gguf`, passed as `--mmproj`
  (image input ON)
- **Why Q5_K_XL**: the Q4/IQ4 quants had quality issues — this is the agentionai
  "AP" fine-tune at a higher quant
- **Context**: 131072 (the one knob the profile leaves free — tune with `-e ctx=...`)
- **Port**: 8080 (shared with the other Podman tracks — one server at a time)
- **Backend**: Vulkan/RADV (`qwen4exp` arch — same pinned-image requirement as the
  other Flash-Next profiles; no MTP)
- **Loading**: `--load-mode mmap` (112 GiB pages from disk so the KV cache fits),
  `--n-cpu-moe 0` (all MoE experts on GPU), `--no-op-offload`,
  `--override-tensor per_layer_token_embd=CPU` (token embedding pinned to CPU)
- **Sampling**: `--jinja`, defaults temp 1.0 / top-p 0.95 / top-k 20 / min-p 0.0,
  `--parallel 1` (single slot), `-ngl 99` (not 999), `-fa on`
- **Reported** on a 128 GB Strix Halo (v0.7.2, mmap): ~450 pp @ 2048 ctx,
  ~240 pp @ ~100k ctx, 12–20 t/s decode.

### Gemma 4 26B A4B (UD-Q8_K_XL) — Podman Vulkan + image input
- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan`
- **Model**: Gemma 4 26B A4B it UD-Q8_K_XL (~27.6 GB), single GGUF at the repo root
- **Vision projector**: `mmproj-F16.gguf` (~1.19 GB) → stored as
  `gemma-4-26B-A4B-it-mmproj-F16.gguf`, passed as `--mmproj` (llama.cpp
  `libmtmd`; the projector is GPU-offloaded by default)
- **Context**: 262144 (native ceiling)
- **Port**: 8080 (shared with the other Podman tracks — one server at a time)
- **Backend**: Vulkan/RADV
- **Note**: no MTP speculation wired up, although `MTP/mtp-gemma-4-26B-A4B-it-*.gguf`
  exists in the repo and could follow the qwen38-27b pattern later.

### vllm-rccl-moe (Multi-Node)
- **Engine**: vLLM + Ray + RCCL (TP=2 across the two nodes)
- **Profiles** (`-e active_profile=<name>` — each runs at the model's native
  max context, sized off the 2×128 GB KV pool):
  - `minimax-m2.7-awq-4bit` (default) — `cyankiwi/MiniMax-M2.7-AWQ-4bit`, ctx 196608
  - `qwen3.5-122b-awq-4bit` — `cyankiwi/Qwen3.5-122B-A10B-AWQ-4bit`, ctx 262144
- **Port**: 8081 (head node)
- **Backend**: ROCm; RCCL traffic rides the Thunderbolt link (`tb*`, ~40 Gbps)
  when up, else the 2.5Gbe NIC — see `setup-thunderbolt-net.yml`

### ds4-deepseek-v4-flash-mtp (Multi-Node)
- **Engine**: `ds4` (antirez's DeepSeek V4 inference engine) in the toolbox
  container `ds4_cluster` — `docker.io/kyuz0/strix-halo-ds4-toolbox:multi-node-rocm-7.2.4`
- **Model**: `DeepSeek-V4-Flash-Q4KExperts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-imatrix.gguf`
  (~153 GB hybrid quant, `antirez/deepseek-v4-gguf`) at `~/ds4` on both nodes
- **MTP**: drafter `DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf` (~3.6 GB) on the
  head only — `--mtp <file> --mtp-draft 1`
- **Parallelism**: 2-node pipeline (layer slicing) — head/coordinator
  `--layers 0:21 --listen <head_ip> 8081`, worker `--layers 22:output
  --coordinator <head_ip> 8081`; the pipeline channel rides the Thunderbolt
  link (`tb*`, ~40 Gbps) when up
- **Context**: 262144 (256k, per the toolbox multi-node example)
- **Ports**: 8081 (pipeline, head listens) + 8000 (OpenAI API on the head)
- **Launch order**: head first (`DS4_ROLE=head`), then worker
  (`DS4_ROLE=worker`) via the rendered script
- **Backend**: ROCm 7.2.4 (the multi-node binary ships only in the
  `multi-node-rocm-7.2.4` toolbox image tag)

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

# Qwen3.8-Flash-Next-AP (Q5_K_XL, single ~112 GiB GGUF) + vision projector
hf download agentionai/Qwen3.8-Flash-Next-AP-GGUF AP-Q5_K_XL/Qwen3.8-Flash-Next-AP-Q5_K_XL.gguf \
  --local-dir ~/models/agentionai/Qwen3.8-Flash-Next-AP-GGUF
                             # lands under the repo name: ~/models/agentionai/.../AP-Q5_K_XL/...
hf download unsloth/Qwen3.8-Flash-Next-GGUF mmproj-F16.gguf \
  --local-dir ~/models/unsloth/Qwen3.8-Flash-Next-GGUF
                             # lands under the repo name: ~/models/unsloth/Qwen3.8-Flash-Next-GGUF/mmproj-F16.gguf
```

## Launch Scripts

After the bootstrap, the rendered launch scripts are in `~/scripts/` on the
target host. The bootstrap also drops PI agent configs into
`ansible/pi-configs/` (rendered on the controller).

### Single-Node Launch Example
```bash
# Qwen3.6-35B-A3B (Podman Vulkan)
~/scripts/qwen36-35b-ud-q8-k-xl-start.sh

# Qwen3.8-27B (Podman Vulkan + MTP)
~/scripts/qwen38-27b-ud-q4-k-xl-start.sh

# Qwen3.8-27B (ROCmFPX engine, ROCmFP4_FAST, prebuilt julianmb/q38rocm image)
~/scripts/qwen38-27b-rocmfp4-start.sh

# Qwen3.8-Flash-Next AP (Q5_K_XL, Podman Vulkan, image input)
~/scripts/qwen38-flash-next-ap-q5-k-xl-start.sh

# Gemma 4 26B A4B (Podman Vulkan, image input)
~/scripts/gemma-4-26b-a4b-ud-q8-k-xl-start.sh
```

### Multi-Node Launch Example (vllm-rccl-moe)
```bash
# halo0 (head — Ray head + vLLM server):
VLLM_RCCL_MOE_ROLE=head   ./ansible/scripts/vllm-rccl-moe-start.sh
# halo1 (worker — joins Ray):
VLLM_RCCL_MOE_ROLE=worker ./ansible/scripts/vllm-rccl-moe-start.sh
```

### Multi-Node Launch Example (ds4-deepseek-v4-flash-mtp)
```bash
# halo0 (head — coordinator: layers 0:21, MTP drafter, OpenAI API):
DS4_ROLE=head   ./ansible/scripts/ds4-deepseek-v4-flash-mtp-start.sh
# halo1 (worker — pipeline worker: layers 22:output, joins the coordinator):
DS4_ROLE=worker ./ansible/scripts/ds4-deepseek-v4-flash-mtp-start.sh

# Once warm: OpenAI endpoint http://<head_ip>:8000/v1
# First run downloads the ~153 GB main GGUF on both nodes and the ~3.6 GB
# MTP drafter on the head into ~/ds4 (mounted at /root/ds4 in the container).
```

## Pi Agent Config

The bootstrap drops pi agent configs into `ansible/pi-configs/`:

- **Podman tracks:**
  - `pi-qwen36-35b-ud-q8-k-xl-podman.json` — provider `qwen36-35b-ud-q8-k-xl` → `http://<node_ip>:8080/v1`
  - `pi-qwen38-27b-ud-q4-k-xl-podman.json` — provider `qwen38-27b-ud-q4-k-xl` → `http://<node_ip>:8080/v1`
  - `pi-qwen38-27b-rocmfp4-podman.json` — provider `qwen38-27b-rocmfp4` → `http://<node_ip>:8080/v1`
  - `pi-qwen38-flash-next-ap-q5-k-xl-podman.json` — provider `qwen38-flash-next-ap-q5-k-xl` → `http://<node_ip>:8080/v1`
  - `pi-gemma-4-26b-a4b-ud-q8-k-xl-podman.json` — provider `gemma-4-26b-a4b-ud-q8-k-xl` → `http://<node_ip>:8080/v1`

- `pi-vllm-rccl-moe.json` — `vllm-rccl-moe` provider (active profile) → `http://<head_ip>:8081/v1`
- `pi-ds4-deepseek-v4-flash-mtp.json` — `ds4-deepseek-v4-flash-mtp` provider (deepseek thinking format) → `http://<head_ip>:8000/v1`

Merge the provider block(s) into `~/.pi/agent/models.json` (pi reloads it when
you open `/model`; no restart needed).

## Config Variables (inventory / env)

### Single-Node Tracks
(All single-node playbooks are self-contained with inline vars — no group_vars needed. The ROCmFP4 track groups its per-model knobs into a `rocm_image_profiles` dict selected by `active_profile`, deriving `docker_image`/`model`/`port`/`ctx`/`parallel` from the active profile.)

### Multi-Node Tracks
- vllm-rccl-moe: `active_profile` (minimax-m2.7-awq-4bit | qwen3.5-122b-awq-4bit), `vllm_moe_head_ip` / `vllm_moe_worker_ip` (derived from `vllm_moe_role` hostvars; override via -e), `vllm_moe_port` (8081), `vllm_moe_tp_size` (2), `vllm_moe_gpu_util` (0.9)
- ds4-deepseek-v4-flash-mtp: `ds4_head_ip` / `ds4_worker_ip` (derived from `ds4_role` hostvars; override via -e), `ds4_ctx` (262144), `ds4_mtp_draft` (1), `ds4_layers_head` (0:21), `ds4_layers_worker` (22:output), `ds4_pp_port` (8081), `ds4_api_port` (8000), `ds4_max_tokens` (65536)
- setup-thunderbolt-net (multi-node): `tb_net_enabled` (true), `tb_net_cidr` (172.20.0.0/24), `tb_net_ip` / `tb_net_peer_ip` (per-host override), `tb_net_install_iperf` (true), `tb_net_iperf_test` (true), `tb_net_iperf_port` (5201), `tb_net_iperf_parallel` (4), `tb_net_iperf_time` (10)

### Scripts
Each single-node track renders one launch script to `~/scripts/<stem>-start.sh`.
The settings below are baked into the rendered script as plain shell variables
(`CONTAINER`, `PORT`, `MODEL`, `IMAGE`, `CTX`, ...); edit the file in place and
re-run it to change them.
- `qwen36-35b-ud-q8-k-xl-start.sh` (CONTAINER/PORT/MODEL/IMAGE/CTX/BATCH/GPU_LAYERS)
- `qwen38-27b-ud-q4-k-xl-start.sh` (CONTAINER/PORT/MODEL/DRAFT/IMAGE/CTX/PARALLEL/BATCH/UBATCH/GPU_LAYERS/CACHE_K/CACHE_V/FLASH_ATTN/LOAD_MODE/SPEC_TYPE/SPEC_DRAFT_N_MAX)
- `qwen38-27b-rocmfp4-start.sh` (CONTAINER/HOST_PORT/CONTAINER_PORT/IMAGE/CTX/SLOTS — prebuilt julianmb/q38rocm image)
- `qwen38-flash-next-ap-q5-k-xl-start.sh` (CONTAINER/PORT/MODEL/MMPROJ/IMAGE/CTX/PARALLEL/GPU_LAYERS/N_CPU_MOE/FLASH_ATTN/LOAD_MODE/TEMP/TOP_P/TOP_K/MIN_P)
- `gemma-4-26b-a4b-ud-q8-k-xl-start.sh` (CONTAINER/PORT/MODEL/MMPROJ/IMAGE/CTX/BATCH/GPU_LAYERS)
- `VLLM_RCCL_MOE_ROLE` (head|worker) — multi-node only, still env-set

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
local llama.cpp build step, and use the official `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan`
Vulkan container instead. MTP speculation args are baked into both the container
`run` command and the rendered launch script.

**Architecture:** the ansible playbook is **bootstrap-only**. It installs
packages, sets GRUB, creates containers/toolboxes, builds llama.cpp, and
downloads model weights. It NEVER launches servers.

## Troubleshooting

### `vk::DeviceLostError` / "context is lost" mid-prompt (Vulkan tracks)

**Symptom** — the server dies during a long prompt (tens of thousands of
tokens) with:

```
# host kernel log (journalctl -k)
amdgpu: ring comp_1.2.0 timeout, signaled seq=…, emitted seq=…
amdgpu: Ring comp_1.2.0 reset succeeded
# container log (podman logs <container>)
radv/amdgpu: The CS has been cancelled because the context is lost. This context is guilty of a hard recovery.
terminate called after throwing an instance of 'vk::DeviceLostError'
  what():  vk::Queue::submit: ErrorDeviceLost
```

**Cause** — a single `vkQueueSubmit` runs longer than the amdgpu compute-ring
watchdog (`amdgpu.lockup_timeout`), so the kernel resets the ring and RADV
reports a lost device. Long-context FLASH_ATTN submits are the usual trigger
(llama.cpp #21724 / #20515 / #20889, ollama/ollama#17870 on the same chip);
MTP speculation makes it worse because `common_speculative_process` runs an
extra full-width draft decode after **every** prompt ubatch — with
`--spec-type draft-mtp` repros die around 55k tokens even with one node per
submit, while MTP-off survives 125k+ (llama.cpp #27306).

**Mitigations (layered — the playbooks always apply 2; 1 is opt-in and only
needed if the rest proves insufficient):**

1. **Kernel watchdog (opt-in, last resort)** — run `set-grub-ttm.yml` /
   `set-limine-ttm.yml` with `-e lockup_timeout_enabled=true` (reboot
   required). Quick no-reboot test:
   `echo 60000 | sudo tee /sys/module/amdgpu/parameters/lockup_timeout`.
   Trade-off: a genuinely hung GPU takes longer to auto-recover.
2. **Submit batching pin** — `-e GGML_VK_MAX_NODES_PER_SUBMIT=1` (upstream fix
   #24872; default 1 on UMA since, pinned explicitly by the ROCmFP4 track).
3. **Smaller ubatches** — lower `--ubatch-size` (e.g. 512 or 128) shrinks the
   work per submit; costs prefill speed.
4. **MTP off for long prompts** — ROCmFP4 track:
   `-e extra_args='--spec-type none'`; UD-Q4_K_XL track: drop
   `--spec-type draft-mtp` / `--model-draft` from the start script.

**Evidence to capture if it persists** — `journalctl -k | grep -E 'amdgpu.*(timeout|reset)'`,
`podman logs <container>`, and the exact prompt length / argv at which it dies;
that distinguishes the watchdog class above from the separate
checkpoint/`get_tensor` DeviceLost class (which happens with prompt-cache
checkpoints armed).
