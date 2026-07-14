# Scheduler Store v1

Desktop and Server expose `schedule_list`, `schedule_get`, `schedule_create`,
and `schedule_set_status`. The trusted host injects App, tenant, and user scope;
tool arguments cannot override it. Android must not advertise this package until
it provides the same bridge and failure semantics.

Supported schedules are one-shot instants, anchored intervals, timezone-aware cron expressions, and bounded RRULE subsets.

Every job binds App, tenant, user, name, schedule, misfire policy, bounded payload, status, next occurrence, and version.

Create requires a stable idempotency key. Repeating the same key and request
returns the original job. Reusing a key for different content is a conflict.
Status changes use the current optimistic version and fail on stale state.

Claims bind job ID, deterministic run ID, due time, worker, lease, and payload. An expired claim is recovered with the same run identity.

Every claim also carries the trusted schedule scope. Declarative notification
requests omit scope and inherit App, tenant, and user exclusively from that
claim. A payload that attempts to provide scope is invalid and cannot enqueue a
notification.

Misfire policy is explicit: skip with grace, fire once, or bounded catch-up. The host owns persistence, worker lifecycle, concurrency, and audit.
