#!/usr/bin/env python3
"""
long_context_stress.py — long-prompt DeviceLost stress test for Strix Halo.

Fires a ~100k+ token prompt at a running llama-server (OpenAI-compatible API)
and records whether the request completes or the GPU loses the device mid-
prefill (llama.cpp #21724 / #24872 / #27306 on AMD Strix Halo).

Stdlib only — no pip dependencies. Run it once per server configuration:

  A: default deploy (MTP / speculation ON)
       python3 long_context_stress.py --label A
  B: redeploy with -e extra_args='--spec-type none'
       python3 long_context_stress.py --label B

The generated prompt is cached so every run uses byte-identical text.
See README.md in this directory for the full procedure and interpretation.
"""

from __future__ import annotations

import argparse
import json
import random
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_URL = "http://192.168.1.212:8080"          # host port for qwen38-27b-rocmfp4
DEFAULT_CONTAINER = "qwen38-27b-ud-q4-k-xl"       # docker_container_name in the playbook
DEFAULT_CTX = 262144                           # server --ctx (speed profile)
DEFAULT_TARGET_TOKENS = 260_000                # ~107k real tokens; headroom under 128K ctx
CHARS_PER_TOKEN_EST = 4.0                      # sizing estimate (Qwen BPE, tech prose)
WORST_CASE_CHARS_PER_TOKEN = 3.2               # safety cap: densest plausible ratio
DEVICE_LOST_RE = re.compile(
    r"devicelost|device lost|context is lost|radv:|gpu reset|"
    r"amdgpu.*(reset|timeout|error)|vk::",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Prompt generation — deterministic synthetic technical document.
# Content realism doesn't affect the stress (prefill cost is token-count
# driven), but a coherent document keeps the test a valid inference workload.
# ---------------------------------------------------------------------------


def _sec_incident(rng: random.Random) -> str:
    """Incident report — the anchor document."""
    sev = rng.choice(["SEV-1", "SEV-2"])
    svc = rng.choice(["inference-gateway", "kv-cache-pool", "vulkan-scheduler", "token-broker"])
    lines = [
        f"INCIDENT REPORT {sev}-{rng.randint(1000, 9999)}",
        f"Service: {svc} | Region: halo-1 | Severity: {sev}",
        "",
        "SUMMARY",
        f"A sustained degradation was observed on {svc}. Prefill latency p99 rose from "
        f"{rng.randint(2, 8)}s to {rng.randint(40, 300)}s over a {rng.randint(5, 60)}-minute window. "
        "Decode throughput dropped proportionally, and the on-call engineer confirmed the "
        "degradation was correlated with long-context requests only; short prompts were unaffected.",
        "",
        "TIMELINE (UTC)",
    ]
    t0 = rng.randint(0, 23)
    events = ["alert fired", "on-call paged", "metrics reviewed", "log sample captured",
              "mitigation attempted", "workaround applied", "traffic shifted",
              "root cause narrowed"]
    for _ in range(rng.randint(6, 10)):
        lines.append(f"{t0:02d}:{rng.randint(0, 59):02d} - {rng.choice(events)}")
    lines += [
        "",
        "IMPACT",
        f"Approximately {rng.randint(1, 40)}% of long-context traffic was affected. No data "
        "loss; requests either completed slowly or failed with a device-level error. Client "
        "retries amplified load by a factor of ~2 during the incident window.",
        "",
        "ROOT CAUSE (PRELIMINARY)",
        "The GPU driver watchdog fired while the inference engine was submitting a large batch "
        "of compute work for prompt prefill. The submission exceeded the ring timeout, the "
        "kernel reset the device, and in-flight requests were aborted mid-generation.",
    ]
    return "\n".join(lines)


def _sec_architecture(rng: random.Random) -> str:
    """System architecture narrative."""
    nodes = ["llama-server", "vulkan-queue", "kv-cache", "mtp-drafter", "router", "health-probe"]
    roles = ["manages the request lifecycle", "batches GPU compute work",
             "stores key/value state", "drafts speculative tokens",
             "routes by context length", "reports liveness to the orchestrator"]
    lines = [
        "SYSTEM ARCHITECTURE",
        "",
        "The serving stack is a single-node deployment on AMD Strix Halo (gfx1151, unified "
        "memory). A llama-server process exposes an OpenAI-compatible API. Requests enter the "
        "router, are admitted against a single server slot, and are split into prefill and "
        "decode phases by the engine.",
        "",
        "COMPONENTS",
    ]
    for n, r in zip(nodes, roles):
        lines.append(f"- {n}: {r} (owner: platform team, SLO: {rng.randint(95, 99)}% availability)")
    lines += [
        "",
        "DATA FLOW",
        "Prompt tokens are chunked into micro-batches. Each micro-batch becomes a compute "
        "graph submitted to the GPU queue. With speculative decoding enabled, each micro-batch "
        "carries additional draft-decode nodes, increasing the node count per submission. The "
        "KV cache lives in unified memory with K quantized to q8_0 and V to turbo4.",
    ]
    return "\n".join(lines)


def _sec_config(rng: random.Random) -> str:
    """Configuration dump."""
    lines = [
        "RUNTIME CONFIGURATION",
        "",
        "[server]",
        f"ctx_size = {DEFAULT_CTX}",
        f"slots = {rng.randint(1, 4)}",
        f"port = {rng.choice([8000, 8080])}",
        "flash_attn = on",
        f"ubatch_size = {rng.choice([512, 1024, 2048])}",
        "",
        "[vulkan]",
        "device = Vulkan0 (AMD Strix Halo)",
        f"max_nodes_per_submit = {rng.choice([1, 1, 1, 64])}   # GGML_VK_MAX_NODES_PER_SUBMIT",
        "queue_mode = dedicated compute queue",
        "",
        "[speculation]",
        "type = mtp (built into model)",
        f"max_draft_tokens = {rng.randint(2, 8)}",
        "accept_threshold = 0.5",
        "",
        "[kv_cache]",
        "k_type = q8_0",
        "v_type = turbo4",
        f"prompt_cache_size = {DEFAULT_CTX} tokens",
    ]
    return "\n".join(lines)


def _sec_metrics(rng: random.Random) -> str:
    """Synthetic metrics table."""
    lines = [
        "METRICS (5-minute window, prefill path)",
        "",
        "metric                  p50     p95     p99     max",
        "prefill_latency_s      "
        f"{rng.randint(1, 4):<7}{rng.randint(5, 12):<7}{rng.randint(13, 40):<7}{rng.randint(41, 120)}",
        "tokens_per_second      "
        f"{rng.randint(200, 400):<7}{rng.randint(150, 250):<7}{rng.randint(80, 150):<7}{rng.randint(20, 80)}",
        "queue_depth            "
        f"{rng.randint(0, 2):<7}{rng.randint(2, 6):<7}{rng.randint(6, 14):<7}{rng.randint(15, 30)}",
        "gpu_submit_nodes       "
        f"{rng.randint(1, 4):<7}{rng.randint(4, 12):<7}{rng.randint(12, 40):<7}{rng.randint(40, 200)}",
        "",
        "Observations: p99 prefill latency scales super-linearly with prompt length. The "
        "gpu_submit_nodes metric spikes exactly when long prompts are admitted, and the spike "
        "width correlates with the number of draft tokens in flight.",
    ]
    return "\n".join(lines)


def _sec_logdump(rng: random.Random) -> str:
    """Synthetic server log excerpt."""
    lines = ["SERVER LOG EXCERPT", ""]
    ts = rng.randint(0, 23)
    msgs = [
        "slot 0: prefill chunk {i}/{n} ({t} tokens)",
        "vulkan: submitting compute graph (nodes={nd}, queue=dedicated)",
        "kv cache: slot 0 usage at {p}% of window",
        "spec decode: draft accepted {a}/{d} tokens",
        "WARN watchdog margin low on ring 0 (headroom {ms} ms)",
        "ERROR vk::DeviceLostError: context is lost (radv)",
    ]
    for i in range(rng.randint(10, 16)):
        lvl = rng.choice(["INFO", "INFO", "INFO", "WARN", "ERROR"])
        m = rng.choice(msgs).format(
            i=i, n=rng.randint(8, 32), t=rng.randint(512, 4096), nd=rng.randint(1, 64),
            p=rng.randint(40, 95), a=rng.randint(0, 6), d=rng.randint(2, 8), ms=rng.randint(1, 40))
        lines.append(f"{ts:02d}:{rng.randint(0, 59):02d}.{rng.randint(0, 999):03d} [{lvl}] {m}")
    return "\n".join(lines)


def _sec_bench(rng: random.Random) -> str:
    """Micro-benchmark table."""
    lines = [
        "MICRO-BENCHMARK (prompt prefill, single slot)",
        "",
        "prompt_tokens   nodes_per_submit   wall_ms   status",
    ]
    for tok in [1024, 8192, 32768, 65536, 131072]:
        nps = rng.choice([1, 64])
        ms = int(tok / rng.randint(200, 450)) * (1 if nps == 1 else 2)
        status = "ok" if (tok <= 65536 or nps == 1) else rng.choice(["devicelost", "timeout"])
        lines.append(f"{tok:<15}{nps:<19}{ms:<9}{status}")
    lines += [
        "",
        "Reading: with nodes_per_submit=1 the 131072-token prefill completes (slow but "
        "clean). With the default batched submit, long prefills trip the watchdog. This is "
        "the exact regime the end-to-end stress test exercises.",
    ]
    return "\n".join(lines)


def _sec_postmortem(rng: random.Random) -> str:
    """Postmortem narrative."""
    lines = [
        "POSTMORTEM",
        "",
        "WHAT HAPPENED",
        "A burst of long-context requests caused the engine to submit a large compute graph "
        "in a single queue submission. The submission exceeded the amdgpu ring watchdog "
        "timeout, the kernel reset the GPU, and every in-flight request failed with a "
        "device-lost error. Short requests were unaffected because their submissions stayed "
        "under the timeout.",
        "",
        "WHY IT HAPPENED",
        "1. Prefill work is proportional to prompt length; long prompts produce many graph nodes.",
        "2. Speculative decoding adds draft-decode nodes to every micro-batch, inflating the count.",
        "3. The default submission policy batches all nodes into one vkQueueSubmit.",
        "4. The amdgpu ring watchdog timeout is short by default on this platform.",
        "",
        "ACTIONS",
        "- [x] Cap graph nodes per submission to 1 (GGML_VK_MAX_NODES_PER_SUBMIT=1).",
        "- [ ] Validate with a ~100k-token end-to-end stress test (the purpose of this document).",
        "- [ ] Decide whether the kernel lockup_timeout must be raised as a second layer.",
        "- [ ] Document the MTP interaction and whether --spec-type none is required.",
    ]
    return "\n".join(lines)


def _sec_runbook(rng: random.Random) -> str:
    """Operational runbook."""
    lines = [
        "RUNBOOK: long-context degradation",
        "",
        "SYMPTOMS",
        "- p99 prefill latency spikes on long prompts only.",
        "- Server log shows 'vk::DeviceLostError' or 'radv: context is lost'.",
        "- Kernel log shows an amdgpu reset or lockup timeout.",
        "",
        "DIAGNOSIS",
        "1. Confirm the request length: check the router access log for prompt token counts.",
        "2. Check the container log for device-lost errors around the same timestamp.",
        "3. Check the kernel log (journalctl -k) for amdgpu reset/timeout lines.",
        "4. Verify GGML_VK_MAX_NODES_PER_SUBMIT is set to 1 in the container environment.",
        "",
        "MITIGATION",
        "1. Immediate: restart the container; in-flight long requests are retried by clients.",
        "2. Short-term: cap client prompt length below the failing threshold.",
        "3. Permanent: keep nodes-per-submit=1; if failures persist, raise amdgpu.lockup_timeout.",
    ]
    return "\n".join(lines)


def _sec_capacity(rng: random.Random) -> str:
    """Capacity planning notes."""
    tps = rng.randint(200, 450)
    lines = [
        "CAPACITY PLANNING",
        "",
        f"Target context window: {DEFAULT_CTX} tokens. The working set per slot is dominated "
        "by the KV cache (K q8_0, V turbo4) plus the prompt cache. On unified memory this "
        "competes with the OS and other workloads, so the deployment pins a single slot to "
        "keep the working set predictable.",
        "",
        f"Throughput model: prefill is compute-bound at ~{tps} tokens/s for moderate lengths "
        "and degrades as the KV cache grows. A full-window prefill therefore takes on the "
        "order of minutes, which is why the stress test allows a long timeout and why the "
        "watchdog margin matters: the GPU is busy for a sustained period, not a burst.",
    ]
    return "\n".join(lines)


def _sec_cost(rng: random.Random) -> str:
    """Cost / tradeoff analysis."""
    lines = [
        "COST AND TRADEOFFS",
        "",
        "Option A: nodes-per-submit=1 (GGML flag only). No reboot, no kernel change, easy to "
        "roll back. Cost: many small submissions; measured overhead is small on this platform "
        "because prefill is compute-bound, but it is not zero.",
        "",
        "Option B: raise amdgpu.lockup_timeout (kernel arg via GRUB/Limine). Lets a large "
        "batched submission finish before the watchdog fires. Cost: a hung GPU now takes much "
        "longer to reset, so a real hang is slower to recover; requires reboot to change; the "
        "playbooks expose it as an opt-in flag (lockup_timeout_enabled) precisely because it "
        "should not be default.",
        "",
        "Decision gate: run the ~100k-token stress test with MTP on, then again with "
        "--spec-type none. If both pass with Option A, do not ship Option B.",
    ]
    return "\n".join(lines)


def _sec_faq(rng: random.Random) -> str:
    """Frequently asked questions."""
    qas = [
        ("Why do only long prompts fail?",
         "Submission size grows with prompt length; short prompts stay under the watchdog timeout."),
        ("Why does MTP matter?",
         "Each micro-batch carries extra draft-decode nodes, pushing the submission over the edge."),
        ("Is the KV quantization relevant?",
         "Only indirectly: smaller KV types let longer contexts fit, so the failing regime is reachable."),
        ("Can this be reproduced without the GPU?",
         "No — the watchdog lives in the amdgpu driver; the stress test must run on the target."),
    ]
    lines = ["FAQ", ""]
    for q, a in qas:
        lines.append(f"Q: {q}\nA: {a}\n")
    return "\n".join(lines)


def _sec_changelog(rng: random.Random) -> str:
    """Version history."""
    lines = ["CHANGE LOG", ""]
    for _ in range(rng.randint(4, 8)):
        v = f"v{rng.randint(1, 3)}.{rng.randint(0, 9)}.{rng.randint(0, 9)}"
        kind = rng.choice(["fix", "perf", "ops", "doc"])
        what = rng.choice([
            "raised ring watchdog margin in staging",
            "pinned nodes-per-submit to 1 for the ROCm track",
            "added /tokenize-based prompt sizing to the stress harness",
            "documented MTP interaction with long prefills",
            "switched KV cache to K=q8_0/V=turbo4",
            "added health probe to the serving container",
        ])
        lines.append(f"{v} ({kind}): {what}")
    return "\n".join(lines)


SECTION_GENERATORS = [
    _sec_incident,
    _sec_architecture,
    _sec_config,
    _sec_metrics,
    _sec_logdump,
    _sec_bench,
    _sec_postmortem,
    _sec_runbook,
    _sec_capacity,
    _sec_cost,
    _sec_faq,
    _sec_changelog,
]

FINAL_QUESTION = (
    "Given the full document above, answer in at most four short sentences: "
    "1) what failed and why, 2) which mitigation is in place, 3) what the "
    "stress test must prove, and 4) the exact llama-server flag that disables "
    "speculative decoding if the long prefill still trips the watchdog."
)


# ---------------------------------------------------------------------------
# Prompt assembly and caching
# ---------------------------------------------------------------------------

def generate_prompt(target_tokens: int, seed: int) -> str:
    """Build a deterministic technical document of ~target_tokens tokens."""
    rng = random.Random(seed)
    # Cap the char count so that even at the densest plausible ratio the
    # prompt stays under the token budget (headroom for template + answer).
    max_chars = int(target_tokens * WORST_CASE_CHARS_PER_TOKEN)
    sections = []
    total = 0
    while total < max_chars:
        for gen in SECTION_GENERATORS:
            if total >= max_chars:
                break
            text = gen(rng)
            sections.append(text)
            total += len(text)
    prompt = "\n\n".join(sections)[:max_chars]
    return prompt + "\n\n" + FINAL_QUESTION


def load_or_create_prompt(target_tokens: int, seed: int, regenerate: bool) -> str:
    """Cache the prompt to disk so A/B/C runs use byte-identical text."""
    prompts_dir = SCRIPT_DIR / "prompts"
    prompts_dir.mkdir(exist_ok=True)
    path = prompts_dir / f"prompt_{seed}_{target_tokens}tok.txt"
    if path.exists() and not regenerate:
        return path.read_text(encoding="utf-8")
    prompt = generate_prompt(target_tokens, seed)
    path.write_text(prompt, encoding="utf-8")
    return prompt


# ---------------------------------------------------------------------------
# HTTP helpers (OpenAI-compatible llama-server API)
# ---------------------------------------------------------------------------

def http_get_json(url: str, timeout: float = 15.0) -> dict:
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_post_json(url: str, payload: dict, timeout: float):
    """POST JSON; return (status_code, body_dict_or_text, elapsed_seconds)."""
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url, data=data,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            elapsed = time.monotonic() - t0
            try:
                return resp.status, json.loads(raw), elapsed
            except json.JSONDecodeError:
                return resp.status, raw, elapsed
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        elapsed = time.monotonic() - t0
        try:
            return e.code, json.loads(raw), elapsed
        except json.JSONDecodeError:
            return e.code, raw, elapsed


def wait_for_health(url: str, timeout: float = 60.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            http_get_json(url + "/health", timeout=5)
            return True
        except Exception:
            time.sleep(3)
    return False


def measure_tokens(url: str, text: str) -> int:
    """Exact token count via the server's /tokenize endpoint (llama.cpp)."""
    try:
        data = json.dumps({"content": text, "add_special_tokens": False}).encode("utf-8")
        req = urllib.request.Request(
            url + "/tokenize", data=data,
            headers={"Content-Type": "application/json"}, method="POST",
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = json.loads(resp.read().decode("utf-8"))
        toks = body.get("tokens")
        if isinstance(toks, list):
            return len(toks)
        if isinstance(body.get("n_tokens"), int):
            return body["n_tokens"]
    except Exception as e:
        print(f"  [warn] /tokenize failed ({e}); using chars/4.0 estimate", file=sys.stderr)
    return int(len(text) / CHARS_PER_TOKEN_EST)


def get_model_id(url: str) -> str:
    try:
        body = http_get_json(url + "/v1/models")
        models = body.get("data") or []
        if models:
            return models[0].get("id", "unknown")
    except Exception:
        pass
    return "unknown"


# ---------------------------------------------------------------------------
# Log forensics — did the GPU lose the device?
# ---------------------------------------------------------------------------

def _run(cmd: str, timeout: float = 60.0) -> tuple:
    """Run a shell command; return (ok, combined_output)."""
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return (p.returncode == 0), (p.stdout or "") + (p.stderr or "")
    except FileNotFoundError:
        return False, f"command not available: {cmd.split()[0]}"
    except subprocess.TimeoutExpired:
        return False, f"timeout running: {cmd}"


def _grep(lines, pattern) -> list:
    return [l for l in lines if pattern.search(l)]


def collect_evidence(container: str, want_kernel: bool) -> dict:
    """Grep container + kernel logs for DeviceLost / watchdog signatures."""
    ev = {"container_lines": [], "kernel_lines": [], "sources": [], "notes": {}}
    ok, out = _run(f"podman logs --tail 800 {container} 2>&1")
    if ok:
        ev["sources"].append(f"podman logs {container}")
        ev["container_lines"] = _grep(out.splitlines(), DEVICE_LOST_RE)
    else:
        ev["notes"]["podman"] = out.strip() or "podman unavailable"
    if want_kernel:
        ok, out = _run("journalctl -k --since '30 min ago' --no-pager 2>&1")
        if ok:
            ev["sources"].append("journalctl -k (30 min)")
            ev["kernel_lines"] = _grep(out.splitlines(), DEVICE_LOST_RE)
        else:
            ev["notes"]["journalctl"] = out.strip() or "journalctl unavailable (need root?)"
    return ev


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Long-context DeviceLost stress test (Python stdlib only).",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("--url", default=DEFAULT_URL, help="llama-server base URL")
    ap.add_argument("--container", default=DEFAULT_CONTAINER,
                    help="podman container name for log forensics")
    ap.add_argument("--label", default="A",
                    help="run label recorded in results.jsonl (A/B/C)")
    ap.add_argument("--target-tokens", type=int, default=DEFAULT_TARGET_TOKENS,
                    help="approximate prompt token target")
    ap.add_argument("--seed", type=int, default=131072, help="prompt generation seed")
    ap.add_argument("--regenerate", action="store_true",
                    help="force prompt regeneration (bypass cache)")
    ap.add_argument("--max-tokens", type=int, default=64,
                    help="max_tokens for the completion")
    ap.add_argument("--timeout", type=float, default=3600.0,
                    help="request timeout in seconds")
    ap.add_argument("--no-tokenize", action="store_true",
                    help="skip /tokenize; use chars/4.0 estimate")
    ap.add_argument("--kernel-logs", action="store_true",
                    help="also grep journalctl -k (run as root for full coverage)")
    ap.add_argument("--out", default=str(SCRIPT_DIR / "results.jsonl"),
                    help="results file (JSON lines, one line per run)")
    args = ap.parse_args()

    base = args.url.rstrip("/")
    print(f"=== long-context stress test — label {args.label} ===")
    print(f"target: {base}   container: {args.container}")

    # 1. health
    if not wait_for_health(base, timeout=30):
        print("FATAL: server not healthy — is the container up?", file=sys.stderr)
        return 1
    model = get_model_id(base)
    print(f"server healthy; model: {model}")

    # 2. prompt (cached so all runs are byte-identical)
    prompt = load_or_create_prompt(args.target_tokens, args.seed, args.regenerate)
    n_chars = len(prompt)
    if not args.no_tokenize:
        print(f"measuring prompt via /tokenize ({n_chars:,} chars)...")
        n_tokens = measure_tokens(base, prompt)
        print(f"  exact tokens: {n_tokens:,}  "
              f"(chars/4.0 estimate: {int(n_chars / CHARS_PER_TOKEN_EST):,})")
        token_source = "tokenize"
    else:
        n_tokens = int(n_chars / CHARS_PER_TOKEN_EST)
        print(f"  estimated tokens: {n_tokens:,} (chars/4.0; --no-tokenize)")
        token_source = "estimate"

    if n_tokens > DEFAULT_CTX - 1024:
        print(f"FATAL: prompt ({n_tokens:,} tokens) + completion would exceed the "
              f"{DEFAULT_CTX} ctx; lower --target-tokens", file=sys.stderr)
        return 1

    # 3. the long request
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": args.max_tokens,
        "temperature": 0.0,
        "stream": False,
    }
    print(f"sending {n_tokens:,}-token prompt "
          f"(max_tokens={args.max_tokens}, timeout={args.timeout:.0f}s)...")
    start_ts = datetime.now(timezone.utc).isoformat()
    status, body, elapsed = http_post_json(
        base + "/v1/chat/completions", payload, args.timeout)

    completion_text = ""
    usage = {}
    error_text = ""
    if isinstance(body, dict):
        choices = body.get("choices") or []
        if choices:
            completion_text = (choices[0].get("message") or {}).get("content") or ""
        usage = body.get("usage") or {}
        if body.get("error"):
            error_text = json.dumps(body["error"])
    elif isinstance(body, str):
        error_text = body

    # 4. forensics
    ev = collect_evidence(args.container, args.kernel_logs)
    dl_response = bool(DEVICE_LOST_RE.search(error_text))
    dl_container = bool(ev["container_lines"])
    dl_kernel = bool(ev["kernel_lines"])
    completed = (status == 200 and not error_text)
    passed = completed and not (dl_response or dl_container or dl_kernel)

    # 5. record
    record = {
        "ts": start_ts,
        "label": args.label,
        "url": base,
        "container": args.container,
        "model": model,
        "target_tokens": args.target_tokens,
        "prompt_chars": n_chars,
        "prompt_tokens": n_tokens,
        "prompt_tokens_source": token_source,
        "max_tokens": args.max_tokens,
        "http_status": status,
        "elapsed_s": round(elapsed, 2),
        "usage": usage,
        "completed": completed,
        "completion_chars": len(completion_text),
        "device_lost": {
            "in_response": dl_response,
            "in_container_logs": dl_container,
            "in_kernel_logs": dl_kernel,
        },
        "evidence_lines": {
            "container": ev["container_lines"][:20],
            "kernel": ev["kernel_lines"][:20],
        },
        "notes": ev["notes"],
    }
    with open(args.out, "a", encoding="utf-8") as f:
        f.write(json.dumps(record) + "\n")

    # 6. report
    print()
    print(f"HTTP {status} in {elapsed:.1f}s | completion: {len(completion_text)} chars")
    if usage:
        print(f"usage: {json.dumps(usage)}")
    if error_text:
        print(f"error: {error_text[:500]}")
    if completion_text:
        print("--- completion (first 500 chars) ---")
        print(completion_text[:500])
    print(f"DeviceLost evidence: response={dl_response} "
          f"container_logs={dl_container} kernel_logs={dl_kernel}")
    if not args.kernel_logs:
        print("  (hint: rerun with --kernel-logs as root to also cover journalctl -k)")
    for k, v in ev["notes"].items():
        print(f"  [note:{k}] {v[:200]}")
    if passed:
        print(f"RESULT [{args.label}]: PASS — long prefill completed cleanly")
    else:
        print(f"RESULT [{args.label}]: FAIL — request failed or DeviceLost evidence found")
    print(f"record appended to {args.out}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
