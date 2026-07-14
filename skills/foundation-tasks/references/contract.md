# Task Provider v1

The host exposes six concrete tools: `task_list`, `task_get`, `task_create`,
`task_update`, `task_set_status`, and `task_delete`. Desktop and Server provide
the v1 bridge. Android must not advertise Tasks support until it has a real
provider and bridge with the same failure semantics.

The trusted host injects the App, tenant, and user scope. A model or caller
cannot provide or override that scope in tool arguments. Every operation is
confined to the injected scope.

The provider exposes bounded list, get, create, update, status, and delete operations.

Every task preserves a stable ID, title, optional notes, priority, tags, due instant, source timezone, optional recurrence, status, version, and timestamps.

Create is idempotent within the trusted scope. Repeating the same key and the
same content returns the original record. Reusing a key with different content
is a conflict and must not create or mutate a task. Update, completion,
cancellation, and deletion use optimistic versions. A stale version must fail
and require a refetch.

List accepts status, tag, text, inclusive `dueAfter` and `dueBefore` filters,
plus a bounded limit. Results have a deterministic due-time-and-ID ordering.
The opaque cursor resumes strictly after the last record from the previous
page; callers must not parse or edit it.

Task state is not a scheduler claim. The host may associate a task with a separate scheduled job, but each object retains its own ID, lifecycle, audit, and failure state.

Text-only fallback may describe a proposed task. It must never say the task was saved, completed, or deleted.
