# Task 02: JSON API Server

Build a lightweight HTTP API server that serves and manages JSON data in memory.

## Problem Statement

Create an in-memory JSON API server (no database) that manages a collection of resources (e.g., "notes", "tasks", or "todos"). The server should support CRUD operations via HTTP endpoints.

## Requirements (Hard)

1. **HTTP server:** Use only Python standard library (`http.server` + `json`) or one lightweight package (Flask/FastAPI)
2. **GET /resources** : Return all resources as JSON array
3. **GET /resources/<id>** : Return single resource by ID (404 if not found)
4. **POST /resources** : Create a new resource (auto-assign integer ID starting from 1)
5. **PUT /resources/<id>** : Update a resource (404 if not found)
6. **DELETE /resources/<id>** : Delete a resource (404 if not found)
7. **JSON responses:** All responses must be valid JSON with proper `Content-Type: application/json` header
8. **Error handling:** Missing IDs → 404, invalid JSON body → 400, unknown routes → 404
9. **Data persistence in memory:** Data survives across requests (not reinitialized per request)

## Nice-to-Haves (Bonus)

1. Query parameters for filtering: `?limit=5&offset=10` for pagination
2. `?q=searchterm` for text search across resource fields
3. Request logging: print each request to stdout (method, path, status code)
4. `PATCH /resources/<id>` for partial updates
5. `GET /stats` returning count and other metadata
6. Graceful shutdown on SIGINT/SIGTERM

## Implementation Guide

### Suggested Architecture

```python
#!/usr/bin/env python3
"""jsonapi — in-memory JSON API server"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import threading

# In-memory store: {id: resource_dict}
store = {}
next_id = 1
lock = threading.Lock()


class APIHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        ...

    def do_POST(self):
        ...

    def do_PUT(self):
        ...

    def do_DELETE(self):
        ...

    def send_json(self, status: int, data):
        ...


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 8080), APIHandler)
    print("Server running on http://127.0.0.1:8080")
    server.serve_forever()
```

### Expected Usage

```bash
# Start server
python api_server.py

# Create a resource
curl -X POST http://localhost:8080/resources \
  -H "Content-Type: application/json" \
  -d '{"title": "Hello", "body": "World"}'

# Get all resources
curl http://localhost:8080/resources

# Update a resource
curl -X PUT http://localhost:8080/resources/1 \
  -H "Content-Type: application/json" \
  -d '{"title": "Updated"}'

# Delete a resource
curl -X DELETE http://localhost:8080/resources/1
```

## Evaluation Checklist

| Criterion | Pass? |
|---|---|
| Server starts and listens | ☐ |
| GET /resources returns all | ☐ |
| GET /resources/<id> returns one | ☐ |
| POST /resources creates new (auto-ID) | ☐ |
| PUT /resources/<id> updates | ☐ |
| DELETE /resources/<id> deletes | ☐ |
| All responses are valid JSON | ☐ |
| 404 on missing IDs/routes | ☐ |
| 400 on invalid JSON body | ☐ |
| Data persists across requests | ☐ |
| Nice-to-haves implemented | ☐ |

## Reference Solution

`reference/` — do not show to the LLM during testing.
