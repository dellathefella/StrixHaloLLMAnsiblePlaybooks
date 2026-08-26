# ROCm / DS4 + Qwen + llama.cpp install — Ryzen AI Max (HP Z2 G1a)

Organized workspace for bootstrapping AMD ROCm inference on the Ryzen AI Max
"Strix Halo" APU, on **HP Z2 G1a** workstations (2.5Gbe NICs — no 10Gbps
requirement). Ubuntu/Debian only. Three tracks, driven by **per-track ansible
playbooks** under `ansible/` (an orchestrator, `bootstrap.yml`, runs them in
order; any track file can also run standalone):

1. **DS4** — DeepSeek V4 Flash via the `ds4` engine (`antirez/ds4`, Dwarf Star
   4, ROCm kernel-optimized for DeepSeek V4 Flash). **Single-node is the
   default** — IQ2_XXS imatrix quant (~80.8 GB) at **126k context** on one
   128 GB node, per AMD's playbook
   (`developer.amd.com/playbooks/deepseek-v4-flash-ds4/`). Multi-node (optional)
   uses the `ds4-toolbox` distrobox pipeline (Q4KExperts ~153GB, layers
   0:21 / 22:output across 2 nodes).
2. **Qwen RCCL cluster** — Qwen3.5-397B-A17B-GPTQ-Int4 across two nodes via
   vLLM + Ray + RCCL, context pushed to 65536 (guide default is 32768).
3. **llama.cpp** — **Qwen3.6-35B-A3B** (8-bit UD-Q8_K_XL, 38.5 GB) served by
   the **latest llama.cpp built from source** with the **ROCm/HIP** backend.
   Also includes: **Step 3.5 Flash** (ubergarm smol-IQ3_KS, ~81.5 GB, 26B total /
   11B active MoE, 256K native context), and **Ornith-1.5-35B-A3B** (Q8_0,
   ~37.8 GB, 35B total / ~3B active MoE — agentic coding, vision-language).

The qwen38 (Qwen3.8-27B) and ds4fa (Lucebox ROCmFPX) tracks were **removed**
per user request (qwen38 too slow; ds4fa failed with an engine/model mismatch
— `token_embd.weight q6_k vs expected f16`), and single-node DS4 **reverted to
the working plain DS4 implementation** (126k ctx, AMD guide).

## Strix Halo optimization rationale (Frame.work LLM bench thread)

The launch profiles are tuned from the Strix Halo benchmarking thread
(`community.frame.work/t/72521`, user lhl — Linux 6.15.5+, TheRock ROCm
nightlies, latest llama.cpp from source):

- **ROCm/HIP dominates prompt processing** on gfx1151 — 4.7× faster and 65%
  less energy than Vulkan for Step 3.5 Flash (same MoE architecture). We build
  llama.cpp **ROCm-only** (HIP graphs enabled), which avoids the old ROCm
  regression (fixed by TheRock/nightly ROCm) and gives the best overall
  throughput.
- **MoE models need 2^n batching** — `batch=256` for qwen36 (38.5 GB, fits KV cache).
- **`--flash-attn on`** and **`--no-mmap`** (weights fully in the unified
  128 GB shared pool).
- **Token generation is memory-bandwidth bound** (~215 GB/s). Qwen3.6 ~3B active
  ≈ 3 GB/token ≈ 65-70 t/s at 8-bit UD-Q8_K_XL. Step 3.5 Flash ~11B active
  ≈ 11 GB/token ≈ 30-48 t/s at smol-IQ3_KS. Both roughly **2×** the BF16 speeds,
  with near-lossless quality.

**Network note:** host NICs are 2.5Gbe (HP Z2 G1a), below the guide's 10Gbps;
tensor-parallel KV exchange is the bottleneck. The playbook warns on this but
treats 2.5Gbe as acceptable — there is no 10Gbps requirement.

**TTM:** the shared-memory pool is configured by the GRUB kernel args
(`ttm.pages_limit=32505856 ttm.page_pool_size=32505856` ⇒ ~124GB). **No
`amd-ttm --set` is used** anywhere in the ansible — set BIOS UMA VRAM to
Auto/minimum, append the GRUB args, reboot.

**ROCm version:** PLAY 1 installs **ROCm 7.2.3** via AMD's `repo.radeon.com`
(noble packages, used on this resolute/26.04 host) — *not* the Ubuntu `rocm`
package (7.1.0). ROCm is needed for DS4 and qwen36 tracks.

**Architecture:** the ansible playbook is **bootstrap-only**. It installs
packages, sets GRUB, creates containers/toolboxes, builds llama.cpp, and
downloads model weights. It NEVER launches servers. On completion it drops
**local copies** of the launch scripts into `scripts/` and the pi agent configs
into `pi-configs/` — you run/merge them when ready.

**Local scripts:** only the **DS4** bootstrap is kept as a local script
(`scripts/ds4-setup.sh` — DS4 itself only); everything else (base, Qwen RCCL,
llama.cpp) is done via ansible. `scripts/install-pi.sh` is the **local pi
install** (pi + the plugins present on this system) for this controller machine.
qwen36 uses the llama.cpp build.

## Layout

```
├── README.md                      this file
├── hf_token.txt                   HuggingFace token (gated model downloads)
├── reference/
│   ├── playbook.txt               AMD ds4 playbook (text extract)
│   └── notes.md                   pi local-server / DS4 config snippets
├── ansible/
│   ├── bootstrap.yml              ORCHESTRATOR: imports the per-track playbooks
│   ├── base.yml                   base preflight, packages, toolchain, GRUB   [base]
│   ├── ds4.yml                    DS4: single-node IQ2_XXS default + multi-node [ds4]
│   ├── qwen36.yml                 Qwen3.6-35B-A3B (ROCm-built llama.cpp,        [llama]
│   │                              UD-Q8_K_XL, ~38.5 GB)

│   ├── tasks/                       shared task files (all llama tracks call)
│   │   └── rocm-build-deps.yml    ROCm runtime + dev packages                 [packages,rocm]
│   ├── qwen-rccl.yml                   Qwen RCCL cluster (vLLM + Ray + RCCL)       [qwen-rccl]
│   ├── summary.yml                final per-host completion summary           [summary]
│   ├── templates/                 Jinja templates (rendered by each track playbook)
│   │   ├── ds4-start.sh.j2        DS4 launch template (single + multi, role via env)
│   │   ├── qwen36-start.sh.j2     Qwen3.6-35B-A3B launch (ROCm, MoE batching)

│   │   ├── qwen-rccl-start.sh.j2       Qwen RCCL launch template
│   │   ├── pi-ds4.json.j2         pi agent config (DS4 single-node default)
│   │   ├── pi-qwen36.json.j2      pi agent config (Qwen3.6)

│   │   └── pi-qwen-rccl.json.j2        pi agent config (Qwen RCCL)
│   └── inventory/
│       ├── hosts                  your real inventory (local ds4_single + llama test)
│       └── hosts.example          sample inventory + vars for all tracks
├── scripts/                       rendered launch scripts (dropped locally by bootstrap)
│   ├── ds4-setup.sh               DS4 host bootstrap (DS4 itself only)
│   ├── install-pi.sh              local pi install (pi + plugins on this system)
│   ├── ds4-start.sh               rendered DS4 launch (DS4_ROLE=single|coordinator|worker)
│   ├── qwen36-start.sh            rendered Qwen3.6-35B-A3B launch

│   └── qwen-rccl-start.sh              rendered Qwen RCCL launch (role via env)
└── pi-configs/                    rendered pi agent configs (dropped locally)
    ├── pi-ds4.json                merge into ~/.pi/agent/models.json
    ├── pi-qwen36.json

    └── pi-qwen-rccl.json
```

## Quick start

### Local machine — pi + DS4 toolchain installer
```bash
./scripts/install-pi.sh
# installs pi + the pi plugins present on this system (pi-web-access, rpiv-ask-user-question,
# pi-background-tasks, pi-permission-system, pi-ds4)
# and merges the pi provider configs from pi-configs/ into ~/.pi/agent/models.json
```

### Ansible route (Ubuntu nodes) — per-track playbooks + orchestrator
```bash
cp ansible/inventory/hosts.example ansible/inventory/hosts   # edit groups/vars
# Full bootstrap (base + whichever groups are populated):
ansible-playbook -i ansible/inventory/hosts ansible/bootstrap.yml
# Re-test a track on an already-provisioned host (skip base):
ansible-playbook -i ansible/inventory/hosts ansible/bootstrap.yml --skip-tags base
# Only one track (tags select tracks; imports are static):
ansible-playbook -i ansible/inventory/hosts ansible/bootstrap.yml --tags llama
# Any track file can also run standalone:
ansible-playbook -i ansible/inventory/hosts ansible/ds4.yml        # DS4 (single + multi)
ansible-playbook -i ansible/inventory/hosts ansible/qwen36.yml     # Qwen3.6-35B-A3B (llama.cpp)
ansible-playbook -i ansible/inventory/hosts ansible/qwen-rccl.yml  # Qwen RCCL cluster
```

### Local run — `connection=local` + password-fed `become` (native, no NOPASSWD)
Running the playbook against the controller itself uses
`ansible_connection=local` with `become` fed the sudo password interactively
via `-K`. This works **natively** on this machine — no temporary NOPASSWD
sudoers grant needed. Two gotchas were solved:

1. **sudo-rs prompt mismatch.** Ubuntu 26.04's default sudo is `sudo-rs`
   (Rust rewrite), which formats the `-p "[sudo via ansible, key=…] password:"`
   prompt as `[sudo: …] Password:` (with a `[sudo: ` prefix). ansible's
   become only matches a prompt *starting* with `[sudo via ansible, key=…]
   password:`, so it never detects it → `Timed out waiting for become success
   or become password prompt`. **Fix:** point become at the classic C sudo,
   which writes the `-p` prompt plain. On this box the classic binary is
   `/usr/bin/sudo.ws` (Ubuntu's `.ws`-suffixed rename when sudo-rs takes the
   default), so the inventory sets:
   ```yaml
   localhost ansible_connection=local ansible_user=jdella   ansible_become_exe=/usr/bin/sudo.ws
   ```
   (Classic sudo is the `sudo` package, `sudo.ws`; sudo-rs is
   `/usr/lib/cargo/bin/sudo` via the `update-alternatives` `sudo` link.)

2. **Skip `gather_facts` on local runs.** With `connection=local`, facts are
   unnecessary — `processor_nproc` has a `| default(16)` and home paths come
   from `ansible_user`. PLAYS 4/5/6 set `gather_facts: no` (cluster PLAYS
   1/2/3 keep it). This also skips sudo at the very first task.

**Run it yourself (prompts once for the sudo password):**
```bash
ansible-playbook -i ansible/inventory/hosts ansible/bootstrap.yml --skip-tags base -K
```

### Example runs (copy-paste workflows)
All commands run from the repo root and assume `hosts` is already populated.
Each prompts once for the sudo password (`-K`); on an already-provisioned host
add `--skip-tags base` to skip the base play.

**1. DS4 single-node (default) — IQ2_XXS at 126k ctx on this controller**
```bash
# 0) syntax check (no sudo needed)
ansible-playbook -i ansible/inventory/hosts ansible/ds4.yml --syntax-check
# 1) dry-run / check mode (applies nothing; prompts sudo once)
ansible-playbook -i ansible/inventory/hosts ansible/ds4.yml --check -K
# 2) full track: toolbox + IQ2_XXS model (~80.8 GB)
ansible-playbook -i ansible/inventory/hosts ansible/ds4.yml -K
# 3) re-test a provisioned host, skip the big model downloads
ansible-playbook -i ansible/inventory/hosts ansible/ds4.yml --skip-tags model -K
# 4) launch (endpoint http://127.0.0.1:8000/v1)
./scripts/ds4-start.sh
```

**2. Multi-node DS4 (optional) — two machines**
```bash
# machine 1 + 2 (edit hosts.example first: ds4_mode=multi, ds4_coord_ip, ds4_download_multi=1)
ansible-playbook -i ansible/inventory/hosts ansible/ds4.yml -K
# machine 1 (coordinator, layers 0:21)
DS4_ROLE=coordinator ./scripts/ds4-start.sh
# machine 2 (worker, layers 22:output)
DS4_ROLE=worker      ./scripts/ds4-start.sh
```

**3. Qwen RCCL cluster (Qwen3.5-397B) — two machines**
```bash
# machine 1 + 2 (edit hosts.example first: qwen_head_ip/qwen_worker_ip)
ansible-playbook -i ansible/inventory/hosts ansible/qwen-rccl.yml -K
# machine 1 (Ray head + vLLM)
QWEN_ROLE=head   ./scripts/qwen-rccl-start.sh
# machine 2 (Ray worker)
QWEN_ROLE=worker ./scripts/qwen-rccl-start.sh
# endpoint http://<head_ip>:7000/v1
```

**4. llama.cpp track (Qwen3.6-35B-A3B)**
```bash
ansible-playbook -i ansible/inventory/hosts ansible/qwen36.yml -K
./scripts/qwen36-start.sh        # Qwen3.6-35B-A3B -> http://127.0.0.1:8081/v1
# override ctx for Qwen3.6, e.g.:
QWEN36_CTX=262144 ./scripts/qwen36-start.sh   # Qwen3.6 native 256k (keep >=128k)
```

**5. Everything at once (full bootstrap)**
```bash
ansible-playbook -i ansible/inventory/hosts ansible/bootstrap.yml -K
# then, per track:
./scripts/ds4-start.sh
./scripts/qwen36-start.sh
./scripts/qwen-rccl-start.sh
```

**Common flags** — `--tags <track>` runs one track (`base`, `ds4`, `qwen`,
`llama`, `qwen-rccl`); `--skip-tags base` skips the base play; `--tags model`
re-runs just downloads; `--check` dry-runs. Within the llama track, per-model
tag `qwen36` runs only that model's download + launch-script/pi-config
render, and `--skip-tags qwen36` skips just that model.
A track file can be run standalone (no need to go through the orchestrator).

### DS4 single-node local bootstrap (the one kept local script)
```bash
./scripts/ds4-setup.sh          # GRUB/TTM(args), ds4 distrobox, model downloads
```

## Model downloads (aria2c — much faster)

The bootstrap downloads GGUF weights via **aria2c** with 16 parallel
connections (`-x 16 -s 16`), which saturates a fast link far better than
the single-stream `curl` or `hf download` (HF's Xet client also silently
hangs on this system). The llama track **skips a download when its GGUF is
already present** (`stat` check + `when:` guard), so re-running the play or
`--tags model` won't re-fetch an existing model. The same commands work
manually if you want to re-fetch a model outside ansible:

```bash
# Qwen3.6-35B-A3B (8-bit UD-Q8_K_XL, ~38.5 GB)
cd ~/.local/share/llama-models && \
  aria2c -x 16 -s 16 --file-allocation=none --auto-file-renaming=false --continue=true \
    -o Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf \
    "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf"

# DS4 single-node IQ2_XXS (~80.8 GB) into ~/ds4
cd ~/ds4 && \
  aria2c -x 16 -s 16 --file-allocation=none --auto-file-renaming=false --continue=true \
    -o DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf \
    "https://huggingface.co/antirez/deepseek-v4-gguf/resolve/main/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf"
```

Verify integrity after download (HF publishes sha256, not md5):
```bash
sha256sum <file>.gguf   # compare against the repo's file listing
```
```bash
sha256sum <file>.gguf   # compare against the repo's file listing
```

## Launch later (bootstrap never runs servers)

After the bootstrap + REBOOT (if GRUB changed), copy the rendered launch
script to each node and run it:

### DS4 single-node (default) — IQ2_XXS at 126k ctx
```bash
./scripts/ds4-start.sh                        # DS4_ROLE=single, IQ2_XXS, ctx 126k, port 8000
DS4_ROLE=single DS4_CTX_SINGLE=131072 ./scripts/ds4-start.sh   # raise ctx if headroom
DS4_HOST=0.0.0.0 ./scripts/ds4-start.sh       # expose on LAN (via ds4_host)
```
The script runs `ds4-server` inside the `ds4-rocm-7.14` distrobox, IQ2_XXS at
126k context (AMD guide default for a 128 GB node; shared pool ≥110 GB). MTP
speculative decoding is **disabled by default** (stability); enable with
`DS4_USE_MTP=1`. OpenAI endpoint: `http://127.0.0.1:8000/v1`.

### DS4 multi-node (both nodes must use the same ctx + model)
```bash
# Machine 1 (coordinator, layers 0:21):
DS4_ROLE=coordinator ./scripts/ds4-start.sh
# Machine 2 (worker, layers 22:output):
DS4_ROLE=worker      ./scripts/ds4-start.sh
```
MTP is disabled by default (`DS4_USE_MTP=1` to enable).

### llama.cpp — Qwen3.6-35B-A3B (ROCm/HIP)
```bash
./scripts/qwen36-start.sh        # ctx 131072 (keep >=128k for thinking)
```
Uses the ROCm-built `llama-server` (HIP graphs, 4.7× faster PP than
Vulkan), `--flash-attn on`, `--no-mmap` (full load into the unified shared
pool), `--cache-ram 0` (prevents host/GPU memory competition on 128GB UMA),
`--n-gpu-layers 999`. Endpoint: `http://127.0.0.1:8081/v1` (qwen36). First request is shader-JIT slow;
decode is memory-bandwidth-bound.

Validated ROCm profile: batch=256 (qwen36, 38.5 GB — KV cache fits). ctx=131072, F16/F16 KV cache, 32 threads, 999 GPU layers.

**Note:** ubergarm's smol-IQ3_KS quant is 3 shards (~81.5 GB total) — llama.cpp
auto-detects remaining shards from `.index.json`. smol-IQ3_KS is a ~3.05 bpw
quant optimized for quality at the smallest practical size.

Runtime stability: ROCm 7.x on Strix Halo is stable for llama.cpp when built
with `-DGGML_HIP_GRAPHS=ON`. If you hit GPU hangs, try
`export HSA_FORCE_FINE_GRAIN_PCIE=1`.

### Qwen cluster (head first, then worker)
```bash
# Machine 1 (head — Ray head + vLLM server):
QWEN_ROLE=head   ./scripts/qwen-rccl-start.sh
# Machine 2 (worker — joins Ray):
QWEN_ROLE=worker ./scripts/qwen-rccl-start.sh
```
OpenAI endpoint: `http://<HEAD_IP>:7000/v1` (Auth: None). vLLM downloads
Qwen weights into the models dir on first serve.

## Output the rendered configs

The launch scripts and pi configs are **generated from templates** (not hand-kept
files). Source: `ansible/templates/*.j2` → rendered by the launch-render plays
(`qwen36.yml` play 2, `tags: [launch, llama]`) into:
- `scripts/qwen36-start.sh` ← `templates/qwen36-start.sh.j2`  (`tags: [launch, qwen36]`)
- `pi-configs/pi-qwen36.json` ← `templates/pi-qwen36.json.j2` (`tags: [launch, qwen36]`)

The DS4 + Qwen tracks render their own start scripts / pi configs the same way.

**Render + view the Qwen3.6 config** (download auto-skips since the GGUF is present):
```bash
ansible-playbook -i ansible/inventory/hosts ansible/qwen36.yml -K --tags qwen36
cat scripts/qwen36-start.sh    # launch script (ROCm0, port 8081)
cat pi-configs/pi-qwen36.json  # pi agent config
```

Per-model tags: `--tags qwen36` runs only the qwen36 download + render;
`--tags launch` runs the whole launch-render play (all llama scripts + pi configs). Each track file is fully
standalone — no need to go through the orchestrator. Once
rendered, `./scripts/install-pi.sh` merges `pi-configs/*` into
`~/.pi/agent/models.json`.

## pi agent config

The bootstrap drops pi agent configs into `pi-configs/`:
- `pi-ds4.json` — `ds4` provider → `http://127.0.0.1:8000/v1`, model `deepseek-v4-flash` (single-node IQ2_XXS).

- `pi-qwen36.json` — `qwen36` provider → `http://127.0.0.1:8081/v1`, model `qwen3.6-35b-a3b`.
- `pi-qwen-rccl.json` — `qwen-rccl` provider → `http://<head_ip>:7000/v1`, model `Qwen/Qwen3.5-397B-A17B-GPTQ-Int4`.

Merge the provider block(s) into `~/.pi/agent/models.json` (pi reloads it when
you open `/model`; no restart needed). `install-pi.sh` installs pi + the pi
plugins present on this system (pi-web-access, rpiv-ask-user-question,
pi-background-tasks, pi-permission-system, pi-ds4) and merges
the pi provider configs.

## Config variables (inventory / env)
- DS4 (single + multi): `ds4_mode` (single default), `ds4_ctx_single` (126000),
  `ds4_ctx` (262144 multi), `ds4_port` (8000), `ds4_host` (127.0.0.1),
  `ds4_coord_ip/port`, `ds4_download_single/multi/mtp` (model downloads per host)
- llama.cpp: `qwen36_ctx` (131072), `qwen36_port` (8081), `qwen36_host/device/batch/ubatch/flash_attn/mmap` (same defaults)
- Qwen: `qwen_head_ip`, `qwen_worker_ip`, `qwen_max_model_len` (default 65536),
  `qwen_tp_size` (default 2), `qwen_port`, `qwen_ifname`
- Scripts: `DS4_ROLE` (single|coordinator|worker), `DS4_USE_MTP`, `DS4_CTX_SINGLE`,
  `DS4_CTX`, `DS4_MODELS_DIR`, `DS4_HOST`; `QWEN36_*` (BIN/MODEL/CTX/PORT/HOST/DEVICE/BATCH/UBATCH/FA/MMAP/THREADS); `QWEN_ROLE`;
  `HF_TOKEN`
