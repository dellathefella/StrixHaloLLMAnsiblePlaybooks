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
DEFAULT_URL = "http://localhost:8080"          # host port for qwen38-27b-rocmfp4
DEFAULT_CONTAINER = "qwen38-27b-rocmfp4"       # docker_container_name in the playbook
DEFAULT_CTX = 131072                           # server --ctx (speed profile)
DEFAULT_TARGET_TOKENS = 110_000                # ~107k real tokens; headroom under 128K ctx
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
