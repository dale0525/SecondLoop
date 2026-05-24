# Stitch screen 03 reminder clarification

## Goal

Implement and verify the third canonical Stitch product screen:
`Chat: Recurring Reminder Clarification (Approved)`.

The screen demonstrates the runtime-first reminder flow where the user asks for
a recurring birthday reminder without providing the birthday, the agent asks a
clarifying question, and only after the missing slot is supplied does the UI
show separate memory and recurring-reminder approval candidates.

## Confirmed Facts

- Stitch screenId:
  `2584c8e54d014209adbd37b562e3ced1`.
- Manifest dimensions: mobile, width `780`, height `2436`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/12-chat-recurring-reminder-clarification-2584c8e54d014209adbd37b562e3ced1.html`
  - `docs/stitch-export/secondloop-operating-system/screens/12-chat-recurring-reminder-clarification-2584c8e54d014209adbd37b562e3ced1.jpg`
- Product/QA docs define the target behavior:
  - QA-REM-01: missing birthday must trigger a clarification and preserve
    pending intent; no reminder should be created by guessing.
  - QA-REM-02: after the birthday is supplied, the UI should show a birthday
    memory candidate and a buy-gift recurring reminder candidate as independent
    approval cards.
  - QA-REM-03: after approval, recurring reminder rules should be visible from
    runtime state.
- Existing code/tests already include recurring reminder runtime concepts:
  `recurring_reminder_confirmation`, recurring reminder approval patching, and
  runtime recurring reminder state rendering in related tests.
- This child depends on screen 2 closeout only in git hygiene terms: existing
  screen 2 uncommitted changes should be preserved and not mixed with unrelated
  screen 3 changes.
- User-supplied implementation contract confirmed for this child:
  - use only `docs/stitch-export/secondloop-operating-system/` as the Stitch
    source;
  - read README, manifest, corresponding HTML/screenshot, final product shape,
    QA acceptance, and development plan before implementation;
  - implement only canonical register product screens;
  - treat retired/superseded screens as negative examples only;
  - fill real functionality/state/API wiring before visual polish;
  - perform Computer Use review at manifest dimensions before completion;
  - run fresh `pixi` verification and report exact evidence.

## Requirements

- Establish the screen 3 mapping before implementation:
  `screenId -> local route/component/state/API`.
- Compare Stitch HTML/screenshot against current local Agent chat UI and record
  UI, functionality, state-flow, and data/API wiring differences before edits.
- Implement the reminder clarification screen through existing Flutter
  architecture. Do not paste Stitch HTML.
- The first user request
  `每年孩子生日前一天提醒我买礼物。` must render as a runtime clarification flow:
  the assistant asks for the child birthday and shows a pending intent / action
  halted state instead of creating an active recurring reminder.
- The follow-up user message
  `孩子生日是 2018 年 6 月 1 日。` must render separate candidates:
  - memory candidate for the child birthday
  - recurring reminder candidate for buying the birthday gift
- Candidate cards must be backed by runtime approval item/state data and expose
  real approve/edit/dismiss affordances or explicit degraded behavior if a
  sender/runtime capability is unavailable.
- The recurring reminder title should express the action, for example
  `给孩子买生日礼物`, not merely `孩子生日`.
- No recurring reminder should be represented as active before approval.
- Use current product boundaries: runtime owns semantic decisions, formal
  mutations require approval, and local natural-language parsing must not be
  used to execute the formal reminder mutation.
- Match the local Stitch screenshot/HTML first viewport, chat thread, status
  labels, action buttons, composer, and bottom nav as closely as possible within
  existing Flutter architecture.
- Do not implement fake approvals or inactive controls. Pending intent, memory
  candidate, and recurring reminder candidate must be backed by runtime state,
  approval item data, or an explicit degraded state.
- Do not track or edit `docs/`; the local Stitch export is a design baseline.
- If app-side runtime/API wiring is insufficient, identify whether a real
  server change is required in the `SecondLoopServer` main branch before
  claiming the screen is complete.

## Acceptance Criteria

- [ ] A screen 3 mapping table and difference list exist before implementation.
- [ ] The rendered UI matches the canonical Stitch first viewport, chat thread,
      pending intent card, memory candidate card, recurring reminder candidate
      card, composer, and bottom nav as closely as the app architecture allows.
- [ ] QA-REM-01 behavior is represented: missing birthday causes clarification,
      no guessed date, no active reminder.
- [ ] QA-REM-02 behavior is represented: supplied birthday produces separate
      memory and recurring reminder candidates.
- [ ] Candidate controls are clickable and either call the runtime approval flow
      or visibly degrade with an honest unavailable/error state.
- [ ] A focused widget test covers the runtime-state fixture for screen 3.
- [ ] Computer Use manual review is performed at manifest width after the UI
      changes.
- [ ] Relevant `pixi` checks pass with fresh evidence, including focused tests,
      analyzer/typecheck, build or documented build-equivalent gate, and
      changed-file verification.
- [ ] Completion output includes screenId, mapping, functionality filled,
      modified files, screenshot/manual verification result, known non-1:1
      differences, and commands run.

## Out of Scope

- Implementing screen 4 task mutation approval.
- Retired/superseded reminder designs.
- Backend deployment unless the existing app cannot represent the required
  runtime state or approval flow without a server contract change.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
