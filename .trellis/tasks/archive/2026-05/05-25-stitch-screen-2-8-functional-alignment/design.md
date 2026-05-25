# Stitch screen 2-8 functional alignment design

## Architecture

The frontend must remain a runtime-first Flutter client. `AgentConversationPage`
renders conversation turns, working-set records, approval items, attachments,
media results, and context snapshots from `RuntimeAgentState` loaded through
`RuntimeAgentStateRepository`. User actions go through
`RuntimeSecretaryAppService` and the `SecretaryRuntimeConversationSender`
interfaces.

The Server runtime must be the semantic and mutation authority. When Stitch UI
requires a pending intent, draft, blocked action, media result, or approval
candidate, the Server must expose it through conversation result metadata and/or
`GET /agent-state`; the App may project and render that state but must not
invent the semantic result locally.

## Boundaries

- App owns rendering, optimistic local attachment previews, safe degraded UI,
  and action buttons that call runtime APIs.
- Server owns intent interpretation, pending intents, target resolution,
  approval queue records, media result persistence, draft/degraded tool state,
  and formal mutation application after approval.
- Vault/working-set records remain the durable view input for tasks, memory, and
  media records.
- Runtime agent view state may include runtime-owned projection records such as
  pending intents, email drafts, and blocked external tool records when they are
  needed for UI display and are not durable working-set facts.

## Data Flow

1. User sends text and optional attachments from `AgentConversationPage`.
2. `sendAgentConversationMessage` routes to cloud runtime and sends attachment
   payloads through `SecretaryRuntimeConversationSender`.
3. Server stores conversation turns, evaluates runtime/tool outcomes, records
   pending state, approval items, media results, drafts, and audit/context refs.
4. App refreshes `RuntimeAgentState` after send/approve/reject/patch.
5. UI renders from the refreshed view state, with send-result fallback only when
   the runtime view state has not caught up.
6. Approval actions call runtime decision or patch APIs, then refresh the view
   state again.

## Runtime Contract Updates

- Pending intents: expose open clarification/pending intent records in
  `agent-state` with kind `pending_intent`, source turn ids, missing slot,
  reasoning, and halted status.
- Task title mutations: approval records for title changes must include
  `editable_fields: ['title']`, `current_title`, `proposed_title`, target id,
  resolver detail, audit/context/tool metadata when available, and pending
  notice.
- Calendar plus memory extraction: a calendar-event candidate response may also
  carry memory candidates; Server should queue both approval kinds in the same
  run.
- Media results: preserve runtime media fields rather than narrowing them to
  only transcript/OCR/summary. Required fields include attachment/source ids,
  confidence, saved-to-vault/sync state, meeting id, duration, high-fidelity
  confirmation, decisions, action items, citations, status, and provider.
- Media action/reminder candidates: if runtime returns action or reminder
  candidates with a media result, they must become approval items. Approving an
  action item should create the corresponding runtime/vault task or clearly
  record a degraded state; rejecting should remove or mark the candidate.
- Unauthorized email: `needs_configuration` / `tool_unavailable` for email may
  include a draft. The runtime should expose draft-only and blocked-tool records
  in `agent-state`, without send approval and without external side effects.

## Frontend Contract Updates

- Keep existing screen fixture tests as visual regression coverage.
- Add functional projection tests that start with empty/runtime-initial state,
  send a user message or attachment through fake senders, refresh a repository
  state shaped like real Server output, and assert visible UI plus actions.
- Prefer shared projection helpers already used by `AgentConversationPage`; add
  typed parsing only where the current projection cannot consume real runtime
  fields.
- Degraded buttons must be explicit and honest: disabled state, snackbar, or
  unavailable label is acceptable; silent no-op is not.

## Compatibility

- Existing fake fixtures should keep working.
- Existing Server response fields remain accepted.
- New view-state records should be additive.
- Server file length rule matters: `runtime_tools.js` is near 1000 lines, so
  changes there should extract helper modules rather than expanding the file.

## Risks

- Real Server changes may affect staging acceptance; keep tests protocol-level
  and avoid secrets.
- Adding projection records to `agent-state` must not turn draft/pending state
  into approved facts.
- Action item approval must not create tasks before user approval.
- Email draft-only must not accidentally reuse `email_send_confirmation`.

## Rollback

- Frontend changes can be reverted per screen if a projection regression occurs.
- Server changes should be isolated to additive runtime contract helpers and
  tests; if a runtime change breaks staging, disable the new projection branch
  while preserving existing approval behavior.
