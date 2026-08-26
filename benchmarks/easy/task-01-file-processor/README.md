# Task 01: File Processor

Build a command-line file processor that reads text files, transforms them, and writes output.

## Problem Statement

Create a CLI tool called `fileproc` that processes text files with the following operations:

- `--count` : Count lines, words, and characters
- `--reverse` : Reverse the order of lines
- `--upper` / `--lower` : Case conversion
- `--unique` : Remove duplicate lines (preserve first occurrence order)
- `--sort` : Sort lines alphabetically
- Combine flags: `--count --unique --upper`

## Requirements (Hard)

1. **CLI interface:** Accept `--input <file>` and at least one operation flag
2. **Multiple operations:** Can chain multiple transforms (`--upper --reverse --unique`)
3. **Output to stdout** by default, with `--output <file>` to write to a file
4. **Error handling:** Missing file → graceful error message (exit code 1). No empty output silently.
5. **UTF-8 support:** Handle non-ASCII characters correctly
6. **Empty file handling:** Should not crash on empty input
7. **No trailing newline issues:** Preserve or normalize trailing newline consistently

## Nice-to-Haves (Bonus)

1. `--stdin` flag to read from stdin instead of file
2. `--inplace` to edit the file in place (like `sed -i`)
3. `--preserve-case` in `--unique` (case-insensitive dedup, keep original case)
4. `--count-lines` / `--count-words` / `--count-chars` individual counts
5. `--help` and `--version` flags
6. `--trim` to strip leading/trailing whitespace from each line before operations

## Implementation Guide

### Suggested Architecture

```python
#!/usr/bin/env python3
"""fileproc — command-line file processor"""

import argparse
import sys
from pathlib import Path


def read_input(path: str) -> list[str]:
    """Read file and return lines."""
    ...


def write_output(lines: list[str], path: str | None) -> None:
    """Write lines to stdout or file."""
    ...


def count(lines: list[str]) -> dict:
    """Return {'lines': N, 'words': N, 'chars': N}."""
    ...


def reverse(lines: list[str]) -> list[str]:
    return lines[::-1]


def upper(lines: list[str]) -> list[str]:
    return [l.upper() for l in lines]


def lower(lines: list[str]) -> list[str]:
    return [l.lower() for l in lines]


def unique(lines: list[str]) -> list[str]:
    seen = set()
    result = []
    for line in lines:
        if line not in seen:
            seen.add(line)
            result.append(line)
    return result


def sort(lines: list[str]) -> list[str]:
    return sorted(lines)
```

### Expected Usage

```bash
# Count lines, words, chars
python fileproc.py --input sample.txt --count

# Uppercase + reverse + remove dups + write to file
python fileproc.py --input sample.txt --upper --reverse --unique --output output.txt

# Read from stdin
cat sample.txt | python fileproc.py --stdin --upper --unique

# Individual counts
python fileproc.py --input sample.txt --count-lines --count-words --count-chars
```

## Evaluation Checklist

| Criterion | Pass? |
|---|---|
| CLI accepts --input + operation flags | ☐ |
| Multiple operations chain correctly | ☐ |
| --output writes to file | ☐ |
| Error on missing file (exit code 1) | ☐ |
| UTF-8 works (e.g., "日本語") | ☐ |
| Empty file doesn't crash | ☐ |
| All 6 operations work | ☐ |
| Nice-to-haves implemented | ☐ |

## Reference Solution

`reference/` — do not show to the LLM during testing.
