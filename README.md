# ROCm / DS4 + Qwen cluster install — Ryzen AI Max (HP Z2 G1a)

Organized workspace for bootstrapping AMD ROCm inference on the Ryzen AI Max
"Strix Halo" APU, on **HP Z2 G1a** workstations (2.5Gbe NICs — no 10Gbps
requirement). Ubuntu/Debian only. Three tracks, all driven by **one unified
ansible playbook**:

1. **DS4** — DeepSeek V4 Flash via the `ds4` engine (single-node IQ2_XXS ~80.8GB,
   or multi-node Q4KExperts ~153GB via pipeline parallelism).
2. **Qwen RCCL cluster** — Qwen3.5-397B-A17B-GPTQ-Int4 across two nodes via
   vLLM + Ray + RCCL, context pushed to 65536 (guide default is 32768).
3. **Qwen3.8-27B (q38rocm / ROCmFPX)** — single-node Qwen3.8-27B via the
   **prebuilt ROCmFPX llama.cpp engine** (dual ROCm + Vulkan, v1.4.0,
   SHA256-verified) from [julianmb/q38rocm](https://github.com/julianmb/q38rocm),
   the **ROCmFP4_FAST** 4-bit quant (13.55 GiB), **MTP speculative decoding**
   (built-in draft head, ~36 tok/s on Vulkan0), and the **asymmetric TurboQuant
   KV cache** (K=`q8_0`, V=`turbo4`) so 262k context costs only ~20 GB. Native
   **262144 context** (set 131k to halve the reserved KV; decode speed is the
   same until you actually fill >~100k context). Needs **ROCm 7.2.x** (PLAY 1
   installs 7.2.3) + the Mesa RADV Vulkan ICD (`mesa-vulkan-drivers`).

**Network note:** host NICs are 2.5Gbe (HP Z2 G1a), below the guide's 10Gbps;
tensor-parallel KV exchange is the bottleneck. The playbook warns on this but
treats 2.5Gbe as acceptable — there is no 10Gbps requirement.

**TTM:** the shared-memory pool is configured by the GRUB kernel args
(`ttm.pages_limit=32505856 ttm.page_pool_size=32505856` ⇒ ~124GB). **No
`amd-ttm --set` is used** anywhere in the ansible — set BIOS UMA VRAM to
Auto/minimum, append the GRUB args, reboot.

**ROCm version:** PLAY 1 installs **ROCm 7.2.3** via AMD's `repo.radeon.com`
(noble packages, used on this resolute/26.04 host) — *not* the Ubuntu `rocm`
package (7.1.0). The q38rocm prebuilt engine links against the 7.2.x runtime
(`libhipblas.so.3`, `librocblas.so.5`, `libamdhip64.so.7`).

**Architecture:** the ansible playbook is **bootstrap-only**. It installs
packages, sets GRUB, creates containers/toolboxes, builds llama.cpp, and
downloads model weights. It NEVER launches servers. On completion it drops
**local copies** of the launch scripts into `scripts/` and the pi agent configs
into `pi-configs/` — you run/merge them when ready.

**Local scripts:** only the **DS4 single-node** bootstrap is kept as a local
script (`scripts/ds4-setup.sh`, treated as a bootstrap tool); everything else
(base, Qwen RCCL, Qwen3.8) is done via ansible. `scripts/install-pi-ds4.sh`
is the local pi + DS4 toolchain installer for this controller machine.

## Layout

```
├── README.md                      this file
├── hf_token.txt                   HuggingFace token (gated model downloads)
├── reference/
│   ├── playbook.txt               AMD ds4 playbook (text extract)
│   └── notes.md                   pi local-server / DS4 config snippets
├── ansible/
│   ├── bootstrap.yml              THE unified playbook (base + DS4 + qwen + qwen38)
│   ├── templates/                 Jinja templates (rendered by bootstrap.yml)
│   │   ├── ds4-start.sh.j2        DS4 launch script template
│   │   ├── qwen-start.sh.j2       Qwen RCCL launch template
│   │   ├── qwen38-start.sh.j2     Qwen3.8 q38rocm launch template (ROCmFPX, MTP, TurboQuant KV)
│   │   ├── pi-ds4.json.j2         pi agent config template (DS4)
│   │   ├── pi-qwen.json.j2        pi agent config template (Qwen RCCL)
│   │   └── pi-qwen38.json.j2      pi agent config template (Qwen3.8)
│   └── inventory/
│       ├── hosts                  your real inventory (local qwen38 test)
│       └── hosts.example          sample inventory + vars for all tracks
├── scripts/
│   ├── ds4-setup.sh               DS4 single-node bootstrap (local tool only)
│   ├── install-pi-ds4.sh          local pi + DS4 toolchain installer
│   ├── ds4-start.sh               rendered DS4 launch (role via env)
│   ├── qwen-start.sh              rendered Qwen RCCL launch (role via env)
│   └── qwen38-start.sh            rendered Qwen3.8 q38rocm launch (MTP, device auto)
└── pi-configs/                    rendered pi agent configs (dropped locally)
    ├── pi-ds4.json                merge into ~/.pi/agent/models.json
    ├── pi-qwen.json
    └── pi-qwen38.json
```

## Quick start

### Local machine — pi + DS4 toolchain installer
```bash
./scripts/install-pi-ds4.sh
# installs pi, @capyup/pi-auto-compact, ds4-cockpit, amd-ttm, hf, amdgpu_top
# and merges the DS4 provider into ~/.pi/agent/models.json
```

### Ansible route (Ubuntu nodes) — one playbook, tracks by group
```bash
cp ansible/inventory/hosts.example ansible/inventory/hosts   # edit groups/vars
# Full bootstrap (base + whichever groups are populated):
ansible-playbook -i ansible/inventory/hosts ansible/bootstrap.yml
# Re-test a track on an already-provisioned host (skip base):
ansible-playbook -i ansible/inventory/hosts ansible/bootstrap.yml --skip-tags base
# Only one track:
ansible-playbook -i ansible/inventory/hosts ansible/bootstrap.yml --tags ds4
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

### DS4 single-node local bootstrap (the one kept local script)
```bash
./scripts/ds4-setup.sh          # GRUB/TTM(args), ds4 distrobox, model downloads
```

## Launch later (bootstrap never runs servers)

After the bootstrap + REBOOT (if GRUB changed), copy the rendered launch
script to each node and run it:

### DS4 multi-node (both nodes must use the same ctx + model)
```bash
# Machine 1 (coordinator, layers 0:21):
DS4_ROLE=coordinator ./scripts/ds4-start.sh
# Machine 2 (worker, layers 22:output):
DS4_ROLE=worker      ./scripts/ds4-start.sh
# Single node (optional):
DS4_ROLE=single      ./scripts/ds4-start.sh
```
MTP speculative decoding is **disabled by default** (stability). Enable with
`DS4_USE_MTP=1` if desired.

### Qwen cluster (head first, then worker)
```bash
# Machine 1 (head — Ray head + vLLM server):
QWEN_ROLE=head   ./scripts/qwen-start.sh
# Machine 2 (worker — joins Ray):
QWEN_ROLE=worker ./scripts/qwen-start.sh
```
OpenAI endpoint: `http://<HEAD_IP>:7000/v1` (Auth: None). vLLM downloads
Qwen weights into the models dir on first serve.

### Qwen3.8-27B (q38rocm / ROCmFPX, single node, MTP on by default)
```bash
./scripts/qwen38-start.sh                       # ctx 262144, MTP draft-mtp, device auto
QWEN38_CTX=131072 QWEN38_PORT=8082 ./scripts/qwen38-start.sh   # halve reserved KV
QWEN38_DEVICE=Vulkan0 QWEN38_MTP=1 ./scripts/qwen38-start.sh   # pin backend
```
The script sets the ROCmFPX/Strix-Halo env (`HSA_OVERRIDE_GFX_VERSION=11.5.1`,
`GGML_HIP_ENABLE_UNIFIED_MEMORY=1`, RADV ICD, `LD_LIBRARY_PATH` = engine bin +
ROCm libs), auto-detects **Vulkan0** (fastest, ~36 t/s) and falls back to
ROCm0 (~28 t/s), then serves with the asymmetric TurboQuant KV cache
(`-ctk q8_0 -ctv turbo4`) + MTP. OpenAI endpoint: `http://0.0.0.0:8082/v1`.
First request is ~3× slow (shader JIT); decode is memory-bandwidth-bound on the
13.55 GiB model, so context length has little effect until you fill >~100k.

## pi agent config

The bootstrap drops pi agent configs into `pi-configs/`:
- `pi-ds4.json` — `ds4` provider → `http://<coord_ip>:8000/v1`, model `deepseek-v4-flash`.
- `pi-qwen.json` — `qwen-cluster` provider → `http://<head_ip>:7000/v1`, model `Qwen/Qwen3.5-397B-A17B-GPTQ-Int4`.
- `pi-qwen38.json` — `qwen38` provider → `http://<host>:8082/v1`, model `qwen3.8-27b`.

Merge the provider block(s) into `~/.pi/agent/models.json` (pi reloads it when
you open `/model`; no restart needed). `install-pi-ds4.sh` also installs the
`@capyup/pi-auto-compact` extension for pre-turn auto-compaction.

## Config variables (inventory / env)
- DS4: `ds4_mode` (single|multi), `ds4_ctx`, `ds4_port`, `ds4_coord_ip/port`,
  `ds4_download_single/multi/mtp` (model downloads per host)
- Qwen: `qwen_head_ip`, `qwen_worker_ip`, `qwen_max_model_len` (default 65536),
  `qwen_tp_size` (default 2), `qwen_port`, `qwen_ifname`
- Qwen3.8 (q38rocm): `qwen38_ctx` (262144 default; 131k halves reserved KV),
  `qwen38_port`, `qwen38_host`, `qwen38_device` (auto|Vulkan0|ROCm0),
  `qwen38_slots`, `qwen38_batch`, `qwen38_ubatch`, `qwen38_kv_k` (q8_0),
  `qwen38_kv_v` (turbo4), `qwen38_draft_n` (4), `qwen38_draft_pmin` (0.0),
  `qwen38_reasoning_budget` (4096), `qwen38_temp`, `qwen38_presence_penalty`,
  `qwen38_repeat_penalty`
- Scripts: `DS4_MODE`, `DS4_MODELS_DIR`, `DS4_DOWNLOAD_*`, `HF_TOKEN`;
  `QWEN38_MODEL/BIN/HOST/PORT/CTX/DEVICE/MTP/DRAFT_N/DRAFT_PMIN/KV_K/KV_V/
  SLOTS/BATCH/UBATCH/REASONING_BUDGET/TEMP/PRESENCE_PENALTY/REPEAT_PENALTY`
