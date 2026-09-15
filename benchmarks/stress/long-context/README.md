# Long-Context Stress Test (DeviceLost repro)

Reliability test — not a scored coding task. Fires a ~100k+ token prompt at the
running `qwen38-27b-rocmfp4` llama-server and records whether it completes or
the GPU loses the device mid-prefill
(llama.cpp #21724 / #24872 / #27306 on AMD Strix Halo).

## What it tests

On Strix Halo, a long prefill submits many Vulkan graph nodes in one
`vkQueueSubmit`. If that submit outruns the amdgpu ring watchdog, the kernel
resets the GPU and llama.cpp fails mid-generation with `vk::DeviceLostError`.
MTP / speculative decoding makes it worse (#27306) because each ubatch carries
extra draft-decode nodes.

The default mitigation is GGML-only (`GGML_VK_MAX_NODES_PER_SUBMIT=1`, set by
the deploy playbook). This test answers the open question: **is that enough, or
do we also need the opt-in `amdgpu.lockup_timeout` kernel arg — and does MTP
need to be disabled with `--spec-type none`?**

## Prerequisites

- Server deployed and healthy:
  `ansible-playbook ansible/single-node/qwen38-27b-rocmfp4-podman.yml`
- Health check on the target host: `curl -s http://localhost:8080/health`
- Python 3.9+ (stdlib only — no pip dependencies)

## Procedure

### Run A — default config (MTP on, flags-only mitigation)

    python3 long_context_stress.py --label A

### Run B — MTP disabled

Redeploy with the spec override, then re-run:

    ansible-playbook ansible/single-node/qwen38-27b-rocmfp4-podman.yml \
        -e extra_args='--spec-type none'
    # confirm the flag took effect:
    podman logs qwen38-27b-rocmfp4 2>&1 | grep -iE 'spec|draft' | head
    python3 long_context_stress.py --label B

### Optional — live kernel-watchdog test (no reboot)

Before opting into the GRUB/Limine change, test the watchdog live:

    sudo echo 60000 | sudo tee /sys/module/amdgpu/parameters/lockup_timeout
    python3 long_context_stress.py --label C-sysfs
    # revert (or reboot to restore the default):
    sudo echo 50 | sudo tee /sys/module/amdgpu/parameters/lockup_timeout

## Interpreting results

| Run A (MTP on) | Run B (`--spec-type none`) | Conclusion |
|---|---|---|
| pass | pass | flags-only mitigation is sufficient; no kernel arg needed |
| fail | pass | MTP is the aggravator (#27306); keep `extra_args='--spec-type none'` in the profile |
| fail | fail | escalate: opt in `amdgpu.lockup_timeout` (`-e lockup_timeout_enabled=true`) and retest as Run C |

Each run appends a JSON line to `results.jsonl` (token count, HTTP status,
elapsed time, DeviceLost evidence from container + kernel logs). Exit code 0 =
clean pass; 1 = failure or DeviceLost evidence.

## Notes

- The prompt is generated once and cached in `prompts/` so A/B/C runs use
  byte-identical text. `--regenerate` forces a new one; `--seed` varies it.
- Prompt length is measured with the server's own `/tokenize` endpoint (exact),
  falling back to a chars/4.0 estimate if unavailable (`--no-tokenize`).
- Default target is ~110k tokens — sized so that even at a densest 3.2
  chars/token ratio the prompt stays under the 131072 ctx, with headroom for
  the chat template and a small completion (`--max-tokens`, default 64).
- A clean prefill of this size takes several minutes; `--timeout` defaults to
  30 min.
- `--kernel-logs` (run as root) also greps `journalctl -k` for amdgpu reset
  messages; without it the script prints a hint to rerun with the flag.
