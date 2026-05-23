# Stitch canonical screen continuation

## Goal

Continue the local Stitch-based SecondLoop frontend implementation from the
current in-progress state, preserving the user's source-of-truth constraints
and making each canonical product screen independently verifiable.

The immediate state is that canonical screen 2 has been implemented enough for
manual acceptance and automated checks, with uncommitted local changes still in
the working tree. The next work must either close out screen 2 cleanly or move
to the next canonical screen through the same per-screen mapping,
difference-analysis, real functionality, visual restoration, and verification
loop.

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
- Current completed/manual-reviewed product screen:
  `99cc1523c51a4e1d9017fb53a2bac9bb`
  (`Chat: Web Research Follow-up Continuity (Approved)`).
- Current uncommitted files include the screen 2 web-research follow-up UI,
  composer state, tokens, and widget test:
  - `lib/features/agent_ui/agent_conversation_layouts.dart`
  - `lib/features/agent_ui/agent_conversation_page.dart`
  - `lib/features/agent_ui/agent_operating_research_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_tokens.dart`
  - `test/agent_conversation_stitch_second_screen_test.dart`
- Screen 2 verification already run in the session:
  - `pixi run flutter test test/agent_conversation_stitch_second_screen_test.dart`
  - targeted `pixi run flutter analyze ...`
  - `pixi run verify-changed`
  - `git diff --check`
- Screen 2 manual review used Computer Use against a local macOS debug app and
  verified the web-research header, source cards, follow-up context chip,
  extracted evidence expansion, trace footer, and follow-up composer.

## Requirements

- Use only the local Stitch export directory listed above as visual/design
  source. Do not use stale local zips, retired/superseded screens, or Stitch
  drafts outside the canonical register.
- Maintain a screen-by-screen mapping from Stitch `screenId` to local
  route/component/state/API behavior before implementation.
- Work one screen, or one tightly related flow, at a time.
- For each screen, compare Stitch HTML and screenshot against local UI and
  record:
  - UI differences
  - functionality differences
  - state-flow differences
  - data/API wiring differences
- If a Stitch screen shows a product capability that belongs to the final
  product docs, acceptance docs, or canonical register, implement or wire the
  real capability before polishing the static UI.
- Use explicit degraded states for unavailable runtime, permissions, connector,
  or backend dependencies. Do not ship fake buttons, fake approval cards, or
  unbacked result panels.
- Keep implementation inside existing Flutter architecture. Do not copy the
  Stitch HTML directly into the app.
- Prefer shared tokens, primitives, and reusable components when a pattern
  appears across screens.
- Preserve product boundaries:
  - SecondLoop is a vault-first personal secretary agent, not an AIOps or
    monitoring tool.
  - Formal action execution goes through runtime, not local natural-language
    parsing.
  - Current facts require `web-research` with citations.
  - Formal mutations and external side effects require approval by default.
  - Email/calendar unavailable states must degrade to draft,
    `needs_configuration`, or `tool_unavailable`.
  - Purchase/payment/local shell/local computer operation must be refused or
    safely degraded.
  - Managed pro and self-managed expose the same user-facing capabilities.
- After each screen, perform Computer Use manual review and run fresh relevant
  checks before reporting completion.
- Do not delete or revert user changes. Do not track `docs/` unless explicitly
  requested. Do not modify Stitch export source HTML/screenshots.

## Acceptance Criteria

- [ ] Current screen 2 changes are either committed/handed off cleanly or
      explicitly preserved as the base for the next screen.
- [ ] The active next canonical screen has a documented
      `screenId -> local route/component/state/API` mapping.
- [ ] The active next screen has a documented Stitch-vs-local difference list
      before implementation.
- [ ] Any required missing product capability is implemented, wired, or
      represented by a real degraded state.
- [ ] Visual implementation is reviewed against manifest dimensions and local
      screenshot/HTML baselines.
- [ ] Computer Use manual review is performed for each completed screen.
- [ ] Relevant Flutter tests, analyze/typecheck, and changed-file verification
      run with fresh evidence.
- [ ] Completion output for each screen includes:
      screenId, local mapping, missing functionality filled, modified files,
      screenshot/manual verification result, known non-1:1 differences, and
      commands run.

## Out of Scope

- Implementing retired register screens.
- Using superseded screen `3aa56b7a88194a37a3c38abb3ef76618`.
- Replacing the app architecture with generated Stitch HTML.
- Tracking or editing exported Stitch source files.
- Broad backend work unless a canonical screen requires a runtime/API contract
  that is absent or cannot reasonably degrade in the app.

## Open Questions

- Resolved: this task is a parent coordination task. Each independently
  verifiable canonical screen should be owned by a child task.

## Child Task Map

- `05-24-stitch-screen-02-web-research-closeout`: adopt and close out the
  existing screen 2 implementation and validation evidence.
- `05-24-stitch-screen-03-reminder-clarification`: implement and verify the next
  canonical screen,
  `2584c8e54d014209adbd37b562e3ced1`
  (`Chat: Recurring Reminder Clarification (Approved)`).

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
