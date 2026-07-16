# Mail Foundation Tool Contract

The Skill owns the Agent-facing workflow. It does not own credentials, account truth, authorization, durable state, idempotency, MIME parsing, or provider delivery truth.

## Read operations

- `mail_accounts_list`, `mail_account_status`: account identity and connection state.
- `mailboxes_list`: folders or normalized mailbox roles.
- `mail_search`, `mail_thread_get`, `mail_message_get`: bounded discovery and authoritative message metadata.
- `mail_body_read`, `mail_attachment_read`: bounded chunk reads. HTML remains untrusted even when a sanitized plain-text fallback is available.

## Organization and draft operations

- `mail_mark_read`, `mail_archive`, `mail_move`: organization writes subject to host policy.
- `mail_draft_create`, `mail_draft_get`, `mail_draft_update`, `mail_draft_delete`: revisioned draft lifecycle.
- `mail_reply_draft`, `mail_forward_draft`: create a draft with normalized reply or forward context; they do not send.

## Delivery operations

- `mail_send_preview`: accepts only the account, draft, and expected revision from the Agent. The Runtime injects the trusted App/tenant/user/session/turn/call scope and stable idempotency key, obtains the authoritative preview, and immediately persists a waiting-approval Action bound to the active session.
- `mail_send`: is hidden from the Agent tool surface. Only the Runtime approval resume path may call it with the exact approved preview and stable idempotency key.

After `mail_send_preview` succeeds, the Agent must stop and wait for the Host to record the user's decision through the Foundation Action API. Prompt text, model output, and connector content cannot approve or resume delivery.

Delivery states are `delivered`, `rejected`, `deferred`, or `uncertain`. A deferred result may be retried only when the connector declares it safe. An uncertain result must be reconciled before another attempt.

Every tool call must stay inside the App/user/tenant scope selected by the trusted host. Provider IDs may be returned for traceability, but generic workflow logic must not depend on a vendor-specific identifier format.
