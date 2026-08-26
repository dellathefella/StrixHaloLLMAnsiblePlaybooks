# Hard Tier

Complex systems that require deep understanding of concurrency, protocols, architecture, and edge cases.

## What "Hard" Means

- **Scope:** 15+ files, 2000+ lines of code
- **Complexity:** Concurrency, network protocols, custom state machines, distributed concepts
- **Dependencies:** Multiple packages, custom protocols, performance-critical code
- **Time budget:** 60 minutes per task
- **What it tests:** System design thinking, concurrency safety, protocol correctness, edge case handling, performance optimization

## Tasks

| # | Name | Focus | Files | LOC |
|---|---|---|---|---|
| 01 | HTTP Server from Scratch | Protocol parsing, concurrency, streaming | 10-15 | ~1500 |
| 02 | Real-Time Chat System | WebSockets, state management, pub/sub | 10-15 | ~2000 |

Each task lives in its own directory under `hard/`. See the individual README for full details.

## Common Hard-Tier Evaluation Criteria

| Criterion | Pass? |
|---|---|
| Correctness under concurrent load | ☐ |
| Protocol compliance (RFC standards) | ☐ |
| Edge case handling (malformed input, timeouts) | ☐ |
| Resource management (file descriptors, connections) | ☐ |
| Graceful degradation | ☐ |
| Performance (no obvious bottlenecks) | ☐ |
| Architecture clarity | ☐ |
| Tests (unit + integration) | ☐ |
| Documentation (README, inline comments) | ☐ |
