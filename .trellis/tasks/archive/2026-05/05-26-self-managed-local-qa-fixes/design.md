# Design

## Boundary

The App is already connected to a user-owned self-managed Cloudflare runtime.
Ready-mode QA exercises the App against the deployed local QA worker generated
by `tools/self_managed_runtime_lib/local_qa_worker_script.dart`.

The worker owns deterministic contract responses for local QA. App UI changes
are out of scope unless the deployed runtime returns the correct metadata and
the App fails to render or act on it.

## Contract Shape

- Conversation messages are stored in worker state per vault/conversation.
- Formal side effects that require consent are represented as approval items.
- Approved memory candidates move from `approval_items` into
  `memory_records`.
- Approved recurring reminders move from `approval_items` into
  `recurring_reminder_rules` with `approval_status: approved`.
- Ambiguous task mutation requests return `clarification_required` and do not
  create an approval.
- Missing-slot reminder requests return `clarification_required` until the user
  supplies the missing birthday.

## Compatibility

The worker contract follows the existing App models:

- `memory_confirmation`
- `task_mutation_confirmation`
- `recurring_reminder_confirmation`
- `recurring_reminder_candidate`

No runtime profile, provider secret, Cloudflare token, or local OAuth cache path
is persisted into tracked reports beyond generic operational notes.

## Rollback

If a worker-only fix regresses manual QA, revert the worker contract change and
redeploy the previous generated worker script. App rebuild is not required for
worker-only contract updates.
