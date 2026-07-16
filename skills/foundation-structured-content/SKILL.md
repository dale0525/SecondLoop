---
name: foundation-structured-content
description: Publish, update, and remove safe declarative chat cards with opaque trusted actions. Use for OAuth consent buttons, schedule or reminder confirmations, durable progress/status cards, A2UI components, or any workflow that needs more structure than Markdown without adding a product-specific page.
---

# Foundation Structured Content

Keep the normal conversation as the workspace. Use Markdown for ordinary answers and this Skill only when the user needs a preview, explicit action, or durable state.

Read [references/contract.md](references/contract.md) before publishing an interactive card.

## Publish safely

1. Separate public display state from private Host parameters.
2. Choose `application/vnd.agentweave.card+json` for standard cards. Use a supported A2UI MIME only when its allowlisted components materially improve the interaction.
3. Provide a useful plain-text fallback for every card.
4. Put trusted operation parameters in action bindings, never in the public payload.
5. Update an existing card with its content ID and expected revision. Do not reuse a deleted content ID.

Use only text, status, fields, lists, and labeled actions. Do not publish HTML, script, iframe, remote image, arbitrary URL, authorization URL, OAuth state, token, password, client secret, cookie, or credential-shaped fields.

## Bind actions

Give each action a stable ID, a stable idempotency key, an expiry no more than 24 hours away, and the narrowest supported input schema. Use an empty object schema when no user input is required.

For `oauth.start`, bind the exact provider, connectors, and capabilities in both private parameters and constraints. Let the trusted Host open the browser and publish the callback result as a later revision.

Publish any later `oauth.status` or `oauth.cancel` action as a new revision of that same content card. The Host rejects authorization IDs originating from another card or conversation.

For `schedule.create`, show the timezone, first occurrence, recurrence, notification text, and misfire behavior before confirmation. Put App, tenant, and user scope nowhere in the binding; the Host injects them. Treat a notification `dedupeKey` as a stable seed for per-run delivery identity.

After action acceptance, rely on the Host-published revision for authoritative status. Do not claim success from the click alone.

## Recover and revise

Use `structured_content_get` before changing a card when the current revision is uncertain. On a revision conflict, read the current card and decide whether the intended update is still valid. Delete only with the current revision.

Unknown MIME types render only their fallback text. Design the fallback so the conversation remains understandable even when no adapter is installed.
