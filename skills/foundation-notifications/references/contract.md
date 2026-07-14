# Notification Host v1

Desktop and Server expose `notification_list`, `notification_get`,
`notification_enqueue`, and `notification_cancel`. The trusted host injects
App, tenant, and user scope. Android must not advertise this package until a
real notification tool bridge provides the same boundaries.

Queue binds App, tenant, user, channel, title, body, deduplication key, earliest delivery time, optional quiet hours, and bounded structured data.

The deduplication key is scoped to App, tenant, user, and channel. Repeating the
same key and content returns the original record; conflicting content is
rejected. Cancellation is allowed only before delivery begins. Delivered and
uncertain records remain immutable facts for inspection and reconciliation.

Scheduler execution may enqueue a notification, but its run state remains separate from notification delivery state.

The host claims due notifications with a lease and records delivered, retryable failure, permanent failure, or uncertain. An expired delivering lease becomes uncertain and requires reconciliation.

The host owns operating-system permission, presentation, privacy policy, channel registration, and platform delivery identifiers.
