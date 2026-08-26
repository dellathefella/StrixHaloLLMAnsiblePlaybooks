# Task 02: REST API with Database

Build a production-ready REST API with SQLite, authentication, migrations, and tests.

## Problem Statement

Create a REST API for a **task management system** with user authentication, task CRUD, filtering, and pagination. The API should be robust enough to handle real-world usage patterns.

## Requirements (Hard)

1. **Project structure:** At least 5 files (`app.py`, `models.py`, `auth.py`, `routes.py`, `database.py` or similar)
2. **SQLite with migrations:** Use a migration system (or manual SQL) for schema evolution
3. **Authentication:** JWT-based auth (register, login, protected endpoints)
4. **Task CRUD:** Create, read, update, delete tasks (each task belongs to a user)
5. **Filtering & pagination:** `?status=todo|in_progress|done&priority=high|medium|low&page=1&per_page=20`
6. **Input validation:** All inputs validated; return 400 with error messages for invalid data
7. **Error handling:** Consistent error response format (`{"error": "message", "code": 400}`)
8. **CORS:** Allow requests from `http://localhost:3000`
9. **Database schema:** Users table + Tasks table with foreign key relationship
10. **Testing:** At least 5 test cases covering auth, CRUD, and error handling

## Nice-to-Haves (Bonus)

1. Task comments/subtasks
2. Email notification on task assignment (stub/mock)
3. `created_at` and `updated_at` timestamps auto-populated
4. Soft delete (mark as deleted, don't actually remove)
5. Bulk operations (`POST /tasks/bulk` with array of tasks)
6. `GET /tasks/export` returning CSV/JSON
7. Request ID tracing (add `X-Request-Id` header)
8. Rate limiting on auth endpoints
9. API documentation (OpenAPI/Swagger spec)
10. `--port` and `--db` CLI arguments

## Implementation Guide

### Suggested Architecture

```
taskapi/
├── __init__.py
├── app.py              # FastAPI/Flask app factory
├── models.py           # SQLAlchemy/ORM models
├── auth.py             # JWT creation, verification, middleware
├── routes.py           # API route handlers
├── database.py         # DB connection, migrations
├── schemas.py          # Pydantic validation schemas
├── main.py             # Entry point (CLI args)
└── tests/
    ├── __init__.py
    ├── conftest.py     # Test fixtures, test client
    └── test_api.py     # Test cases
```

### Database Schema

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    title TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'todo' CHECK(status IN ('todo', 'in_progress', 'done')),
    priority TEXT DEFAULT 'medium' CHECK(priority IN ('low', 'medium', 'high')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE INDEX idx_tasks_user ON tasks(user_id);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_priority ON tasks(priority);
```

### Expected Usage

```bash
# Start server
python -m taskapi.main --port 8080

# Register
curl -X POST http://localhost:8080/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "email": "alice@example.com", "password": "secret"}'

# Login
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "secret"}'
# → returns {"token": "eyJ..."}

# Create a task (authenticated)
curl -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer eyJ..." \
  -d '{"title": "Fix the thing", "priority": "high"}'

# Filter and paginate
curl "http://localhost:8080/tasks?status=todo&priority=high&page=1&per_page=10"
```

### JWT Token Structure

```python
# Payload:
{
    "sub": "<user_id>",
    "username": "<username>",
    "exp": <expiry_timestamp>
}
# Secret: randomly generated at startup, stored in memory
```

### Test Cases to Include

```python
# 1. User registration succeeds
# 2. Duplicate username registration fails (400/409)
# 3. Login returns valid JWT
# 4. Invalid password returns 401
# 5. Create task requires auth (401 without token)
# 6. CRUD operations work correctly
# 7. Filtering returns correct subset
# 8. Pagination works (returns correct count/page)
```

## Evaluation Checklist

| Criterion | Pass? |
|---|---|
| 5+ project files | ☐ |
| SQLite with schema | ☐ |
| JWT authentication (register + login) | ☐ |
| Task CRUD with user ownership | ☐ |
| Filtering + pagination | ☐ |
| Input validation (400 on bad input) | ☐ |
| Consistent error format | ☐ |
| CORS configured | ☐ |
| Foreign key relationship | ☐ |
| Tests included (5+) | ☐ |
| Nice-to-haves implemented | ☐ |

## Reference Solution

`reference/` — do not show to the LLM during testing.
