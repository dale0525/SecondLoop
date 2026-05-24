# Stitch screen 03 reminder clarification design

## Evidence

- Active child task:
  `05-24-stitch-screen-03-reminder-clarification`.
- Parent coordination task:
  `05-24-stitch-canonical-screen-continuation`.
- Stitch source:
  `docs/stitch-export/secondloop-operating-system/html/12-chat-recurring-reminder-clarification-2584c8e54d014209adbd37b562e3ced1.html`.
- Stitch screenshot:
  `docs/stitch-export/secondloop-operating-system/screens/12-chat-recurring-reminder-clarification-2584c8e54d014209adbd37b562e3ced1.jpg`.
- Stitch metadata:
  mobile, width `780`, height `2436`, screenId
  `2584c8e54d014209adbd37b562e3ced1`.
- Source-of-truth entry:
  `3b8ef30093554bf2bc42e296ee36be6c`.
- Canonical register:
  `a5874f74133b435a9feb498e76a23fe4`.
- Negative-only sources:
  retired register `43a2a241349e40a4b3dd3d61c0d3c76b`, superseded incomplete
  index `3aa56b7a88194a37a3c38abb3ef76618`.
- Product acceptance source:
  `docs/qa/final-product-acceptance.md` QA-REM-01 through QA-REM-03.
- Product architecture source:
  `docs/development/final-product-development-plan.md`, runtime state node /
  event model for pending intent, clarification, approval, memory, and recurring
  reminder.
- Relevant frontend specs:
  `.trellis/spec/frontend/component-guidelines.md`,
  `.trellis/spec/frontend/state-management.md`,
  `.trellis/spec/frontend/type-safety.md`,
  `.trellis/spec/frontend/quality-guidelines.md`.
- Relevant backend/client specs:
  `.trellis/spec/backend/api-client-guidelines.md`,
  `.trellis/spec/backend/quality-guidelines.md`.

## Screen mapping

| Stitch element | Local route/component/API | Notes |
| --- | --- | --- |
| `Chat: Recurring Reminder Clarification (Approved)` | `AppShell` Chat tab -> `AgentConversationPage` | `AppShell` uses bottom nav below `960px`; the screen's `780px` manifest width lands in the mobile shell. |
| Top app bar, Managed Pro chip, bottom nav | `lib/app/router.dart`, `_buildOperatingSystemMobileShell` in `agent_conversation_layouts.dart` | Screen 1/2 already established this canonical mobile shell. |
| Chat turns | `RuntimeAgentState.conversationTurns` -> `AgentConversationPage._loadRuntimeAgentState` -> `_OperatingMessageList` | User and assistant text should remain runtime-state-driven, not hard-coded page copy. |
| Pending intent / action halted card | Runtime state working-set/state record rendered in `_OperatingMessageList` | Use explicit machine-readable runtime state, not assistant text parsing. |
| Memory candidate | `approval_items[]` with `kind: memory_confirmation` -> `_OperatingMemoryCandidateCard` | Existing operating card exists and is runtime approval backed. |
| Recurring reminder candidate | `approval_items[]` with `kind: recurring_reminder_confirmation` -> new operating recurring reminder candidate card | Existing generic runtime approval card supports approve/reject/edit, but the mobile operating shell does not render it when memory candidates are present. |
| Approve / dismiss / edit actions | `_resolveRuntimeApproval`, `_patchRuntimeApprovalTitle`, `RuntimeSecretaryAppService`, `ChatRuntimeApprovalSender` | Must call the runtime approval path or visibly degrade through the existing error state. |
| Active recurring reminder after approval | `RuntimeAgentState.recurringReminderRules` and task/reminder surfaces | Screen 03 only proves the pre-approval candidate state; QA-REM-03 full post-approval visibility can remain a follow-up unless needed by the screen fixture. |

## Stitch-vs-local difference list

1. Stitch shows a `Pending Intent` card after the first assistant clarification,
   with `Action Halted`, `Missing Slot: child birthday`, and reasoning text.
   Current local operating chat has no pending-intent card renderer.
2. Stitch shows memory and recurring-reminder candidate cards together after the
   second assistant message. Current `_OperatingMessageList._approvalCards()`
   renders memory approvals and suppresses non-memory runtime approvals when
   any memory approval exists.
3. Stitch's recurring reminder card is domain-specific: title
   `给孩子买生日礼物`, schedule `Every year on May 31`, next trigger, risk, audit,
   edit, approve, dismiss, and the note that no recurring reminder is active
   until approval. Current generic runtime approval card lacks the operating
   shell visual structure and schedule/next-trigger presentation.
4. Stitch's candidate buttons are card-footer actions. Current operating memory
   candidate uses inline buttons in the card body. This can be close enough if
   spacing and hierarchy match, but screen 03 should avoid fake controls.
5. Stitch's normal composer placeholder is `Type a message or command...`.
   Current non-follow-up operating composer says `Type instructions or data...`.
6. The Stitch export uses a remote generated profile image. The local app should
   keep the existing app/avatar behavior and not depend on remote image assets.

## Screenshot baseline notes

The local screen 03 screenshot shows these visual anchors that must be checked
in Computer Use:

- top app bar with `SecondLoop Agent`, `Managed Pro`, notification and overflow
  controls;
- date chip `May 12, 2026`;
- first user bubble right-aligned, assistant clarification left-aligned;
- pending intent card directly below the clarification with `Action Halted`;
- second user bubble followed by the two candidate cards;
- recurring reminder card footer has `Approve`, `Edit`, and `Dismiss`;
- note below recurring reminder card says no recurring reminder is active until
  approved;
- bottom composer and five-item bottom nav are visible at the manifest width.

## Runtime state contract

The UI must render from machine-readable runtime state:

- `conversation_turns`: four turns for the canonical fixture:
  first reminder request, clarification response, birthday follow-up, candidate
  response.
- Pending intent state: represent the halted reminder intent as a runtime state
  record, preferably in `working_set_records` with `kind: pending_intent`,
  `source_message_id` or equivalent source field, `status`, `missing_slots`,
  and `reasoning`. If the server later exposes first-class `pending_intents`,
  the UI projection can be extended without changing the card contract.
- `approval_items`: include one `memory_confirmation` item and one
  `recurring_reminder_confirmation` item. Both must have stable IDs and records
  with enough fields for the cards:
  - memory: `text`, `conflict_risk`, `audit_id`
  - recurring reminder: `title`, schedule label, next trigger label,
    risk assessment, audit ID, `editable_fields: ["title"]`, and `version`
- `recurring_reminder_rules`: empty before approval so the UI does not present
  an active reminder prematurely.

The app must not parse the Chinese prompt locally to infer birthday dates or
execute reminder mutation. Runtime owns semantics; the Flutter layer renders
state and sends approval/edit decisions.

## UI architecture

- Keep changes inside existing Agent UI parts:
  - `agent_conversation_layouts.dart` for message-list orchestration and
    callback plumbing.
  - `agent_operating_system_cards.dart` for operating-shell cards.
  - `agent_operating_system_tokens.dart` only if existing tokens cannot express
    the required spacing or tone.
  - `agent_conversation_page.dart` for callback routing only.
- Prefer small private widgets over expanding already-large files unnecessarily.
  Current relevant source files are under 1000 lines, but close to the limit;
  if any non-document file crosses 1000 lines during implementation, refactor
  before continuing.
- Keep runtime approval actions unified:
  memory and recurring cards should call the same `_resolveRuntimeApproval`
  path, and recurring title edits should call `_patchRuntimeApprovalTitle`.
- Add stable `ValueKey` handles for pending intent and recurring reminder
  candidate cards/buttons so widget tests and manual QA can locate them.

## Compatibility and degradation

- Existing runtime states without pending-intent records should render normally.
- Existing memory-only approval tests must continue passing.
- Existing recurring title-edit behavior must continue working.
- If the sender/runtime cannot approve, reject, or patch, reuse the existing
  page-level `_askError` degraded state instead of showing controls that appear
  successful.
- Do not modify Stitch export HTML/screenshots or track generated `docs/`
  content.
- If runtime approval sender capabilities are missing, controls must visibly
  degrade through the existing error state or disabled/unavailable state; never
  appear to succeed locally.
- If server support is missing for pending-intent or recurring-reminder runtime
  state, implement the required contract in the `SecondLoopServer` local main
  branch and push for staging rather than faking app-local semantics.

## Validation target

- Add a focused screen 03 widget test at `780x2436` (or a locally practical
  equivalent preserving width) using a runtime-state fixture.
- Verify:
  - pending intent appears after the clarification,
  - no active recurring reminder is shown before approval,
  - memory and recurring candidate cards both appear,
  - recurring reminder title is action-oriented,
  - approve/edit/dismiss affordances are present and wired,
  - bottom nav and composer remain visible.
