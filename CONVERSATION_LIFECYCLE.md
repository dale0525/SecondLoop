# Conversation Lifecycle

AgentWeave stores conversations as App-, agent-, tenant-, user-, and device-scoped sessions. The Desktop Host uses the same durable contract for history recovery, while mobile hosts can continue to call the Runtime storage API directly.

## HTTP contract

All routes inherit the local transport authentication and Host scope of the running sidecar.

| Method and path | Behavior |
| --- | --- |
| `POST /sessions` | Create a session with a validated title and return the complete session record |
| `GET /sessions?limit=50&cursor=…` | List a stable page ordered by most recent update |
| `GET /sessions/{id}` | Load the authoritative session, messages, and persisted runtime events |
| `PATCH /sessions/{id}` | Rename a session when `expectedUpdatedAt` still matches |
| `DELETE /sessions/{id}?expectedUpdatedAt=…` | Delete one unchanged session and its messages/events |
| `GET /sessions/{id}/messages` | Read the scoped message history compatibility view |
| `POST /sessions/{id}/messages` | Run and persist one serialized turn for that session |

Titles are trimmed, non-empty, free of control characters, and limited to 256 UTF-8 bytes. Page limits range from 1 through 100. Unknown request fields, malformed timestamps, invalid cursors, missing sessions, and cross-scope identifiers fail closed.

## Pagination

Session pages use an opaque hex-encoded, version-local cursor containing a snapshot timestamp and the last row's update time, creation time, and identifier. The storage query uses the same deterministic ordering:

```text
updated_at descending, created_at descending, id ascending
```

The first page fixes a snapshot boundary. Sessions updated after that boundary do not move into later pages, preventing duplicates while a user traverses one result set. A caller starts a fresh traversal to observe newer activity. Cursors are bounded and validated before reaching storage; they grant no scope access.

## Optimistic mutations and turn serialization

Rename and delete require the `updated_at` value last observed by the caller. If another turn or mutation changed the session, the server returns `409` with the authoritative session record. The caller must refresh and require a new explicit action instead of silently overwriting or deleting newer work.

Within one sidecar process, operations for the same session share a private asynchronous lock. A second turn loads history only after the preceding turn has committed. Rename, load, and delete use that same lock, so deletion cannot race an in-flight model turn. Different sessions remain independent. SQLite compare-and-swap conditions remain authoritative if the database changes outside that in-process coordination.

## Desktop behavior

Managed Desktop startup lists sessions and restores the most recently updated conversation. The conversation drawer uses real server data for search, selection, pagination, inline rename, and confirmed delete. It keeps the current chat intact when history listing fails and refreshes authoritative state after a `409` conflict.

Browser development uses the same route contract through the Vite development proxy. Renderer code never receives the managed sidecar origin or transport credential.
