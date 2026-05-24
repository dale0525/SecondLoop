# Design: Stitch screen 05 calendar email approval

## Architecture And Boundaries

- Keep the implementation inside the existing Flutter chat/runtime UI:
  `AgentConversationPage`, `_OperatingMessageList`, and shared
  `agent_*`/`conversation_cards` primitives.
- Treat the Stitch export as visual evidence only. Do not import or translate
  HTML directly.
- Prefer runtime-backed rendering over `AgentUiAcceptanceController` demo
  cards. The screen should be driven by `RuntimeAgentState.approvalItems`,
  conversation turns, attachment view data, context snapshot, and audit refs.
- App code may format/derive display labels from runtime records, but semantic
  decisions remain owned by runtime. The app must not infer that an event was
  created or synced before runtime approval state says so.
- Server changes are only in scope if the existing runtime payload cannot
  represent the calendar approval honestly.

## Data Flow And Contracts

1. Runtime state loads via `RuntimeAgentStateRepository.fetchAgentState`.
2. `AgentConversationPage` parses `approval_items` into
   `SecretaryRuntimeApprovalItem`.
3. `_OperatingMessageList` renders approval items:
   - existing memory card for `memory_confirmation`;
   - new/refined calendar event approval card for
     `calendar_event_confirmation`;
   - existing recurring reminder and task mutation paths remain intact.
4. Calendar event display data is derived from the approval item:
   - `calendarEventId` / `record.id`;
   - `record.title`;
   - `record.starts_at_ms` and `record.ends_at_ms`;
   - `record.participants`;
   - `record.source_message`;
   - `record.diff`;
   - `record.approval_status`;
   - optional audit/tool/sync labels from `record`, `latestContextSnapshot`,
     or `auditRefs`.
5. Approve/reject calls continue through the runtime approval service and then
   refresh runtime state.
6. Edit uses the existing approval patch service only when runtime marks a
   field editable. Otherwise render an unavailable/degraded edit state.

## UI Shape

- Mobile canonical width follows the Stitch manifest width `780`.
- The first viewport should include:
  - top app bar with managed-pro/capability signals;
  - right-aligned user prompt and attachment tile;
  - processing labels for `email-analysis`, `memory-capture`, and
    `calendar-skill`;
  - assistant response with left accent;
  - memory candidate card;
  - calendar event approval card;
  - composer and bottom nav.
- Calendar event approval card should be visually distinct from generic task
  approval:
  - calendar icon/tool label in header;
  - proposed event title;
  - schedule row;
  - attendee row;
  - pending notice;
  - audit/sync metadata;
  - Reject/Edit/Approve actions.
- The card must remain stable across narrow mobile, canonical, and desktop
  widths. Use responsive wrapping rather than letting labels overflow.

## Compatibility And Migration

- Preserve existing task mutation, recurring reminder, memory, and generic
  approval behavior.
- Do not remove the older demo `CalendarEmailCard` unless replacement is
  clearly wired everywhere it was used.
- Existing runtime payloads that omit optional calendar metadata must still
  render safely with explicit unavailable labels.
- Approval route behavior that marks a candidate approved without external
  writes is acceptable for this screen as long as the UI does not claim an
  external calendar write happened.

## Risk Points

- Multiple approval kinds in the same runtime state can regress by hiding one
  card behind another.
- Calendar timestamps may be missing or in milliseconds; formatting must handle
  zero/null without misleading output.
- Edit support may not exist for calendar approvals. A fake editable UI would
  violate the product boundary.
- The old acceptance/demo card can make the UI appear complete while bypassing
  real runtime approval state.
- Manual review requires Computer Use at manifest dimensions after automated
  checks.

## Rollback Shape

- Keep the new calendar approval rendering isolated behind
  `item.kind == 'calendar_event_confirmation'`.
- If the refined calendar surface causes regressions, it can fall back to the
  generic candidate approval card while preserving runtime approval actions.
- Server-side changes, if any are required, must remain backward compatible
  with existing approval item fields.
