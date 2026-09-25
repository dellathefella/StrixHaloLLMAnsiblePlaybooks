# StrixHalo LLM Ansible Playbooks — Ryzen AI Max (HP Z2 G1a)

Organized workspace for bootstrapping AMD ROCm / Vulkan LLM inference on the
Ryzen AI Max "Strix Halo" APU, on **HP Z2 G1a** workstations (2.5Gbe NICs —
no 10Gbps requirement; optional TB4 node-to-node link, see below).
CachyOS (Arch-based) first, Ubuntu 26.04 second. Tracks organized by **deployment
topology** (single-node vs multi-node) with separate bootstrap orchestrators:

## Deployment Topology

### Single-Node Tracks (`ansible/single-node/`)

All single-node tracks run locally on a single machine (llama.cpp Vulkan or
halogen ROCm):

- **Qwen36-35B-A3B MTP (UD-Q8_K_XL)** — Qwen3.6-35B-A3B (8-bit UD-Q8_K_XL,
  ~38.5 GB) via Podman Vulkan container
  (`ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan-v0.7.6.1`), but from the
  `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` repo, which bakes MTP speculative
  decoding **into the GGUF itself** (no separate drafter file).
  Follows the model card's own quickstart: `-ngl 99` (not 999), `-fa on`,
  `--parallel 1` (MTP doesn't support `-np > 1` yet), `--spec-type draft-mtp
  --spec-draft-n-max 2`. Loading this GGUF without `--spec-type draft-mtp`
  fails to load at all — it's not optional here. Port 8080, ctx 262144.

- **Qwen38-27B (UD-Q4_K_XL)** — Qwen3.8-27B (UD-Q4_K_XL) via Podman Vulkan
  container with **MTP speculative decoding** via the repo drafter
  `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` (`draft-mtp`, draft n-max 3, f16 KV cache,
  batch 2048 / ubatch 512, flash-attn on, mmap loading, single slot).
  Port 8080, ctx 262144.

- **Qwen38-27B (q38rocm)** — the same ROCmFP4-FAST model served via the model
  author's own prebuilt, Strix-Halo-tuned image (`ghcr.io/julianmb/q38rocm`).
  Its profile-driven `run_server.sh` auto-detects Vulkan0 (Mesa RADV Wave64 +
  KHR_coopmat) and wires up MTP speculative decoding + asymmetric TurboQuant
  KV + RAM prompt-caching. We run the `speed` profile with `DRAFT_N=3`
  (measured best on halo1: ~24.8 t/s decode, ~50% MTP acceptance). **Pulled,
  never built.** Port 8080, ctx 131072. (Formerly a from-source build of the
  LaurentZuijdwijk DFlash2 fork — replaced because that fork shipped no
  runnable image.)

- **Qwen38-Flash-Next AP (Q5_K_XL)** — Qwen3.8-Flash-Next-AP 125B-A6B (Q5_K_XL,
  single ~112 GiB GGUF from `agentionai`) via Podman Vulkan container, with
  **image recognition** (the `unsloth` `mmproj-F16.gguf` projector is downloaded
  and passed as `--mmproj`). The only Flash-Next profile kept — the UD-Q2_K_XL
  and UD-IQ4_XS quants were dropped for unreliable output quality: `-ngl 99`,
  `--n-cpu-moe 0`, `-fa on`, `--load-mode
  mmap` (112 GiB pages from disk so the KV cache fits), `--no-op-offload`,
  `--override-tensor per_layer_token_embd=CPU`, `--jinja`, `--parallel 1`, sampler
  defaults temp 1.0 / top-p 0.95 / top-k 20 / min-p 0.0. Port 8080. Reported on a
  128 GB Strix Halo: ~450 pp @ 2048 ctx, ~240 pp @ ~100k ctx, 12–20 t/s decode, no MTP.

- **Qwen38-Flash-Next (halogen)** — Qwen3.8-Flash-Next W4B (~118 GB, 179.55B
   params @ 5.53 bpw) via peonist's **halogen-flash-server** — a closed-source,
   purpose-built **ROCm** engine (not a llama.cpp fork) shipped as the prebuilt
   image `ghcr.io/peonist-ai/halogen-flash-server:0.13.4` (PULLED, never built).
   Weights are the repo's native `.hgn` format (loadable only by halogen): the
    track downloads `qwen38-flash-next-w4b.hgn` (115.55 GiB checkpoint) +
    `qwen38-flash-next-w4b.overlay.hgn` (quality sidecar) +
    `qwen38-flash-next-vision.hgn` (vision tower) + `tokenizer/` into a
    dedicated `~/halogen-models` dir bind-mounted at `/models:ro`, where the
    engine auto-discovers them. OpenAI-compatible `/v1` + `/health` on port
    **8731** (the only track not on 8080 — it targets the `rocm` group).
    Greedy sampling by default; the card's thinking-mode settings (temp 1.0 /
    top-p 0.95 / top-k 20) are a commented `HALOGEN_*` env block in the launch
     script. The ~118 GiB cold load is slow — the track waits up to ~10 min for
     `/health`. **Image input is enabled**: the vision tower is mounted and
     `HALOGEN_VISION_TOWER` points the engine at it.

- **Qwen38-Flash-Next ABLITERATED (halogen)** — the same halogen engine serving a
   **refusal-direction abliteration** of the vendor checkpoint, delivered as the
   gated `Ae55667/halogen-qwen3.8-flash-next-abliterated` **patch kit** (Apache-2.0).
   **EXPERIMENTAL**: abliteration is a heuristic weight edit — it can degrade
   reasoning, factuality, or instruction-following in ways that are hard to
   predict. Use where fewer refusals matter more than guaranteed quality.
   The track downloads the vendor checkpoint at the **pinned revision**
   `942daecd…`, downloads the gated patch kit, runs `apply_expert_patch.py` to
   rewrite the 49 MoE expert `down_proj` tensors **in place** (sha256-verified,
   with backup), then starts the engine with `HALOGEN_CK_OVERLAY` pointed at the
   abliterated quality overlay. Engine `0.13.4` (latest peonist). Lives in a
   **separate** `~/halogen-ablit/` tree so it never clobbers the stock halogen
   track (mutually exclusive at runtime, ~88 GiB resident). Port **8731**, ROCm.
   **Gated**: request access on the HuggingFace model page + `hf auth login`
   before running. **Image input is enabled by default**: the vendor vision
   tower `qwen38-flash-next-vision.hgn` is fetched at the pinned revision
   and passed as `HALOGEN_VISION_TOWER=/models/qwen38-flash-next-vision.hgn`
   (`-e enable_vision=false` for text-only).

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
  (`--mtp --mtp-model <drafter> --mtp-draft 1`). Toolbox container `ds4_cluster`
  (separate from `vllm_cluster`) on
  `docker.io/kyuz0/strix-halo-ds4-toolbox:multi-node-rocm-7.2.4`.
  The ~153 GB Q4KExperts hybrid GGUF from `antirez/deepseek-v4-gguf` is
  downloaded by the playbook into `~/ds4` on both nodes and bind-mounted
  read-only into the container at the same path; the ~3.6 GB MTP drafter is
  head-only. Pipeline channel on port 8081 (head listens, worker dials in)
  rides the Thunderbolt link (`tb*`, ~40 Gbps) when up; the OpenAI API is on
  port 8000 of the head. Head/worker IPs derive from the inventory hostvars
  (`ds4_role` — TB static 172.20.0.1/.2 by default); override with
  `-e ds4_head_ip=... -e ds4_worker_ip=...`. Start the head first, then the
  worker (`DS4_ROLE=head|worker`).

- **ds4-deepseek-v41-flash-tp** — DeepSeek **V4.1** Flash (Q2, 340.6 GiB incl.
  ~189 GiB of disk-resident FP8 Engram tables) from
  `antirez/deepseek-v4.1-flash-gguf`, 2-node **resident tensor parallel**
  (`--tensor-parallel --transport tcp`, 50/50 expert split, ~76 GiB per rank)
  on `docker.io/kyuz0/strix-halo-ds4-toolbox:ds4.1f-rocm10.0` — the kyuz0
  gfx1151 ROCm port; upstream ds4 still refuses V4.1 on ROCm. V4.1 on ROCm
  accepts **only** resident TP here: no `--layers` pipeline, no MTP/DSpark, no
  SSD-streaming TP. Q4 doesn't fit resident across two 128 GB nodes. The GGUF
  lands in `~/ds4.1` on both nodes (keep it on NVMe — Engram rows are read on
  demand): the **head** pulls it from HF once, the **worker** copies it from
  the head over TB4. Shares the `ds4_cluster` container name with the V4 track
  (only one fits in memory). TP channel on 8081 **over TB4 (required** — the
  play fails if `thunderbolt0`/`tb*` isn't up with its 172.20.0.x IP;
  `-e ds4_allow_lan_fallback=true` to waive), API on 8000.
  **Hands-off by default**: one run sets up the TB4 link, downloads + seeds,
  stops every other running container on both nodes (root + rootless, to free
  unified memory), drops the page cache, starts worker → head, waits for
  `/v1/models`, and runs a smoke test (`-e ds4_v41_launch=false` to only
  stage). No `-K` needed when `inventory/group_vars/rocm/become.yml` exists
  (see *Unattended sudo* below).

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
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen36-35b-ud-q8-k-xl-mtp-podman.yml
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen38-27b-q38rocm-podman.yml
ansible-playbook -i ansible/single-node/inventory/hosts ansible/single-node/qwen38-flash-next-halogen-podman.yml
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

# ds4 DeepSeek V4.1 Flash track (both nodes) — resident tensor parallel;
# one command: TB4 link, download + TB4 seed, stop other containers, launch, smoke test:
ansible-playbook -i ansible/multi-node/inventory/hosts ansible/multi-node/ds4-deepseek-v41-flash-tp.yml
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
│   │   ├── qwen36-35b-ud-q8-k-xl-mtp-podman.yml  Qwen3.6-35B-A3B MTP (Podman Vulkan, MTP built into GGUF)
│   │   ├── qwen38-27b-q38rocm-podman.yml  Qwen3.8-27B (julianmb q38rocm image, MTP speed profile)
│   │   ├── qwen38-flash-next-halogen-podman.yml  Qwen3.8-Flash-Next (halogen-flash-server, ROCm, prebuilt image)
│   │   ├── qwen38-flash-next-halogen-ablit-podman.yml  Qwen3.8-Flash-Next ABLITERATED (halogen + Ae55667 patch kit, gated)
│   │   ├── ornith15-ciru-halo-agent-vllm-podman.yml  Ornith1.5 Ciru Halo Agent (Ciru vLLM/ROCm + DFlash2, image built here)
│   │   ├── gemma-4-26b-a4b-ud-q8-k-xl-podman.yml  Gemma 4 26B A4B (Podman Vulkan + vision)
│   │   ├── containerfiles/        Containerfiles for built-from-source tracks
│   │   │   ├── ornith15-ciru-halo-agent-vllm.Containerfile
│   │   ├── tasks/                 Shared task files included by the tracks above
│   │   │   ├── podman-models-dir.yml            models dir + ownership
│   │   │   ├── hf-download-files.yml            HF download loop (skip if present, optional rename)
│   │   │   ├── podman-build-image.yml           podman build from a Containerfile (skip if tag exists)
│   │   │   ├── podman-remove-container.yml      podman rm -f before (re)launch
│   │   │   ├── podman-check-running.yml         start result + running check
│   │   │   ├── podman-wait-health.yml           sleep + poll /health
│   │   │   └── podman-render-launch-artifacts.yml  launch script + opencode config render
│   │   ├── inventory/
│   │   │   ├── hosts              single-node inventory (vulkan/rocm → aiservers)
│   │   │   ├── hosts.example      sample multi-machine inventory
│   │   │   └── group_vars/all.yml placeholder — empty; tracks define vars inline
│   │   ├── templates/             Jinja templates (rendered by each track)
│   │   │   ├── scripts/           Launch script templates
│   │   │   │   ├── qwen36-35b-ud-q8-k-xl-mtp-start.sh.j2   Qwen3.6-35B Vulkan launch (MTP built into GGUF)
│   │   │   │   ├── qwen38-27b-q38rocm-start.sh.j2   Qwen3.8-27B q38rocm launch (prebuilt image, speed profile)
│   │   │   │   ├── gemma-4-26b-a4b-ud-q8-k-xl-start.sh.j2   Gemma 4 Vulkan launch (model + mmproj)
│   │   │   │   ├── qwen38-flash-next-halogen-start.sh.j2   Flash-Next halogen launch (prebuilt ROCm image)
│   │   │   │   ├── qwen38-flash-next-halogen-ablit-start.sh.j2   Flash-Next halogen ABLITERATED launch (patched base + overlay)
│   │   │   │   └── ornith15-ciru-halo-agent-vllm-start.sh.j2   Ciru Halo Agent launch (built vLLM/ROCm image)
│   │   │   │   ├── opencode-configs/  OpenCode agent JSON config templates
│   │   │   │   │   ├── opencode-qwen36-35b-ud-q8-k-xl-mtp-podman.json.j2
│   │   │   │   │   ├── opencode-qwen38-27b-q38rocm-podman.json.j2
│   │   │   │   │   ├── opencode-gemma-4-26b-a4b-ud-q8-k-xl-podman.json.j2
│   │   │   │   │   ├── opencode-qwen38-flash-next-halogen-podman.json.j2
│   │   │   │   │   ├── opencode-qwen38-flash-next-halogen-ablit-podman.json.j2
│   │   │   │   │   └── opencode-ornith15-ciru-halo-agent-vllm-podman.json.j2
│   │   └── rendered/              Rendered output (gitignored)
│   │       ├── scripts/           Rendered launch scripts
│   │       └── opencode-configs/  Rendered opencode configs
│   │
│   ├── multi-node/                Multi-node cluster tracks
│   │   ├── bootstrap.yml          ORCHESTRATOR: shared/ setup + multi-node playbooks
│   │   ├── summary.yml            final per-host completion summary           [summary]
│   │   ├── setup-thunderbolt-net.yml  TB4 node-to-node cluster link (multi-node only) + tb-net-diag
│   │   ├── vllm-rccl-moe.yml          Multi-model vLLM + RCCL MoE track, TB link preferred
│   │   ├── ds4-deepseek-v4-flash-mtp.yml  2-node ds4 DeepSeek V4 Flash (pipeline parallel + MTP), TB link preferred
│   │   ├── ds4-deepseek-v41-flash-tp.yml  2-node ds4 DeepSeek V4.1 Flash Q2 (resident tensor parallel), TB4 required
│   │   ├── inventory/
│   │   │   ├── hosts              multi-node inventory (halo0 head + halo1 worker, SSH; rocm → aiservers, multinode for TB)
│   │   │   └── group_vars/all.yml placeholder — empty; tracks define vars inline
│   │   ├── templates/             Jinja templates
│   │   │   ├── vllm-rccl-moe-start.sh.j2          vLLM MoE cluster launch (head/worker)
│   │   │   ├── opencode-vllm-rccl-moe.json.j2    opencode config (active profile)
│   │   │   ├── ds4-deepseek-v4-flash-mtp-start.sh.j2  ds4 cluster launch (DS4_ROLE=head|worker)
│   │   │   ├── opencode-ds4-deepseek-v4-flash-mtp.json.j2   opencode config
│   │   │   ├── ds4-deepseek-v41-flash-tp-start.sh.j2  ds4 V4.1 TP launch (DS4_ROLE=worker first, then head)
│   │   │   ├── opencode-ds4-deepseek-v41-flash-tp.json.j2   opencode config
│   │   │   └── tb-net-diag.sh.j2                   TB4 link diagnostics (iperf3 server/client/ping)
│   │   └── rendered/              Rendered output (gitignored)
│   │       ├── scripts/           Rendered launch scripts
│   │       └── opencode-configs/  Rendered opencode configs
│   │
│   └── secrets/                   Secret files (gitignored)
│       └── hf_token.txt           HuggingFace token for gated model downloads
```

## Track Details

### Qwen36-35B-A3B (UD-Q8_K_XL) — Podman Vulkan

- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan-v0.7.6.1`
- **Model**: Qwen3.6-35B-A3B UD-Q8_K_XL (~38.5 GB)
- **Context**: 262k (native ceiling)
- **Port**: 8080
- **Backend**: Vulkan/RADV

### Qwen36-35B-A3B MTP (UD-Q8_K_XL) — Podman Vulkan + MTP

- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan-v0.7.6.1`
- **Model**: `Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf` from `unsloth/Qwen3.6-35B-A3B-MTP-GGUF`
  (same file name/quant, different repo)
- **MTP**: **built into the model** — `--spec-type draft-mtp --spec-draft-n-max 2`,
  no separate `--model-draft` drafter file. Loading this GGUF without
  `--spec-type draft-mtp` fails to load, per the model card.
- **Context**: 262144 (native ceiling), `--parallel 1` (model card: `-np > 1`
  not yet supported with MTP)
- **Port**: 8080 (shared with the other Podman tracks — one server at a time)
- **Backend**: Vulkan/RADV
- **GPU layers**: `-ngl 99` (not 999, per the model card's own quickstart), `-fa on`

### Qwen38-27B (UD-Q4_K_XL) — Podman Vulkan + MTP

- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan-v0.7.6.1`
- **Model**: Qwen3.8-27B UD-Q4_K_XL (`Qwen3.8-27B-UD-Q4_K_XL.gguf`)
- **Drafter**: `MTP/mtp-Qwen3.8-27B-Q4_0.gguf`, passed as `--model-draft`
  (`draft-mtp` is only auto-discovered with `-hf`, never from a local `--model`)
- **Context**: 262144 (native ceiling), `--parallel 1` (single slot)
- **Port**: 8080
- **Backend**: Vulkan/RADV
- **Speculation**: `--spec-type draft-mtp --spec-draft-n-max 3`, KV cache f16 (K+V)
- **Batching / loading**: `-b 2048`, `-ub 512`, `-fa on`, `--load-mode mmap`, `-ngl 999`

### Qwen38-27B (q38rocm) — Vulkan, prebuilt image, MTP speed profile

- **Image**: `ghcr.io/julianmb/q38rocm:1.5.3` — **pulled**, never built.
  The model author's own Strix-Halo-tuned serving stack; its `run_server.sh`
  auto-detects Vulkan0 (Mesa RADV Wave64 + KHR_coopmat) vs ROCm0.
- **Model**: `Qwen3.8-27B-ROCmFP4-FAST.gguf` from
  `julianmb/Qwen-3.8-27B-ROCmFP4-FAST-GGUF` (~13.55 GiB, 4.26 bpw). The
  MTP draft heads are built into the model — the engine creates the draft
  context from the same file, so there is no separate drafter GGUF.
- **Profile**: `speed` — ctx 131072, MTP on, KV `q8_0`/`turbo4`, RAM prompt
  caching on, temp 0.
- **Speculation**: `DRAFT_N=3` (measured on halo1: n=3 beat n=4/n=2 —
  ~24.8 t/s decode, ~50% MTP acceptance on prose).
- **Port**: 8080
- **Backend**: Vulkan/RADV (Wave64 cooperative matrices)
- **Stability**: long-context prefill needs a 126 GiB TTM limit
  (`ttm.pages_limit=33030144`); at the old 124 GiB a 45k-token prefill
  tripped `Fence fallback timer expired on ring comp_1.0.1`. Set via the
  shared `set-grub-ttm.yml` / `set-limine-ttm.yml` playbooks.

### Qwen38-Flash-Next AP (Q5_K_XL) — Podman Vulkan + image input

- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan-v0.7.6.1`
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

### Qwen38-Flash-Next (halogen) — Podman ROCm + image input, prebuilt halogen-flash-server

- **Image**: `ghcr.io/peonist-ai/halogen-flash-server:0.13.4` — **pulled** with
  `--pull=newer`, never built (closed-source, purpose-built ROCm engine;
  `--device=/dev/kfd --device=/dev/dri --group-add keep-groups --ipc=host
  --ulimit memlock=-1:-1` per the upstream quickstart, no `--privileged`).
- **Weights**: `peonist-ai/halogen-qwen3.8-flash-next` (HF, ~118 GiB, `.hgn`
  format — loadable only by halogen, not transformers/vLLM/llama.cpp). The track
  downloads `qwen38-flash-next-w4b.hgn` (115.55 GiB checkpoint, skip sentinel),
  `qwen38-flash-next-w4b.overlay.hgn` (2.40 GiB quality sidecar, auto-loaded
  beside the checkpoint), `qwen38-flash-next-vision.hgn` (0.84 GiB vision
  tower, enabled via `HALOGEN_VISION_TOWER=/models/qwen38-flash-next-vision.hgn`
  for image input), and `tokenizer/` into a dedicated `~/halogen-models`
  dir bind-mounted at `/models:ro`. Left on HF: the speed overlay (2.31 GiB)
  and the MTP draft head (BYO-GGUF path only).
- **Context**: 262144 (HALOGEN_CTX default)
- **Port**: 8731 (`/v1/*` + `/v1/responses` + `/health`) — the only single-node
  track off 8080; it targets the `rocm` inventory group
- **Backend**: ROCm gfx1151 (native kfd access, keep-groups)
- **Sampling**: greedy by default; the model card's thinking-mode settings are
  `HALOGEN_TEMPERATURE=1.0 HALOGEN_TOP_P=0.95 HALOGEN_TOP_K=20` (commented env
  block in the launch script)
- **Wait**: the ~118 GiB cold load into the GPU pool is slow — the playbook
  polls `/health` for up to ~10 min (`podman_health_retries: 120`), and the
  launch script for up to ~20 min.
- **Claimed** (upstream README, not independently verified here): ~4x faster
  end-to-end than EngramHalo.cpp / ROCmFP4 / CIRU at 5.53 bpw

### Ornith1.5 Ciru Halo Agent (vLLM/ROCm + DFlash2) — Podman + image input

- **Image**: `localhost/ornith15-ciru-halo-agent-vllm:1.0.2` — **built here**
  (Ciru publishes no container image). The Containerfile wraps the repo's
  bundled runtime installer: Ubuntu 24.04 + apt prereqs + uv +
  `runtime/INSTALL-ORNITH-RUNTIME.sh` → `/opt/ciru/installed-runtime`
  (pinned vLLM `0.1.0rc2.dev9+rocm100`, AITER, PyTorch 2.13 rocm10.0.0,
  ROCm SDK 10.0.0, Python 3.14). Stock `pip install vllm` cannot serve
  these weights.
- **Weights**: `jcbtc/Ornith1.5-Ciru-Halo-Agent-vllm-strix-halo` (HF,
  ~24.3 GB assets) downloaded to `~/ciru-halo-agent`; the `bundle/` dir
  (packed IU4 checkpoint + DFlash2 drafter + native BF16 vision tensors +
  serve scripts) is bind-mounted at `/bundle` **read-write** (the server
  needs `bundle/cache` writable). `ORNITH_RUNTIME_ROOT` points the launcher
  at the baked runtime.
- **Serve**: `bundle/serve-vision.sh` (vision ON by default — one image per
  request, 1,048,576-pixel budget, ≤8 active requests; no `mmproj` needed,
  the projector ships inside the checkpoint) or `bundle/serve.sh`
  (`vision_enabled: false`, text-only).
- **Context**: 262,144 tokens/request | 8 active sequences | 44 GiB shared
  KV/state pool | prefix caching with recurrent-state reuse (subsequent
  agents sharing a history load faster).
- **Speculation**: adaptive DFlash2 (15/7/off under 32K computed tokens;
  7-token drafting at C2–8).
- **Port**: 8741 (`/v1/*` + `/health`), model id `ciru-halo-agent`;
  targets the `rocm` inventory group.
- **Memory**: ~100 GB budget loaded (recorded whole-host peak 95.35 GB on
  128 GB Strix Halo) — one server at a time.
- **Claimed** (model card, AMD-sponsored build): ~178 tok/s C1 coding
  decode, ~295 tok/s aggregate at C8, ~1,287 tok/s cold prefill at 64K /
  ~668 tok/s near 256K (~5 min to fill 256K), ~123 tok/s cached C1 decode
  at 63K history.

### Gemma 4 26B A4B (UD-Q8_K_XL) — Podman Vulkan + image input

- **Container**: `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan-v0.7.6.1`
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
  head only — `--mtp --mtp-model <file> --mtp-draft 1`. Optional: if the
  drafter isn't present, the launch script starts the coordinator without it
  (plain, non-speculative) rather than refusing to serve the 153 GB model.
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

### ds4-deepseek-v41-flash-tp (Multi-Node)

- **Engine**: `ds4` in the toolbox container `ds4_cluster` —
  `docker.io/kyuz0/strix-halo-ds4-toolbox:ds4.1f-rocm10.0` (kyuz0/ds4
  `main-gfx1151`, ROCm 10.0). The play asserts the binary carries the V4.1
  ROCm TP path before going further.
- **Model**: `DeepSeek-V4.1-Flash-Q2.gguf` (365,713,686,528 bytes; IQ2_XXS
  gate/up + Q2_K down routed experts, ~152 GiB main weights + ~189 GiB FP8
  Engram tables) at `~/ds4.1` on both nodes. The download runs async on both
  nodes in parallel and is size-verified afterwards.
- **Parallelism**: resident 2-rank tensor parallel —
  `--tensor-parallel --transport tcp`; worker `--role worker --coordinator
  <head_ip> 8081`, head `--role coordinator --listen <head_ip> 8081`. No
  `--layers`, MTP, DSpark, `--power` < 100, or `--ssd-streaming` (all rejected
  for V4.1 TP on ROCm).
- **Context**: 262144 (`-e ds4_ctx=...`; V4.1 accepts up to 1048576)
- **Ports**: 8081 (TP channel) + 8000 (OpenAI/Anthropic API on the head)
- **Launch order**: worker first, then head. Logs go to
  `~/ds4.1-logs/ds4-<role>.log` on each node. The worker runs the `ds4` CLI
  (`ds4-server` refuses `--role worker`); the head runs `ds4-server`.
- **Measured (halo0 + halo1, TB4)**: 80.56 GiB resident per rank (85 GiB
  GTT incl. KV/buffers at ctx 262144); ~1 min from launch to `/v1/models`;
  ~12.5–15 t/s decode; ~1.5 GiB of TB4 traffic per 400 generated tokens.
  Worker seeding over TB4 ran at ~1.15 GB/s (vs ~115 MB/s from HF).

## Model Downloads (hf CLI)

The bootstrap downloads GGUF weights via **hf** (the Hugging Face CLI), which
handles caching, resumption, and authentication natively. The llama track
**skips a download when its GGUF is already present** (`stat` check + `when:`
guard), so re-running the play or `--tags model` won't re-fetch an existing
model. The same commands work manually if you want to re-fetch a model outside
ansible:

```bash
# Qwen3.6-35B-A3B MTP (UD-Q8_K_XL, ~38.5 GB)
hf download unsloth/Qwen3.6-35B-A3B-MTP-GGUF Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf \
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

# Qwen3.8-Flash-Next halogen weights (W4B .hgn — ~118 GiB repo; this track
# pulls the checkpoint + quality overlay + vision tower + tokenizer)
hf download peonist-ai/halogen-qwen3.8-flash-next \
  --include qwen38-flash-next-w4b.hgn \
  --include qwen38-flash-next-w4b.overlay.hgn \
  --include qwen38-flash-next-vision.hgn \
  --include 'tokenizer/*' \
  --local-dir ~/halogen-models
                             # the halogen engine auto-discovers them at /models
                             # (bind mount of ~/halogen-models, read-only)

# Ornith1.5 Ciru Halo Agent (full repo: bundle/ weights + runtime/ installer,
# ~24.3 GB assets) — the whole repo is needed, not individual files
hf download jcbtc/Ornith1.5-Ciru-Halo-Agent-vllm-strix-halo \
  --local-dir ~/ciru-halo-agent
                             # bundle/ is bind-mounted at /bundle (RW) in the
                             # container built by this track
```

## Launch Scripts

After the bootstrap, the rendered launch scripts are in `~/scripts/` on the
target host. The rendered OpenCode configs land on the **controller** under
`ansible/<topology>/rendered/opencode-configs/` (e.g.
`ansible/single-node/rendered/opencode-configs/`).

### Single-Node Launch Example

```bash
# Qwen3.6-35B-A3B MTP (Podman Vulkan, MTP built into GGUF)
~/scripts/qwen36-35b-ud-q8-k-xl-mtp-start.sh

# Qwen3.8-27B (q38rocm image, MTP speed profile)
~/scripts/qwen38-27b-q38rocm-start.sh


# Qwen3.8-Flash-Next (halogen-flash-server, ROCm, prebuilt image)
~/scripts/qwen38-flash-next-halogen-start.sh

# Ornith1.5 Ciru Halo Agent (Ciru vLLM/ROCm + DFlash2, built image)
~/scripts/ornith15-ciru-halo-agent-vllm-start.sh

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
# The playbook downloads the ~153 GB main GGUF on both nodes and the ~3.6 GB
# MTP drafter on the head into ~/ds4 BEFORE this script runs; the container
# bind-mounts that same host path read-only, so the script only checks the
# files are present.
```

### Multi-Node Launch Example (ds4-deepseek-v41-flash-tp)

```bash
# Easiest — let ansible start worker -> head, wait, and smoke test:
ansible-playbook -i ansible/multi-node/inventory/hosts ansible/multi-node/ds4-deepseek-v41-flash-tp.yml

# Or by hand, with the script the playbook rendered on each node:
# halo1 (worker, FIRST):
DS4_ROLE=worker ~/scripts/ds4-deepseek-v41-flash-tp-start.sh
# halo0 (coordinator + API):
DS4_ROLE=head   ~/scripts/ds4-deepseek-v41-flash-tp-start.sh
# Logs: ~/ds4.1-logs/ds4-{worker,head}.log   API: http://<head_ip>:8000/v1
```

## OpenCode Agent Config

Each track renders its OpenCode config to the controller's
`ansible/<topology>/rendered/opencode-configs/` (the committed
`ansible/opencode-configs/` holds the multi-node ds4 fragment):

- **Podman tracks:**
  - `opencode-qwen36-35b-ud-q8-k-xl-mtp-podman.json` — provider `qwen36-35b-ud-q8-k-xl-mtp` → `http://<node_ip>:8080/v1`
  - `opencode-qwen38-27b-q38rocm-podman.json` — provider `qwen38-27b-q38rocm` → `http://<node_ip>:8080/v1`
  - `opencode-qwen38-flash-next-halogen-podman.json` — provider `qwen38-flash-next-halogen` → `http://<node_ip>:8731/v1`
  - `opencode-gemma-4-26b-a4b-ud-q8-k-xl-podman.json` — provider `gemma-4-26b-a4b-ud-q8-k-xl` → `http://<node_ip>:8080/v1`

- `opencode-vllm-rccl-moe.json` — `vllm-rccl-moe` provider (active profile) → `http://<head_ip>:8081/v1`
- `opencode-ds4-deepseek-v4-flash-mtp.json` — `ds4-deepseek-v4-flash-mtp` provider → `http://<head_ip>:8000/v1`
- `opencode-ds4-deepseek-v41-flash-tp.json` — `ds4-deepseek-v41-flash-tp` provider → `http://<head_ip>:8000/v1`

Each file is a standalone opencode config fragment (schema at
`https://opencode.ai/config.json`) declaring one provider on the
`@ai-sdk/openai-compatible` adapter. Merge the `provider` block(s) into
`~/.config/opencode/opencode.json`, or point `OPENCODE_CONFIG` at the file.

### Combining multiple providers (several models in one config)

The per-track configs each ship a single `provider`. To point the CLI at more
than one model at once, nest their `provider` blocks under one top-level
`provider:` map — each block is an independent provider keyed by its own name
(`qwen36-35b-...`, `ornith15-ciru-halo-agent-vllm`, `gemma-4-...`, etc.). See
the worked example at [`opencode-multi-provider.example.json`](ansible/opencode-configs/opencode-multi-provider.example.json). Key rules:

- one `provider` block per model track; the **key** is the provider name, the
  nested **models** entry is the model id you pass to the API.
- every provider needs its own `baseURL` (node IP + the track's port: `8080`
  for llama.cpp, `8731` for halogen, `8741` for this Ciru track) and `apiKey`.
- two tracks can share a port but still be distinct providers as long as their
  `baseURL`/`models` differ (they just can't run at the same time).

## Config Variables (inventory / env)

### Single-Node Tracks

All single-node playbooks are self-contained with inline vars — no group_vars needed.

### Multi-Node Tracks

- vllm-rccl-moe: `active_profile` (minimax-m2.7-awq-4bit | qwen3.5-122b-awq-4bit), `vllm_moe_head_ip` / `vllm_moe_worker_ip` (derived from `vllm_moe_role` hostvars; override via -e), `vllm_moe_port` (8081), `vllm_moe_tp_size` (2), `vllm_moe_gpu_util` (0.9)
- ds4-deepseek-v4-flash-mtp: `ds4_head_ip` / `ds4_worker_ip` (derived from `ds4_role` hostvars — TB static IP when the live TB link check says both ends are up, else LAN `ansible_host` on both; override via -e), `ds4_ctx` (262144), `ds4_mtp_draft` (1), `ds4_layers_head` (0:21), `ds4_layers_worker` (22:output), `ds4_pp_port` (8081), `ds4_api_port` (8000), `ds4_max_tokens` (65536)
- ds4-deepseek-v41-flash-tp: `ds4_head_ip` / `ds4_worker_ip` (same derivation), `ds4_ctx` (262144), `ds4_tp_port` (8081), `ds4_api_port` (8000), `ds4_max_tokens` (65536), `ds4_allow_lan_fallback` (false — the TP channel must ride TB4 172.20.0.x), `ds4_v41_launch` (true — stops ALL other running containers, root + rootless, drops the page cache, then starts worker → head + smoke test; false = stage only; bootstrap.yml passes false), `ds4_skip_tb_setup` (false — skip the imported setup-thunderbolt-net.yml), `ds4_seed_port` (8089, temporary head→worker copy over TB4), `ds4_health_retries` / `ds4_health_delay` (120 × 10s)
- setup-thunderbolt-net (multi-node): `tb_net_enabled` (true), `tb_net_cidr` (172.20.0.0/24), `tb_net_ip` / `tb_net_peer_ip` (per-host override), `tb_net_install_iperf` (true), `tb_net_iperf_test` (true), `tb_net_iperf_port` (5201), `tb_net_iperf_parallel` (4), `tb_net_iperf_time` (10)

### Scripts

Each single-node track renders one launch script to `~/scripts/<stem>-start.sh`.
The settings below are baked into the rendered script as plain shell variables
(`CONTAINER`, `PORT`, `MODEL`, `IMAGE`, `CTX`, ...); edit the file in place and
re-run it to change them.

- `qwen36-35b-ud-q8-k-xl-mtp-start.sh` (CONTAINER/PORT/MODEL/IMAGE/CTX/PARALLEL/BATCH/GPU_LAYERS/FLASH_ATTN/SPEC_TYPE/SPEC_DRAFT_N_MAX)
- `qwen38-27b-q38rocm-start.sh` (CONTAINER/PORT/MODEL/IMAGE/PROFILE/DRAFT_N — pulls the prebuilt q38rocm image if missing, passes the model path as the run_server.sh arg)
- `gemma-4-26b-a4b-ud-q8-k-xl-start.sh` (CONTAINER/PORT/MODEL/MMPROJ/IMAGE/CTX/BATCH/GPU_LAYERS)
- `qwen38-flash-next-halogen-start.sh` (CONTAINER/PORT/CHECKPOINT/OVERLAY/VISION/IMAGE/CTX — pulls the prebuilt image if missing; ROCm flags per the upstream quickstart, ~20 min health wait)
- `VLLM_RCCL_MOE_ROLE` (head|worker) — multi-node only, still env-set

## Strix Halo Optimization Notes

The launch profiles are tuned from the Strix Halo benchmarking thread
(`community.frame.work/t/72521`, user lhl — Linux 6.15.5+, TheRock ROCm
nightlies, latest llama.cpp from source):

- **ROCm/HIP dominates prompt processing** on gfx1151 — 4.7× faster and 65%
  less energy than Vulkan. We build llama.cpp **ROCm-only** (HIP graphs
  enabled).
- **MoE models need 2^n batching** — `batch=256` for qwen36-35b-ud-q8-k-xl-mtp (38.5 GB, fits KV cache).
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
`--usecase=rocm --no-dkms` — *not* the Ubuntu `rocm` package (7.1.0). The
single-node Podman tracks only need podman + recent Mesa (Vulkan); ROCm is
needed for the multi-node vllm-rccl-moe / ds4-deepseek-v4-flash-mtp tracks.

**Podman tracks:** The new `*-podman.yml` playbooks are **self-contained** — all
vars are defined inline (no dependency on `group_vars/all.yml`), they skip the
local llama.cpp build step, and use the official `ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan-v0.7.6.1`
Vulkan container instead. MTP speculation args are baked into both the container
`run` command and the rendered launch script.

**Architecture:** the ansible playbook is **bootstrap-only**. It installs
packages, sets GRUB, creates containers/toolboxes, builds llama.cpp, and
downloads model weights. It NEVER launches servers.

## Unattended sudo (multi-node)

To run the multi-node playbooks without `-K`, drop the nodes' sudo password
into a **gitignored** group_vars file that Ansible loads automatically:

```bash
mkdir -p ansible/multi-node/inventory/group_vars/rocm
printf 'ansible_become_password: "%s"\n' '<sudo password>' \
  > ansible/multi-node/inventory/group_vars/rocm/become.yml
chmod 600 ansible/multi-node/inventory/group_vars/rocm/become.yml
```

`.gitignore` covers `ansible/*/inventory/group_vars/*/become.yml` (and
`ansible/secrets/*`). For encryption at rest, `ansible-vault encrypt` the file
and run with `--vault-password-file`. Without the file, `-K` works as before.

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
   #24872; default 1 on UMA since). No current track exposes this as a
   playbook var (the ROCmFP4 track that did was retired) — set it via
   `podman run -e GGML_VK_MAX_NODES_PER_SUBMIT=1` directly if needed.
3. **Smaller ubatches** — lower `--ubatch-size` (e.g. 512 or 128) shrinks the
   work per submit; costs prefill speed.
4. **MTP off for long prompts** — UD-Q4_K_XL / UD-Q8_K_XL-MTP tracks: drop
   `--spec-type draft-mtp` (and `--model-draft`/`--mtp-model` if present)
   from the start script.

**Evidence to capture if it persists** — `journalctl -k | grep -E 'amdgpu.*(timeout|reset)'`,
`podman logs <container>`, and the exact prompt length / argv at which it dies;
that distinguishes the watchdog class above from the separate
checkpoint/`get_tensor` DeviceLost class (which happens with prompt-cache
checkpoints armed).
