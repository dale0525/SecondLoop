# Streaming Turn Lifecycle

AgentWeave Desktop uses a durable, cursor-based event feed for long-running conversation turns. The feed is transported through trusted Electron IPC, so the Renderer never receives the sidecar transport credential or the stored model API key.

## Contract

`POST /sessions/{session_id}/turns` accepts a bounded `content` string and a caller-generated `requestId`. The pair `(session_id, requestId)` is idempotent. A successful new request returns `202 Accepted`; an exact replay returns the existing turn without inserting another user message.

The Runtime creates the turn ledger row and user message in one transaction before model execution starts. A session has at most one `running` turn. The durable turn identifier is also passed into the Runtime, so `turn_started`, terminal events, event records, cancellation, and replay all refer to the same identity.

`GET /sessions/{session_id}/turns/{turn_id}/events` returns events after the durable history boundary expressed by `after`. The response contains the next event index, the authoritative turn state, and a `hasMore` flag. `waitMs` enables bounded long polling up to 25 seconds. Clients reconnect with the last successfully rendered cursor and deduplicate records by event ID.

`POST /sessions/{session_id}/turns/{turn_id}/cancel` requests cancellation of the active execution. Cancellation is cooperative at the server task boundary and produces one durable `turn_cancelled` terminal event. Repeated cancellation after a terminal state is a no-op.

## Durable states

- `running`: execution can still publish events.
- `completed`: the terminal event and assistant message were committed together.
- `failed`: execution ended with a durable failure boundary.
- `cancelled`: the user requested a safe stop.
- `interrupted`: process recovery found a turn that was still `running`.

Non-terminal events are appended before they become available to replay. A completed assistant message, terminal event, turn status, and session timestamp are committed in one transaction. Late events are rejected after a terminal state.

## Recovery

On storage startup, every leftover `running` turn is changed to `interrupted` and receives a durable `turn_failed` event with a stable restart message. Previously persisted deltas remain replayable. Desktop keeps the rendered partial response, asks the sidecar supervisor to recover, and resumes from the last event cursor. If the process restarted, the first replay returns the authoritative `interrupted` terminal state instead of silently losing the request.

Loading a session returns messages, runtime events, and turn ledger rows. This lets a new Renderer restore a live turn after a window reload, or explain an interrupted turn after a sidecar restart.

## Compatibility and limits

The synchronous `POST /sessions/{session_id}/messages` endpoint remains available for existing integrations. New Desktop conversation flows use the durable turn endpoints. Event pages are limited to 100 records, request identifiers to 128 portable characters, and request content to 1 MiB.

The event feed is scoped by App, agent, tenant, user, device, session, and turn. Electron exposes only fixed typed operations for starting a turn, replaying events, and cancelling; arbitrary Renderer URLs remain forbidden.
