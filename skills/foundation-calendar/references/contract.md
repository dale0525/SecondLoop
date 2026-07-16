# Calendar Connector v1

The host owns scope, credentials, permissions, approval, idempotency, audit, and delivery. The skill owns workflow selection and clear user-facing state.

Required operations:

- `calendar_events_list` lists events within a bounded time range.
- `calendar_free_busy` reads free-busy intervals.
- `calendar_event_get` inspects one authoritative provider event.
- `calendar_event_create_preview`, `calendar_event_update_preview`, and `calendar_event_cancel_preview` create immutable mutation previews without changing provider state.
- `calendar_event_apply` applies one approved immutable preview.

Every event must preserve a stable ID, calendar ID, start and end instants, source timezone, attendees, recurrence, status, provider reference, and optimistic version.

Attendee-visible mutations require approval. A preview hash must bind the event version, time, timezone, attendees, location, recurrence, conflicts, account, and idempotency key.

The Host persists create, update, and cancel requests as `calendar.event.create`, `calendar.event.update`, and `calendar.event.cancel` Foundation Actions. The persisted envelope binds the connector and operation, account, event or calendar resource, expected event version, effect class, idempotency key, complete preview payload, payload hash, and approval summary. Only the Host may exchange an approved envelope for a one-shot `calendar_event_apply` grant.

The App, tenant, and user scope comes from trusted Host context. A model-supplied account ID must match the account selected by that context when the Host has selected one. Reusing an idempotency key with a different preview fails closed.

Do not silently flatten unsupported recurrence rules, provider-specific calendars, or timezone transitions. Return a deterministic unsupported or conflict result.
