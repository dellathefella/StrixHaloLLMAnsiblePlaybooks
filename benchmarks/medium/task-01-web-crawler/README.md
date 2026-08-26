# Task 01: Web Crawler

Build a concurrent web crawler that discovers and downloads pages from a starting URL, respecting robots.txt and rate limits.

## Problem Statement

Create a web crawler that:

1. Starts from a given seed URL
2. Discovers new URLs by parsing links from fetched pages
3. Downloads page content (HTML + text extraction)
4. Stores results in a SQLite database
5. Respects `robots.txt` rules
6. Enforces a crawl delay (rate limiting)
7. Tracks visited URLs to avoid duplicates
8. Supports a maximum depth limit and page count limit

## Requirements (Hard)

1. **Project structure:** At least 3 files (e.g., `crawler.py`, `storage.py`, `robots.py`)
2. **Concurrency:** Use `asyncio` with `aiohttp` for concurrent fetching (min 5 concurrent requests)
3. **SQLite storage:** Persist visited URLs, status, content hash, and extracted text
4. **Robots.txt parsing:** Parse and respect `robots.txt` rules using `urllib.robotparser`
5. **Rate limiting:** Configurable delay between requests (default: 1 second)
6. **Duplicate detection:** Hash URLs and content to avoid re-fetching
7. **Depth tracking:** Only crawl links up to `max_depth` from the seed (default: 3)
8. **Page limit:** Stop after `max_pages` fetched (default: 100)
9. **CLI interface:** `--seed <url> --depth N --limit N --delay N`
10. **Logging:** Structured logging (at minimum: URL, status, depth, time)

## Nice-to-Haves (Bonus)

1. `robots.txt` caching (don't re-parse for each host)
2. `sitemap.xml` discovery and submission
3. Text extraction (strip HTML tags, extract readable text)
4. `--output <dir>` to save raw HTML to disk alongside DB
5. `--resume` to continue from a previous crawl (load state from DB)
6. `--sitemap-only` mode that only extracts URLs without fetching content
7. `User-Agent` header with identifiable name
8. `--exclude-domains` and `--include-domains` filters
9. `--extensions` filter (only crawl `.html`, `.pdf`, etc.)
10. Progress reporting (pages crawled / time elapsed / URLs found)

## Implementation Guide

### Suggested Architecture

```
crawler/
├── __init__.py
├── cli.py              # CLI argument parsing, entry point
├── crawler.py          # Main crawl loop, URL scheduling
├── fetcher.py          # Async HTTP fetching with rate limiting
├── robots.py           # robots.txt parsing and checking
├── storage.py          # SQLite database operations
├── parser.py           # HTML parsing, link extraction, text extraction
└── utils.py            # URL normalization, hashing helpers
```

### Database Schema

```sql
CREATE TABLE pages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    url TEXT UNIQUE NOT NULL,
    status_code INTEGER,
    content_hash TEXT,
    title TEXT,
    text TEXT,
    depth INTEGER DEFAULT 0,
    fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    robots_allowed INTEGER DEFAULT 1
);

CREATE TABLE links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_url TEXT NOT NULL,
    to_url TEXT NOT NULL,
    depth INTEGER NOT NULL,
    UNIQUE(from_url, to_url)
);

CREATE INDEX idx_pages_url ON pages(url);
CREATE INDEX idx_links_depth ON links(depth);
```

### Expected Usage

```bash
# Basic crawl
python -m crawler.cli --seed https://example.com --depth 2 --limit 50

# With delay and output directory
python -m crawler.cli --seed https://example.com --delay 2 --limit 200 --output ./crawled

# Resume a previous crawl
python -m crawler.cli --seed https://example.com --resume
```

### Key Design Decisions the LLM Should Address

1. **URL normalization** — strip fragments, lowercase, handle relative URLs
2. **Concurrency model** — asyncio.Queue for pending URLs, semaphore for rate limiting
3. **Robots.txt scope** — per-host caching, don't block if robots.txt fetch fails
4. **Error resilience** — transient errors (5xx) should retry with backoff
5. **Memory management** — don't hold all page content in memory; write to disk

## Evaluation Checklist

| Criterion | Pass? |
|---|---|
| Project has 3+ files | ☐ |
| Async concurrency (≥5 requests) | ☐ |
| SQLite with correct schema | ☐ |
| robots.txt respected | ☐ |
| Rate limiting works | ☐ |
| Duplicate detection | ☐ |
| Depth tracking correct | ☐ |
| Page limit enforced | ☐ |
| CLI works as specified | ☐ |
| Logging present | ☐ |
| Nice-to-haves implemented | ☐ |
| Tests included | ☐ |

## Reference Solution

`reference/` — do not show to the LLM during testing.
