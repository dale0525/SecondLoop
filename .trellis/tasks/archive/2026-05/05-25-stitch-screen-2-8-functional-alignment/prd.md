# Stitch screen 2-8 functional alignment

## Goal

Bring canonical Stitch screens 2 through 8 from visual-only alignment to real
functional alignment. The work must verify and fill the runtime/state/API
wiring that backs the already-rendered UI for web research continuity,
recurring-reminder clarification, task mutation approval, calendar/email
approval, file OCR, meeting audio action candidates, and unauthorized email
draft-only behavior.

The implementation must still work one screen, or one tightly related runtime
flow, at a time.

## Confirmed Facts

- Authoritative local design export:
  `docs/stitch-export/secondloop-operating-system/`.
- Source-of-truth entry screen:
  `3b8ef30093554bf2bc42e296ee36be6c`
  (`SecondLoop Final Stitch Source of Truth`).
- Canonical implementation register:
  `a5874f74133b435a9feb498e76a23fe4`.
- Retired register:
  `43a2a241349e40a4b3dd3d61c0d3c76b`.
- Superseded / incomplete index
  `3aa56b7a88194a37a3c38abb3ef76618` must not be used.
- Previous screen-specific Trellis child tasks for screens 2-8 are archived and
  show that visual/UI work was completed with fake runtime-state fixtures.
- Current frontend screen tests cover rendering from injected
  `RuntimeAgentState` fixtures and some fake approval sender interactions.
- The main functional gap is end-to-end wiring: real runtime outputs, agent view
  state, approval queue behavior, and frontend projection must carry the same
  records that the UI fixtures assume.
- App runtime-first path already uses:
  - `GET /v1/runtime/vaults/:vaultId/agent-state`
  - `POST /v1/runtime/vaults/:vaultId/conversations/:conversationId/messages`
  - approval decision and approval patch APIs through
    `RuntimeSecretaryAppService`.
- Server-side evidence from `SecondLoopServer` shows likely gaps:
  - pending intents are stored in runtime state but are not exposed in
    `agent-state` as renderable records for screen 3;
  - task mutation approvals do not currently expose editable title metadata
    rich enough for screen 4's title-change card;
  - calendar candidates are supported, but calendar plus memory extraction needs
    combined candidate behavior for screen 5;
  - media result persistence drops rich OCR/audio fields such as source id,
    confidence, saved-to-vault, meeting id, duration, high-fidelity
    confirmation, decisions, and action items for screens 6-7;
  - action item candidate approvals are rendered by the frontend fixture, but
    Server approval decisions do not yet create or reject formal action/task
    candidates;
  - unauthorized email `needs_configuration` / `tool_unavailable` does not yet
    project a draft-only record plus fail-closed blocked-tool record into
    `agent-state` for screen 8.
- `workers/secretary-runtime/src/runtime_tools.js` is already 987 lines, so
  any substantial Server edit there must include refactoring to keep files at or
  below the project line-count rule.

## Requirements

- Use only `docs/stitch-export/secondloop-operating-system/` as the local Stitch
  source. Do not use stale zips, retired screens, or superseded indexes.
- Keep implementing only the canonical product screens from the canonical
  register.
- Preserve all existing UI alignment work unless a functional correction
  requires a scoped adjustment.
- Do not paste Stitch HTML into the app. All work must fit existing Flutter and
  runtime architecture.
- Do not modify or track exported Stitch HTML/screenshots or other `docs/`
  files.
- Keep `screenId -> local route/component/state/API` mapping current for every
  screen before implementing its functional work.
- For each screen, record UI, functionality, state-flow, and data/API wiring
  differences before edits.
- Fill real functionality before visual polish. No fake approvals, no fake
  buttons, no unbacked result panels.
- If a runtime/backend contract is missing, implement it in
  `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer` on local
  `main`, without writing secrets or sensitive server details into tracked app
  files.
- Maintain product boundaries:
  - SecondLoop is vault-first personal secretary agent, not AIOps or local
    computer automation.
  - App must not locally parse natural language to execute formal actions.
  - Current facts require `web-research` with citations.
  - Formal mutations and external side effects require approval by default.
  - Email/calendar unavailable states must degrade to draft,
    `needs_configuration`, or `tool_unavailable`.
  - Purchase/payment/local shell/local computer operations must be refused or
    safely degraded.
- Every completed screen needs fresh automated validation and Computer Use
  review at the manifest width.

## Screen Mapping

| # | Stitch screenId | Canonical title | Local route/component/state/API target | Functional alignment focus |
| --- | --- | --- | --- | --- |
| 2 | `99cc1523c51a4e1d9017fb53a2bac9bb` | Chat: Web Research Follow-up Continuity | `AgentConversationPage` mobile shell; `_OperatingAssistantResponse`; `agent_operating_research_cards.dart`; runtime turns with `web_research_drafts`, `citations_json`, `tool_trace`; agent-state recent turns/context snapshot. | Verify real send/fetch continuity, citations, and follow-up context are driven by runtime state, not fixture-only rendering. |
| 3 | `2584c8e54d014209adbd37b562e3ced1` | Chat: Recurring Reminder Clarification | `AgentConversationPage`; `_OperatingPendingIntentCard`; `_OperatingMemoryCandidateCard`; `_OperatingRecurringReminderCandidateCard`; runtime pending intents, memory approvals, recurring-reminder approvals, approval patch/decision APIs. | Expose real pending intent in agent-state; ensure birthday clarification does not create active reminder before approval; approval/edit/approve paths use runtime. |
| 4 | `0632921a825a4f1b9e91c2f66a4c97e3` | Task Mutation Approval: Recent Reference | `AgentConversationPage`; `TaskMutationApprovalCard`; runtime task records, recent entity refs, task mutation approvals, approval patch/decision APIs. | Make real task title mutation approvals editable and rich enough for target, resolver, current/proposed diff, audit/context/tool metadata. |
| 5 | `585ce0f7d36b4f55a8511bea0e2ef655` | Calendar Approval: Email Extraction | `AgentConversationPage`; attachment tile; `_OperatingMemoryCandidateCard`; `CalendarEventApprovalCard`; runtime email/document extraction, memory candidate, calendar event approval. | Support combined memory plus calendar candidates from one runtime turn; ensure event creation remains approval-gated. |
| 6 | `2384fe0e4de54f4e97f9935f813ecd01` | Chat: File OCR With Attachment Tile | `AgentConversationPage`; attachment widgets; `agent_runtime_media_results.dart`; `_OperatingReminderCandidateCard`; vault attachment upload/read; media result records; approval APIs. | Preserve OCR text, summary, source id, confidence, saved-to-vault state, attachment association, and optional follow-up reminder as runtime-backed records. |
| 7 | `3656acaa364f4e58b9d71c1d79f41809` | Chat: Meeting Audio Action Candidates | `AgentConversationPage`; audio attachment tile; media result widgets; `_OperatingActionItemCandidateCard`; runtime media/audio result records; action candidate approvals. | Preserve meeting id, transcript/minutes, decisions, action items, high-fidelity confirmation, and make create/dismiss candidates mutate runtime state honestly. |
| 8 | `a8435575721c43b9a5398a242abc28d0` | Email Unauthorized: Draft Only | `AgentConversationPage`; `agent_operating_email_cards.dart`; runtime email draft/degraded state, blocked tool record, no send approval. | Project unauthorized email into draft-only plus fail-closed blocked action records with no send side effect. |

## Acceptance Criteria

- [ ] Planning artifacts include PRD, design, and implementation plan before
      coding starts.
- [ ] Each screen 2-8 has a documented mapping and pre-edit difference list.
- [ ] Screen 2 proves real runtime web-research state includes citations and
      follow-up continuity; citation-less current-fact success is not accepted.
- [ ] Screen 3 pending intent, memory candidate, recurring-reminder candidate,
      edit, approve, and dismiss/deny behavior are backed by runtime state and
      APIs.
- [ ] Screen 4 title mutation approval is rendered from real runtime approval
      metadata and remains unapplied until approval succeeds.
- [ ] Screen 5 email/calendar extraction can expose both a memory candidate and
      a calendar event approval from one runtime turn; event creation remains
      gated.
- [ ] Screen 6 file OCR media result keeps OCR text separate from summary,
      shows source/confidence/vault state from runtime metadata, and keeps
      attachment preview/open behavior functional.
- [ ] Screen 7 meeting audio result keeps transcript/minutes/decision/action
      metadata and action candidate create/dismiss behavior is real or honestly
      degraded.
- [ ] Screen 8 unauthorized email shows draft-only and blocked-tool state, no
      send approval, and no claim of sent email.
- [ ] Focused frontend tests cover real send/fetch/projection paths in addition
      to existing static runtime-state fixtures.
- [ ] Relevant Server tests cover runtime contract/view-state gaps if Server is
      changed.
- [ ] Existing screen 2-8 visual tests still pass.
- [ ] Relevant lint/typecheck/build/test commands pass with fresh evidence.
- [ ] Each completed screen gets Computer Use review at manifest width and a
      closeout report with screenId, route/component mapping, functionality
      filled, modified files, screenshot/manual result, known non-1:1
      differences, and commands run.

## Out of Scope

- Re-implementing or redesigning screens 9-13.
- Implementing retired/superseded Stitch screens.
- Replacing the Flutter app with generated HTML.
- Editing exported Stitch source files.
- Adding local natural-language execution paths in the App.
- Implementing real external email send/calendar provider side effects unless
  already available through runtime; unavailable connectors should degrade.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
