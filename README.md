# ROCm / DS4 + Qwen + llama.cpp install — Ryzen AI Max (HP Z2 G1a)

Organized workspace for bootstrapping AMD ROCm inference on the Ryzen AI Max
"Strix Halo" APU, on **HP Z2 G1a** workstations (2.5Gbe NICs — no 10Gbps
requirement). Ubuntu/Debian only. Four tracks, driven by **per-track ansible
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
   the **latest llama.cpp built from source** with the **Vulkan (Mesa RADV)**
   backend. **Gemma 4 26B-A4B (27.6 GB) removed per user — Qwen3.6 covers the
   use case.** Also included: Gemma 4 E4B (4.8 GB, Q4_K_S, Q4 quant).
4. **Laguna S 2.1** — **Chadrock ROCmFP4 StrixKVSpine V4** quant (4.453 BPW,
   ~60.95 GB, AMD-optimized tensor protection for Strix Halo), served by the
   **Ciru ROCmFPX Runtime V3** (CIRR-ai/ROCmFPX fork — NOT stock upstream
   llama.cpp).

The qwen38 (Qwen3.8-27B) and ds4fa (Lucebox ROCmFPX) tracks were **removed**
per user request (qwen38 too slow; ds4fa failed with an engine/model mismatch
— `token_embd.weight q6_k vs expected f16`), and single-node DS4 **reverted to
the working plain DS4 implementation** (126k ctx, AMD guide).

## Strix Halo optimization rationale (Frame.work LLM bench thread)

The launch profiles are tuned from the Strix Halo benchmarking thread
(`community.frame.work/t/72521`, user lhl — Linux 6.15.5+, TheRock ROCm
nightlies, latest llama.cpp from source):

- **Vulkan (Mesa RADV) wins token generation and MoE prompt processing** on
  gfx1151. Official ROCm 7.x had a serious pp regression (Qwen3-8B BF16:
  ROCm 7.0.1 = 325 t/s vs 6.4.4 = 1132 t/s); TheRock/nightly ROCm fixes it.
  We therefore build llama.cpp **Vulkan-only** (RADV), which is proven on this
  box and avoids the ROCm regression entirely.
- **MoE models need 2^n batching on Vulkan** → `batch=256, ubatch=512`.
- **`--flash-attn on`** and **`--no-mmap`** (weights fully in the unified
  128 GB shared pool).
- **Token generation is memory-bandwidth bound** (~215 GB/s). 8-bit UD-Q8_K_XL
  keeps active params small — Qwen3.6 ~3B active ≈ 3 GB/token ≈ 65-70 t/s.
  That's roughly **2×** the BF16
  speeds, with near-lossless quality.

**Network note:** host NICs are 2.5Gbe (HP Z2 G1a), below the guide's 10Gbps;
tensor-parallel KV exchange is the bottleneck. The playbook warns on this but
treats 2.5Gbe as acceptable — there is no 10Gbps requirement.

**TTM:** the shared-memory pool is configured by the GRUB kernel args
(`ttm.pages_limit=32505856 ttm.page_pool_size=32505856` ⇒ ~124GB). **No
`amd-ttm --set` is used** anywhere in the ansible — set BIOS UMA VRAM to
Auto/minimum, append the GRUB args, reboot.

**ROCm version:** PLAY 1 installs **ROCm 7.2.3** via AMD's `repo.radeon.com`
(noble packages, used on this resolute/26.04 host) — *not* the Ubuntu `rocm`
package (7.1.0). ROCm is needed for the DS4 track; the llama.cpp track uses
Vulkan (Mesa RADV) and doesn't need HIP.

**Architecture:** the ansible playbook is **bootstrap-only**. It installs
packages, sets GRUB, creates containers/toolboxes, builds llama.cpp, and
downloads model weights. It NEVER launches servers. On completion it drops
**local copies** of the launch scripts into `scripts/` and the pi agent configs
into `pi-configs/` — you run/merge them when ready.

**Local scripts:** only the **DS4** bootstrap is kept as a local script
(`scripts/ds4-setup.sh` — DS4 itself only); everything else (base, Qwen RCCL,
llama.cpp) is done via ansible. `scripts/install-pi.sh` is the **local pi
install** (pi + the plugins present on this system) for this controller machine.

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
│   ├── qwen-rccl.yml                   Qwen RCCL cluster (vLLM + Ray + RCCL)       [qwen-rccl]
│   ├── llama.yml                  Qwen3.6-35B-A3B + Gemma4-E4B (latest       [llama]
│   │                              llama.cpp source build, Vulkan/RADV)
│   ├── laguna.yml                 Laguna S 2.1 ROCmFP4 (Ciru ROCmFPX        [laguna]
│   │                              Runtime V3 fork — separate from upstream
│   │                              llama.cpp)
│   ├── summary.yml                final per-host completion summary           [summary]
│   ├── templates/                 Jinja templates (rendered by each track playbook)
│   │   ├── ds4-start.sh.j2        DS4 launch template (single + multi, role via env)
│   │   ├── qwen36-start.sh.j2     Qwen3.6-35B-A3B launch (Vulkan, MoE batching)
│   │   ├── qwen-rccl-start.sh.j2       Qwen RCCL launch template
│   │   ├── pi-ds4.json.j2         pi agent config (DS4 single-node default)
│   │   ├── pi-qwen36.json.j2      pi agent config (Qwen3.6)
│   │   ├── laguna-start.sh.j2          Laguna S 2.1 ROCmFP4 launch (ROCmFPX)
│   │   ├── pi-laguna.json.j2           pi agent config (Laguna S 2.1)
│   │   └── pi-qwen-rccl.json.j2        pi agent config (Qwen RCCL)
│   └── inventory/
│       ├── hosts                  your real inventory (local ds4_single + llama test)
│       └── hosts.example          sample inventory + vars for all tracks
├── scripts/                       rendered launch scripts (dropped locally by bootstrap)
│   ├── ds4-setup.sh               DS4 host bootstrap (DS4 itself only)
│   ├── install-pi.sh              local pi install (pi + plugins on this system)
│   ├── ds4-start.sh               rendered DS4 launch (DS4_ROLE=single|coordinator|worker)
│   ├── qwen36-start.sh            rendered Qwen3.6-35B-A3B launch
│   ├── laguna-start.sh            rendered Laguna S 2.1 ROCmFP4 launch
│   └── qwen-rccl-start.sh              rendered Qwen RCCL launch (role via env)
└── pi-configs/                    rendered pi agent configs (dropped locally)
    ├── pi-ds4.json                merge into ~/.pi/agent/models.json
    ├── pi-qwen36.json
    ├── pi-laguna.json
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
ansible-playbook -i ansible/inventory/hosts ansible/llama.yml      # Qwen3.6 + Gemma4-E4B
ansible-playbook -i ansible/inventory/hosts ansible/qwen-rccl.yml       # Qwen RCCL cluster
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

**4. llama.cpp track (Qwen3.6-35B-A3B 8-bit UD-Q8_K_XL + Gemma4-E4B Q4_K_S)**
```bash
ansible-playbook -i ansible/inventory/hosts ansible/llama.yml -K
./scripts/qwen36-start.sh     # Qwen3.6-35B-A3B -> http://127.0.0.1:8081/v1
./scripts/gemma-e4b-start.sh  # Gemma4-E4B Q4_K_S -> http://127.0.0.1:8083/v1
# override ctx for Qwen3.6, e.g.:
QWEN36_CTX=262144 ./scripts/qwen36-start.sh   # Qwen3.6 native 256k (keep >=128k)
```

**5. Laguna S 2.1 ROCmFP4 (Ciru ROCmFPX Runtime V3 — separate from llama.cpp)**
```bash
ansible-playbook -i ansible/inventory/hosts ansible/laguna.yml -K
./scripts/laguna-start.sh     # Laguna S 2.1 ROCmFP4 -> http://127.0.0.1:8082/v1
# override context (256K experimental lane):
STABILITY_MODE=performance ./scripts/laguna-start.sh
```

**5. Everything at once (full bootstrap)**
```bash
ansible-playbook -i ansible/inventory/hosts ansible/bootstrap.yml -K
# then, per track:
./scripts/ds4-start.sh
./scripts/qwen36-start.sh
./scripts/gemma-e4b-start.sh
./scripts/laguna-start.sh
./scripts/qwen-rccl-start.sh
```

**Common flags** — `--tags <track>` runs one track (`base`, `ds4`, `qwen`,
`llama`, `laguna`); `--skip-tags base` skips the base play; `--tags model`
re-runs just downloads; `--check` dry-runs. Within the llama track, per-model
tags `qwen36` / `gemma-e4b` run only that model's download + launch-script/pi-config
render, and `--skip-tags qwen36` / `--skip-tags gemma-e4b` skip just that model. The
laguna track has its own tags (`--tags laguna`, `--tags build`, `--tags model`,
`--tags laguna`). A track file can be run standalone (no need to go through the
orchestrator).

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

# Laguna S 2.1 ROCmFP4 StrixKVSpine V4 (~60.95 GB, Ciru ROCmFPX Runtime V3 only)
cd ~/.local/share/llama-models && \
  aria2c -x 16 -s 16 --file-allocation=none --auto-file-renaming=false --continue=true \
    -o laguna-s-2.1-ROCmFP4-StrixKVSpine-v4.gguf \
    "https://huggingface.co/jcbtc/Laguna-S-2.1-Chadrock-ROCmFP4-StrixKVSpine-V4-GGUF/resolve/main/laguna-s-2.1-ROCmFP4-StrixKVSpine-v4.gguf"
```

Verify integrity after download (HF publishes sha256, not md5):
```bash
sha256sum <file>.gguf   # compare against the repo's file listing
# Laguna S 2.1 expected sha256: ea1d854a72c47ec8e72c16ea91b8ff3cd5e1620b834df175f683c86f27dc26d6
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

### llama.cpp — Qwen3.6-35B-A3B + Gemma 4 E4B (Vulkan/RADV)
```bash
./scripts/qwen36-start.sh   # ctx 131072 (keep >=128k for thinking)
./scripts/gemma-e4b-start.sh # ctx 131072, dense model, large batch
```
Both use the latest source-built `llama-server` with the Mesa RADV Vulkan
backend (fastest tg + MoE pp on Strix Halo), `--flash-attn on`, `--no-mmap`
(full load into the unified shared pool), `--n-gpu-layers 999`. Endpoints:
`http://127.0.0.1:8081/v1` (qwen36) and `http://127.0.0.1:8083/v1` (gemma-e4b).
First request is shader-JIT slow; decode is memory-bandwidth-bound.

### Laguna S 2.1 ROCmFP4 StrixKVSpine V4 (Ciru ROCmFPX Runtime V3)
```bash
./scripts/laguna-start.sh
# raise context (experimental 256K lane — not yet fully validated):
STABILITY_MODE=performance ./scripts/laguna-start.sh
```
**Runtime V3** uses the Ciru ROCmFPX fork (NOT stock upstream llama.cpp).
AMD-optimized ROCmFP4 quant: 118B total / ~8B active, **60.95 GB** at **4.453
BPW**, tested at **35.62 tok/s** generation and **195.70 tok/s** PP at 128K.

V3 Vulkan stability fixes (Runtime V2 baseline):
- `GGML_VK_MAX_NODES_PER_SUBMIT=10` — split large FA dispatch (prevents RADV DeviceLost)
- `GGML_VK_FA_MAX_WORKGROUPS_X_PER_DISPATCH=4` — bounded FA workgroups
- Context checkpoints disabled (`--ctx-checkpoints 0`) for hybrid/SWA safety
- JSON grammar fixes (PR #24835: no trailing whitespace in generated JSON values)

Validated profile: batch=2048, ubatch=512, ctx=131072, F16/F16 KV cache, 16
threads, 999 GPU layers. Endpoint: `http://127.0.0.1:8082/v1`.

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
files). Source: `ansible/templates/*.j2` → rendered by the launch-render play
(`llama.yml`, play 2, `tags: [launch, llama]`) into:
- `scripts/qwen36-start.sh` ← `templates/qwen36-start.sh.j2`  (`tags: [launch, qwen36]`)
- `scripts/gemma-e4b-start.sh` ← `templates/gemma-e4b-start.sh.j2` (`tags: [launch, gemma-e4b]`)
- `scripts/laguna-start.sh` ← `templates/laguna-start.sh.j2`  (`tags: [launch, laguna]`)
- `pi-configs/pi-qwen36.json` ← `templates/pi-qwen36.json.j2` (`tags: [launch, qwen36]`)
- `pi-configs/pi-gemma-e4b.json` ← `templates/pi-gemma-e4b.json.j2` (`tags: [launch, gemma-e4b]`)
- `pi-configs/pi-laguna.json` ← `templates/pi-laguna.json.j2` (`tags: [launch, laguna]`)

The DS4 + Qwen tracks render their own start scripts / pi configs the same way.

**Render + view the Qwen3.6 config** (download auto-skips since the GGUF is present):
```bash
ansible-playbook -i ansible/inventory/hosts ansible/llama.yml -K --tags qwen36
cat scripts/qwen36-start.sh    # launch script (Vulkan0, port 8081)
cat pi-configs/pi-qwen36.json  # pi agent config
```

**Render just the laguna config** (full track, includes ROCmFPX build):
```bash
ansible-playbook -i ansible/inventory/hosts ansible/laguna.yml -K
cat scripts/laguna-start.sh
# skip build and download, only render:
ansible-playbook -i ansible/inventory/hosts ansible/laguna.yml -K --tags launch
```

Per-model tags: `--tags qwen36` runs only the qwen36 download + render; `--tags
gemma-e4b` runs only the gemma-e4b download + render; `--tags
launch` runs the whole launch-render play (both qwen36 + gemma-e4b scripts + pi
configs). The laguna track is fully standalone (`ansible/laguna.yml`). Once
rendered, `./scripts/install-pi.sh` merges `pi-configs/*` into
`~/.pi/agent/models.json`.

## pi agent config

The bootstrap drops pi agent configs into `pi-configs/`:
- `pi-ds4.json` — `ds4` provider → `http://127.0.0.1:8000/v1`, model `deepseek-v4-flash` (single-node IQ2_XXS).

- `pi-qwen36.json` — `qwen36` provider → `http://127.0.0.1:8081/v1`, model `qwen3.6-35b-a3b`.
- `pi-laguna.json` — `laguna-s21` provider → `http://127.0.0.1:8082/v1`, model `laguna-s21-rocmfp4-strixkvspine-v4` (ROCmFP4, Ciru ROCmFPX Runtime V3).
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
- llama.cpp: `qwen36_ctx` (131072),
  `qwen36_port` (8081), `qwen36_host/device/batch/ubatch/flash_attn/mmap` (same defaults);
  `laguna_ctx` (131072), `laguna_port` (8082), `laguna_host` (127.0.0.1),
  `laguna_batch` (2048), `laguna_ubatch` (512), `laguna_threads` (16),
  `laguna_vulkan_nodes` (10), `laguna_vulkan_fa_wg` (4), `laguna_sha256`,
  `laguna_repo`/`laguna_branch`/`laguna_commit` (Ciru ROCmFPX Runtime V3)
- Qwen: `qwen_head_ip`, `qwen_worker_ip`, `qwen_max_model_len` (default 65536),
  `qwen_tp_size` (default 2), `qwen_port`, `qwen_ifname`
- Scripts: `DS4_ROLE` (single|coordinator|worker), `DS4_USE_MTP`, `DS4_CTX_SINGLE`,
  `DS4_CTX`, `DS4_MODELS_DIR`, `DS4_HOST`; `GEMMA_*/QWEN36_*` (BIN/MODEL/CTX/
  PORT/HOST/DEVICE/BATCH/UBATCH/FA/MMAP/THREADS); `LAGUNA_*` (BIN/LIB/MODEL/CTX/
  PORT/HOST/BIN_DIR/BATCH/UBATCH/THREADS/CTX_CHECKPOINTS/STABILITY_MODE); `QWEN_ROLE`;
  `HF_TOKEN`
