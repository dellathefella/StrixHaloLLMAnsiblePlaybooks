# LLM Coding Benchmarks

Systematic coding benchmarks for evaluating LLMs on Strix Halo hardware. Each tier tests different dimensions of code generation, architecture thinking, and engineering discipline.

## Directory Structure

```
benchmarks/
├── README.md              ← you are here
├── easy/                  # Scripts, APIs, simple utilities
│   ├── README.md
│   └── task-01-file-processor/
│   └── task-02-json-api-server/
├── medium/                # Full apps, CLI tools, testing
│   ├── README.md
│   └── task-01-web-crawler/
│   └── task-02-rest-api-with-db/
└── hard/                  # Distributed systems, compilers, complex state
    ├── README.md
    └── task-01-http-server-from-scratch/
    └── task-02-real-time-chat/
```

## Tier Definitions

| Tier | What it tests | Expected context | LLM strengths required |
|---|---|---|---|
| **Easy** | Single-file scripts, basic APIs, data processing | 1-3 files, <200 LOC | Syntax, standard library, basic error handling |
| **Medium** | Multi-file apps, CLI tools, database-backed services | 5-10 files, 500-1500 LOC | Project structure, testing, dependency management, state machines |
| **Hard** | Distributed systems, custom protocols, compilers, real-time | 15+ files, 2000+ LOC | Concurrency, network protocols, architecture patterns, edge cases |

## How to Run

1. Pick a task directory
2. Give the LLM the `README.md` (requirements + guide) — **do not** show the reference solution
3. Set a time budget (easy: 10 min, medium: 30 min, hard: 60 min)
4. Evaluate against the checklist in each task's README
5. Record results in the **scorecard** (below)

## Evaluation Checklist

For each task, score these dimensions:

| Dimension | Score (0-3) | Notes |
|---|---|---|
| **Correctness** | Does it work end-to-end? | 0=fails, 1=partial, 2=mostly, 3=all cases |
| **Requirements** | All hard requirements met? | Count missing requirements |
| **Nice-to-haves** | Bonus features implemented? | Count implemented |
| **Code quality** | Readable, structured, idiomatic? | 0=spaghetti, 1=works-but-messy, 2=clean, 3=professional |
| **Error handling** | Graceful failures? | 0=crashes, 1=some handling, 2=good, 3=exhaustive |
| **Testing** | Unit/integration tests? | 0=none, 1=some, 2=adequate, 3=comprehensive |
| **Performance** | Reasonable speed/memory? | 0=unusable, 1=slow but works, 2=acceptable, 3=optimized |

**Total: 0-21 points per task. Scorecard tracks averages by tier and model.**

---

## Scorecard

| Model | Easy (avg) | Medium (avg) | Hard (avg) | Overall | Notes |
|---|---|---|---|---|---|
| Qwen3.6-35B-A3B | | | | | UD-Q8_K_XL, ~65 t/s |
| Gemma 4 26B-A4B | | | | | UD-Q8_K_XL, ~45 t/s |
| Qwen3.8-Flash-Next 125B-A6B | | | | | UD-IQ4_XS, ~23 t/s decode, ~390 t/s pp512 |
| Qwen3.8-Flash-Next-AP 125B-A6B | | | | | Q5_K_XL (agentionai), ~12–20 t/s decode, ~450 pp @ 2048, ~240 pp @ ~100k |
| gpt-oss-120B | | | | | MXFP4, ~55 t/s |
| | | | | | |

---

## General Rules

1. **No internet access** — the LLM must work with what it knows
2. **No showing reference solutions** — that defeats the purpose
3. **Same prompt format** for all models — copy-paste the exact task README
4. **Time budget is fixed** — stop the LLM when time expires, note "timeout"
5. **Run the code** — don't just judge from text; execute it and verify
