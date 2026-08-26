# Task 02: Real-Time Chat System

Build a real-time chat server with WebSocket support, user rooms, message history, and presence tracking.

## Problem Statement

Create a real-time chat system that supports:

1. WebSocket connections for real-time messaging
2. User authentication via token (simple API key)
3. Room-based messaging (join rooms, send messages to rooms)
4. Message history (last N messages per room)
5. Presence tracking (who's online in each room)
6. HTTP API for registration, room management, and message history retrieval

## Requirements (Hard)

1. **WebSocket server:** Real-time bidirectional communication using `websockets` library or equivalent
2. **User system:** Register/log in with username and password; auth token returned
3. **Rooms:** Create, join, leave rooms; list available rooms
4. **Messaging:** Send messages to rooms; broadcast to all members; receive in real-time
5. **Message history:** Query last N messages per room (HTTP endpoint); persist in SQLite
6. **Presence:** Track who is connected to each room; notify on join/leave
7. **Persistence:** Messages stored in SQLite; survive server restart
8. **Concurrency:** Handle concurrent WebSocket connections safely (thread-safe state)
9. **HTTP API:** REST endpoints for non-real-time operations (register, login, list rooms, get history)
10. **Error handling:** Handle disconnections, invalid messages, unauthorized access

## Nice-to-Haves (Bonus)

1. **Typing indicators:** `typing` event when user starts typing
2. **Message reactions:** Add/remove emoji reactions on messages
3. **Direct messages:** 1:1 messaging between users
4. **Message search:** Search messages within a room (text search)
5. **Rich messages:** Support markdown or code blocks in messages
6. **Room topics/descriptions:** Room metadata
7. **Message edits/deletes:** Edit or delete messages (with edit history)
8. **Read receipts:** Track which messages have been seen
9. **File sharing:** Upload/download files in chat
10. **Rate limiting:** Prevent spam (max messages per minute per user)

## Implementation Guide

### Suggested Architecture

```
chat/
├── __init__.py
├── server.py           # WebSocket server + HTTP server
├── auth.py             # User registration, login, token management
├── rooms.py            # Room creation, membership, message broadcasting
├── messages.py         # Message storage, retrieval, history
├── presence.py         # Online tracking, presence events
├── protocols.py        # Message protocol definitions (JSON schemas)
├── api.py              # HTTP API routes (FastAPI or manual)
├── database.py         # SQLite connection, schema, migrations
├── config.py           # Server configuration
├── main.py             # Entry point
├── tests/
│   ├── __init__.py
│   ├── test_auth.py
│   ├── test_rooms.py
│   └── test_chat.py
└── requirements.txt
```

### Message Protocol

```json
// Client → Server
{
    "type": "message",
    "room": "general",
    "content": "Hello world"
}

// Server → Client (broadcast)
{
    "type": "message",
    "room": "general",
    "user": "alice",
    "content": "Hello world",
    "id": "msg_001",
    "timestamp": 1234567890
}

// Join event
{
    "type": "user_joined",
    "room": "general",
    "user": "alice"
}

// Typing indicator
{
    "type": "typing",
    "room": "general",
    "user": "alice"
}
```

### Database Schema

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE rooms (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE room_members (
    room_id INTEGER REFERENCES rooms(id),
    user_id INTEGER REFERENCES users(id),
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (room_id, user_id)
);

CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    room_id INTEGER NOT NULL REFERENCES rooms(id),
    user_id INTEGER NOT NULL REFERENCES users(id),
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_messages_room ON messages(room_id, created_at DESC);
```

### Expected Usage

```bash
# Start server
python -m chat.main --port 8080

# Register a user (HTTP)
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "secret"}'
# → {"token": "abc123"}

# Join a room via WebSocket
wscat -c ws://localhost:8080/ws?token=abc123 -x '{"type": "join", "room": "general"}'

# Send a message
wscat -c ws://localhost:8080/ws?token=abc123 -x '{"type": "message", "room": "general", "content": "Hi!"}'

# List rooms (HTTP)
curl http://localhost:8080/api/rooms

# Get message history (HTTP)
curl "http://localhost:8080/api/rooms/general/messages?limit=50"
```

### Key Design Decisions the LLM Should Address

1. **Concurrency:** Thread-safe message broadcasting, per-room locks vs global lock
2. **WebSocket lifecycle:** Reconnection handling, heartbeat/ping-pong
3. **Message deduplication:** Idempotent message delivery on reconnect
4. **Memory management:** Limit message history retention, clean up stale connections
5. **Scalability:** Single-server design is fine, but architecture should hint at horizontal scaling (pub/sub, shared store)

## Evaluation Checklist

| Criterion | Pass? |
|---|---|
| WebSocket server works | ☐ |
| User auth (register + login) | ☐ |
| Room creation/join/leave | ☐ |
| Real-time message broadcasting | ☐ |
| Message history (last N) | ☐ |
| SQLite persistence | ☐ |
| Presence tracking | ☐ |
| Thread-safe concurrency | ☐ |
| HTTP API endpoints | ☐ |
| Error handling | ☐ |
| Tests included | ☐ |
| Nice-to-haves implemented | ☐ |

## Reference Solution

`reference/` — do not show to the LLM during testing.
