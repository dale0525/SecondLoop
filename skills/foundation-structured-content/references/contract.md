# Structured Content Host Contract

## Public card

The base AgentWeave card payload accepts this shape:

```json
{
  "title": "Reminder preview",
  "summary": "Runs every weekday.",
  "status": { "label": "Ready to schedule", "tone": "info" },
  "fields": [{ "label": "Timezone", "value": "Asia/Shanghai" }],
  "actions": [{ "id": "confirm", "label": "Confirm", "style": "primary" }]
}
```

The Runtime adds `actionBindings` with opaque binding IDs. Never supply that field yourself.

Allowed status tones are `neutral`, `info`, `success`, `warning`, and `danger`. Allowed action styles are `primary`, `secondary`, and `danger`.

## Safe A2UI subset

Use MIME `application/vnd.a2ui.safe-card+json` with schema version `0.8` or `1`. The public payload has a `components` array and may also have the same top-level `actions` used by the base card:

```json
{
  "components": [
    { "type": "text", "style": "heading", "text": "Connect workspace" },
    { "type": "status", "label": "Not connected", "tone": "warning" },
    { "type": "field", "label": "Provider", "value": "Google Workspace" },
    { "type": "list", "items": ["Mail", "Calendar", "Contacts"] }
  ],
  "actions": [{ "id": "connect", "label": "Connect", "style": "primary" }]
}
```

Text styles are `heading`, `body`, and `caption`. The adapter rejects every other component, property, active-content field, URL field, or credential-shaped field and falls back to plain text. The Runtime adds opaque `actionBindings`; never include them in model-authored payloads.

## Binding

Each binding contains `actionId`, `intent`, `idempotencyKey`, `expiresAt`, private `parameters`, an optional restricted `inputSchema`, and optional `constraints`.

Supported intents are:

- `oauth.start`, `oauth.status`, and `oauth.cancel`;
- `schedule.create` and `schedule.status`.

An empty input schema is:

```json
{
  "type": "object",
  "properties": {},
  "required": [],
  "additionalProperties": false
}
```

OAuth start constraints must contain exactly the provider IDs, connector IDs, and capabilities requested by the private parameters. Schedule parameters use the same trusted Scheduler shapes as `schedule_create` or `schedule_set_status`.

## Revisions and events

The first revision is `1`. An update supplies the current content ID and `expectedRevision`; the Host publishes the next revision atomically. Deletion creates a permanent tombstone at the next revision.

Action receipts and later OAuth callbacks are persisted as session events. Clients replay them through the session cursor, including after the originating turn has finished or the App has restarted.
