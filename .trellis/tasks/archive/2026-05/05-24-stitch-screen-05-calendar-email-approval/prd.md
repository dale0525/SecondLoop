# Stitch screen 05 calendar email approval

## Goal

Implement and verify the fifth canonical Stitch product screen:
`Calendar Approval: Email Extraction (Approved)`.

The screen demonstrates a runtime-first email/calendar flow where the user asks
the agent to extract travel dates from an attached email, the app shows the
email attachment and processing chain, the runtime proposes a memory candidate
for the trip, and a calendar event candidate remains pending until the user
approves it.

## Confirmed Facts

- Stitch screenId:
  `585ce0f7d36b4f55a8511bea0e2ef655`.
- Manifest dimensions: mobile, width `780`, height `2172`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/14-calendar-approval-email-extraction-585ce0f7d36b4f55a8511bea0e2ef655.html`
  - `docs/stitch-export/secondloop-operating-system/screens/14-calendar-approval-email-extraction-585ce0f7d36b4f55a8511bea0e2ef655.jpg`
- Stitch source shows:
  - user prompt `Extract my travel dates from the attached email.`;
  - attachment tile `Fwd: Itinerary for NYC Trip - June`, `14 KB`, `PDF`;
  - processing chain `email-analysis -> memory-capture -> calendar-skill`;
  - assistant response saying it found upcoming travel to New York City and a
    related calendar action;
  - a `Memory Candidate` card for `Travel: NYC June 10-15, 2026`;
  - a `Calendar Event Approval` card for
    `Meeting with NYC Design Team`,
    `June 12, 2026, 10:00 AM - 11:00 AM`, and attendees
    `Sarah J., Mike T., Elena R.`;
  - explicit pending notice:
    `Event will not be created until approved by user account owner.`;
  - approval metadata including `calendar_tool`, audit id
    `cal_2026_06_12`, sync priority `Standard`, and Reject/Edit/Approve
    actions.
- Product docs define the email/calendar boundary:
  - unauthorized email/calendar must degrade to draft,
    `needs_configuration`, or `tool_unavailable`;
  - authorized reads are low risk;
  - sending email, creating calendar events, sending invites, and other
    external side effects require approval;
  - runtime must not claim an external action has executed unless it actually
    completed.
- Product docs also require runtime/audit visibility for approval items,
  approval patches, tool traces, audit events, recent entity refs, and context
  snapshots.
- Development docs define the phase 5 target:
  - implement `email` skill contract with unauthorized draft/configuration
    degradation, authorized read, and send approval;
  - implement `calendar` skill contract with read/write permission separation
    and event creation/update approval;
  - App displays media job state, sources, summaries, extracted fields, and
    approval cards.
- QA docs require a real App/manual QA path for email/calendar only when a
  testable email/calendar OAuth account is available; otherwise this must be
  recorded as not manually covered rather than implied.
- SecondLoopServer already has runtime contract support for:
  - `calendar_event_candidate` response metadata;
  - `calendar_event_confirmation` approval items with `calendar_event_id` and
    `record`;
  - approval routes that mark calendar event candidates approved without
    pretending to perform an external write;
  - model gateway instructions that calendar creation/invite requests must
    return approval-required calendar event candidates.
- Existing app code already parses generic runtime approval fields:
  `id`, `kind`, `email_draft_id`, `calendar_event_id`, `record`,
  `editable_fields`, `version`, and `source_intent_id`.
- Existing app UI has older/demo calendar-email surfaces in
  `CalendarEmailCard`, `AgentUiAcceptanceController.simulateCalendarEmail()`,
  and `agent_calendar_email_*_storyboard.dart`, but the runtime approval path
  currently focuses on memory, recurring reminder, and task mutation approval
  rendering.
- User-supplied implementation contract inherited from the parent task:
  - use only `docs/stitch-export/secondloop-operating-system/` as the Stitch
    source;
  - read README, manifest, corresponding HTML/screenshot, final product shape,
    QA acceptance, and development plan before implementation;
  - implement only canonical register product screens;
  - treat retired/superseded screens as negative examples only;
  - fill real functionality/state/API wiring before visual polish;
  - perform Computer Use review at manifest dimensions before completion;
  - run fresh `pixi` verification and report exact evidence.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `585ce0f7d36b4f55a8511bea0e2ef655` | `AppShell` Chat tab -> `AgentConversationPage` mobile operating shell -> `_OperatingMessageList` approval/result surfaces in `agent_conversation_layouts.dart`, `agent_conversation_page.dart`, `agent_conversation_attachments.dart`, `agent_operating_system_cards.dart`, and calendar/email card primitives; runtime state from `RuntimeAgentState.conversationTurns`, `RuntimeAgentState.approvalItems`, `RuntimeAgentState.memoryRecords`, `RuntimeAgentState.workingSetRecords`, `RuntimeAgentState.latestContextSnapshot`, and `RuntimeAgentState.auditRefs`; API through `RuntimeSecretaryAppService.approveApprovalItem`, `rejectApprovalItem`, approval patch/degraded edit handling, and existing runtime state refresh. |

## Stitch-vs-Local Difference List Before Implementation

- UI differences:
  - Stitch shows a compact managed-pro top bar with email/calendar capability
    signals, a right-aligned user message, a dedicated email attachment tile,
    horizontal processing chips, a left-accent assistant response, a memory
    candidate card, and a calendar event approval card.
  - Current local runtime approval UI has strong task mutation and reminder
    surfaces, but does not yet have a Stitch-matched
    `calendar_event_confirmation` card with proposed event details, calendar
    tool metadata, pending notice, audit id, sync priority, and
    Reject/Edit/Approve action layout.
  - Existing `CalendarEmailCard` is a demo/acceptance card for availability,
    invite, and email draft examples; it is not yet the canonical runtime
    screen 05 surface.
- Functionality differences:
  - Stitch implies email attachment understanding, memory capture, and calendar
    event candidate creation in one conversation result.
  - Local App must render real runtime state and approval items rather than
    relying on `AgentUiAcceptanceController` demo simulation.
  - Approve/reject must call the existing runtime approval service and refresh
    state. Edit must be backed by a real approval patch path if supported, or
    visibly degrade as unavailable.
- State-flow differences:
  - The proposed calendar event must remain pending until approval succeeds.
  - The memory candidate and calendar approval may coexist in one runtime
    state. The UI must not hide one approval because another kind is present.
  - Attachment and extracted-event context should stay tied to the relevant
    conversation turn/context snapshot, not a global mock.
- Data/API wiring differences:
  - Runtime currently exposes calendar approvals through
    `calendar_event_confirmation` with `calendar_event_id` and `record`.
  - The App must safely derive title, start/end time, attendees, source message,
    diff, audit/tool metadata, and approval status from `record`,
    `latestContextSnapshot`, `auditRefs`, or explicit degraded values.
  - If runtime payloads lack a field needed for an honest user-facing card, the
    App must show a clear unavailable/degraded value and identify whether a
    `SecondLoopServer` change is required before claiming full screen
    completion.

## Requirements

- Implement the screen through existing Flutter architecture. Do not paste
  Stitch HTML.
- The fixture/user flow must include:
  - user message: `Extract my travel dates from the attached email.`;
  - email attachment tile:
    `Fwd: Itinerary for NYC Trip - June`, `14 KB`, `PDF`;
  - processing labels equivalent to
    `email-analysis`, `memory-capture`, and `calendar-skill`;
  - assistant response explaining the email was analyzed and a New York City
    travel/calendar action was found.
- The runtime-backed UI must support at least these approval kinds together:
  - `memory_confirmation`;
  - `calendar_event_confirmation`.
- The memory candidate surface must show the extracted trip memory, source,
  risk level, and approve/dismiss actions through the real runtime approval
  path.
- The calendar event approval surface must show:
  - proposed event title;
  - start/end time;
  - participants/attendees;
  - calendar tool/source label;
  - pending notice that no event is created until approved;
  - audit id or equivalent trace reference;
  - sync priority or an honest unavailable/degraded value;
  - Reject/Edit/Approve actions.
- Approve/reject controls must use the real runtime approval sender/service and
  refresh visible runtime state after completion.
- Edit must either patch the approval through a real runtime capability or
  visibly degrade with an honest unavailable/error state. Do not ship a fake
  edit path.
- Preserve product boundaries:
  - authorized email/calendar reads are low risk;
  - calendar event creation/update is an external side effect and requires
    approval;
  - unavailable connector/permission states degrade to draft,
    `needs_configuration`, or `tool_unavailable`;
  - the app must not claim a calendar event was created unless the runtime says
    it was actually completed.
- Match the local Stitch screenshot/HTML first viewport, attachment tile,
  processing chain, memory candidate, calendar event approval hierarchy,
  actions, composer, and bottom navigation as closely as possible within the
  existing Flutter architecture.
- Do not track or edit `docs/`; the local Stitch export is a design baseline.
- If app-side runtime/API wiring is insufficient, identify whether a real
  server change is required in
  `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer` before
  claiming the screen is complete.

## Acceptance Criteria

- [ ] A screen 05 mapping table and Stitch-vs-local difference list exist
      before implementation.
- [ ] The rendered UI matches the canonical Stitch first viewport, attachment
      tile, processing labels, assistant response, memory candidate, calendar
      event approval hierarchy, metadata, pending notice, actions, composer,
      and bottom nav as closely as the app architecture allows.
- [ ] A runtime-state fixture can render both `memory_confirmation` and
      `calendar_event_confirmation` approval items in the same conversation.
- [ ] The calendar event remains pending before approval and is not represented
      as created/synced until runtime approval succeeds.
- [ ] Approve/reject controls are wired to the runtime approval flow and expose
      busy/error state.
- [ ] Edit is backed by runtime patch behavior or visibly degraded with a clear
      unavailable state.
- [ ] Calendar approval details include event title, date/time, attendees,
      source/tool metadata, audit or trace reference, and sync priority or a
      clearly labeled degraded value.
- [ ] Existing demo/acceptance `CalendarEmailCard` usage is not treated as a
      substitute for runtime-backed screen 05 behavior.
- [ ] A focused widget test covers the runtime-state fixture for screen 05.
- [ ] The screen-specific widget test includes a responsive width matrix for
      narrow mobile, manifest width `780`, and desktop width.
- [ ] Existing runtime approval tests continue to pass or are updated to the
      refined contract without weakening runtime-first behavior.
- [ ] Computer Use manual review is performed at manifest width after the UI
      changes.
- [ ] Relevant `pixi` checks pass with fresh evidence, including focused tests,
      analyzer/typecheck, build or documented build-equivalent gate, and
      changed-file verification.
- [ ] Completion output includes screenId, mapping, functionality filled,
      modified files, screenshot/manual verification result, known non-1:1
      differences, and commands run.

## Out of Scope

- Implementing screen 06 file OCR or later canonical screens.
- Implementing retired/superseded calendar/email designs.
- Replacing app architecture with generated Stitch HTML.
- Claiming real external calendar creation, invite sending, or email sending
  when the runtime only marks a candidate approved.
- Building a full email/calendar OAuth setup flow unless the screen cannot
  honestly degrade without it.
- Backend deployment unless the existing app cannot represent the required
  runtime state or approval flow without a server contract change.

## Open Questions

- None currently. The screen scope and product behavior are defined by the
  canonical Stitch register, final product docs, QA acceptance docs, current
  SecondLoopServer runtime contract, and the existing parent task mapping.

## Notes

- This is a complex child task because it spans runtime-state rendering,
  approval actions, calendar/email product boundaries, responsive UI, and
  manual review. Add `design.md` and `implement.md` before `task.py start`.
