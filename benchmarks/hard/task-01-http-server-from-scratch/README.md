# Task 01: HTTP Server from Scratch

Build a concurrent HTTP/1.1 server from scratch using only Python's standard library (`socket`, `threading`/`asyncio`). No web frameworks allowed.

## Problem Statement

Create a fully functional HTTP/1.1 server that:

1. Parses HTTP requests (method, path, headers, body)
2. Routes requests to handlers
3. Supports multiple concurrent connections
4. Handles HTTP/1.1 features: `Host` header, `Content-Length`, `Connection: keep-alive`, chunked transfer encoding
5. Serves static files from a directory
6. Supports basic request middleware (timing, logging)

## Requirements (Hard)

1. **HTTP/1.1 parsing:** Correctly parse request lines, headers, and bodies. Handle malformed requests gracefully (return 400).
2. **Request routing:** Dispatch to handler functions by path prefix or exact match
3. **Concurrency:** Handle multiple simultaneous connections (threading or asyncio)
4. **Static file serving:** Serve files from a configured directory with correct `Content-Type` based on extension
5. **Keep-alive:** Support HTTP/1.1 persistent connections (`Connection: keep-alive`)
6. **Chunked transfer encoding:** Support `Transfer-Encoding: chunked` for response body streaming
7. **Content-Type detection:** Map file extensions to MIME types (at minimum: `.html`, `.css`, `.js`, `.json`, `.png`, `.jpg`, `.txt`)
8. **Range requests:** Support `Range: bytes=start-end` header for partial content (206 response)
9. **Error handling:** Return proper HTTP status codes (400, 404, 405, 500, 501)
10. **Request logging:** Log each request (method, path, status, duration) to stdout

## Nice-to-Haves (Bonus)

1. **Request middleware pipeline:** Chain of middleware (timing → logging → auth → handler)
2. **HTTPS support:** TLS using `ssl` module
3. **Gzip compression:** `Accept-Encoding: gzip` support with `Content-Encoding: gzip` response
4. **ETag / Last-Modified:** Conditional requests with `If-None-Match` and `If-Modified-Since` (304 response)
5. **Custom headers:** `X-Powered-By`, `Server` header
6. **Request timeout:** Abort slow requests after configurable timeout
7. **Connection limits:** Max concurrent connections with queuing
8. **WebSocket upgrade:** Basic `Upgrade: websocket` support
9. **Request body buffering:** Configurable max body size (reject oversized bodies with 413)
10. **Access control:** Simple allow/deny list by IP

## Implementation Guide

### Suggested Architecture

```
httpserver/
├── __init__.py
├── server.py           # Main server loop, accept connections
├── parser.py           # HTTP request parser (line, headers, body)
├── response.py         # HTTP response builder (status, headers, body)
├── router.py           # Request routing (path matching, handler dispatch)
├── handlers.py         # Default handlers (static files, 404, 405)
├── middleware.py       # Middleware chain (timing, logging)
├── static.py           # Static file serving with MIME types and caching
├── chunked.py          # Chunked transfer encoding encoder
├── connection.py       # Connection handler (one connection, keep-alive loop)
├── types.py            # Constants, MIME type map, status codes
├── config.py           # Server configuration
├── main.py             # Entry point
├── tests/
│   ├── __init__.py
│   ├── test_parser.py
│   ├── test_server.py
│   └── test_static.py
└── static/             # Sample static files for testing
```

### HTTP Request Parser

```python
# Must handle:
# GET /path HTTP/1.1
# Host: example.com
# Content-Type: application/json
# Content-Length: 42
#
# (blank line)
# {"key": "value"}

class HTTPRequest:
    method: str
    path: str
    version: str
    headers: dict[str, str]
    body: bytes
```

### HTTP Response Builder

```python
# Must build:
# HTTP/1.1 200 OK
# Content-Type: text/html
# Content-Length: 12
# Connection: keep-alive
#
# <html>...</html>

class HTTPResponse:
    status_code: int
    reason_phrase: str
    headers: dict[str, str]
    body: bytes | None  # None means chunked

    def to_bytes(self) -> bytes: ...
    def chunked_chunks(self) -> Iterator[bytes]: ...
```

### Expected Usage

```bash
# Basic server
python -m httpserver.main --port 8080 --root ./static

# With middleware and limits
python -m httpserver.main --port 8080 --root ./static --max-body 10485760 --timeout 30

# Test it
curl -v http://localhost:8080/
curl -v http://localhost:8080/nonexistent
curl -v -X POST http://localhost:8080/api/test -d '{"test": true}'
```

### Key Design Decisions the LLM Should Address

1. **Connection lifecycle:** Accept → parse loop → handler → write response → loop (for keep-alive) or close
2. **Concurrency model:** Thread-per-connection (simpler) vs asyncio (more complex but more scalable)
3. **Buffer management:** Read exactly `Content-Length` bytes, handle partial reads
4. **Thread safety:** Shared state (router, file cache) protected by locks
5. **Graceful shutdown:** Signal handling, drain active connections, close listener socket
6. **Chunked encoding:** `0\r\n\r\n` terminator, trailer headers support

## Evaluation Checklist

| Criterion | Pass? |
|---|---|
| Parses HTTP/1.1 requests correctly | ☐ |
| Routes to handlers | ☐ |
| Handles concurrent connections | ☐ |
| Static file serving with MIME types | ☐ |
| Keep-alive (persistent connections) | ☐ |
| Chunked transfer encoding | ☐ |
| Range requests (206) | ☐ |
| Proper error status codes | ☐ |
| Request logging | ☐ |
| Tests included | ☐ |
| Nice-to-haves implemented | ☐ |

## Reference Solution

`reference/` — do not show to the LLM during testing.
