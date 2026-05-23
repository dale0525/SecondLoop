# Stitch screen 02 web research acceptance closeout

## Goal

Close out the already-developed second canonical Stitch product screen and make
its evidence easy to review, commit, or build on before moving to screen 3.

This child task adopts the existing uncommitted screen 2 work rather than
starting a new implementation. It should preserve the manual and automated
verification already completed in the current session.

## Confirmed Facts

- Stitch screen:
  `99cc1523c51a4e1d9017fb53a2bac9bb`
  (`Chat: Web Research Follow-up Continuity (Approved)`).
- Local implementation maps to Agent chat:
  `AgentConversationPage` -> operating-system mobile shell ->
  web-research cards and follow-up composer.
- Existing uncommitted files for this screen:
  - `lib/features/agent_ui/agent_conversation_layouts.dart`
  - `lib/features/agent_ui/agent_conversation_page.dart`
  - `lib/features/agent_ui/agent_operating_research_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_tokens.dart`
  - `test/agent_conversation_stitch_second_screen_test.dart`
- Manual review already completed with Computer Use against a local macOS debug
  app. Verified header mode chips, first search result sources, second follow-up
  context chip, extracted evidence expansion, audit footer, and follow-up
  composer.
- Fresh checks already run:
  - `pixi run flutter test test/agent_conversation_stitch_second_screen_test.dart`
  - targeted `pixi run flutter analyze ...`
  - `pixi run verify-changed`
  - `git diff --check`
- A manual-review issue was found and fixed: the generic
  `Entity Ref / Active Memory / Working set` context strip appeared above the
  composer on the web-research continuity screen, but the Stitch baseline goes
  directly into the follow-up composer.

## Requirements

- Preserve the screen 2 mapping, functionality, visual behavior, and test
  coverage already produced.
- Treat screen 2 as a real runtime-state rendering path, not a static mock:
  sources, citations, context snapshot, tool trace, and extracted evidence must
  be driven by runtime state/message metadata.
- Keep the screen aligned with the canonical Stitch HTML/screenshot:
  `html/11-chat-web-research-follow-up-continuity-99cc1523c51a4e1d9017fb53a2bac9bb.html`
  and
  `screens/11-chat-web-research-follow-up-continuity-99cc1523c51a4e1d9017fb53a2bac9bb.jpg`.
- Do not introduce retired/superseded design content.
- Do not modify or track `docs/`.
- If further edits are needed, keep them scoped to screen 2 closeout and shared
  primitives that screen 2 already introduced.

## Acceptance Criteria

- [x] Screen 2 has final completion notes with:
      screenId, local route/component mapping, missing functionality filled,
      modified files, manual verification result, remaining non-1:1 differences,
      and commands run.
- [x] Existing tests and `verify-changed` remain passing after any final edits.
- [x] The uncommitted diff is reviewed for accidental unrelated changes.
- [x] The task is ready for commit/handoff or for being archived after commit,
      depending on the user's desired git flow.

## Closeout Evidence

- Stitch screenId:
  `99cc1523c51a4e1d9017fb53a2bac9bb`.
- Local route/component mapping:
  Agent Chat tab -> `AgentConversationPage` -> operating-system mobile shell ->
  web-research runtime cards and follow-up composer.
- Missing functionality filled:
  runtime-state-driven web-research source cards, citation metadata, follow-up
  context chip, extracted evidence toggle, audit footer, and follow-up-mode
  composer. Generic context strip is suppressed for this canonical continuity
  screen to match Stitch.
- Modified files:
  - `lib/features/agent_ui/agent_conversation_layouts.dart`
  - `lib/features/agent_ui/agent_conversation_page.dart`
  - `lib/features/agent_ui/agent_operating_research_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_tokens.dart`
  - `test/agent_conversation_stitch_second_screen_test.dart`
- Manual verification:
  Computer Use reviewed a local macOS debug app at the mobile screen fixture
  width. Verified header chips, first search result sources, second follow-up
  card, extracted evidence expansion, audit footer, composer, and bottom nav.
- Known non-1:1 differences:
  the app keeps the existing local tray icon/avatar asset rather than Stitch's
  remote generated portrait. Runtime source titles may vary with real runtime
  data; the test fixture is aligned with the canonical local Stitch HTML.
- Fresh closeout commands:
  - `pixi run flutter test test/agent_conversation_stitch_second_screen_test.dart`
  - `pixi run flutter analyze lib/features/agent_ui/agent_conversation_layouts.dart lib/features/agent_ui/agent_operating_research_cards.dart lib/features/agent_ui/agent_operating_system_cards.dart test/agent_conversation_stitch_second_screen_test.dart`
  - `git diff --check`
  - `wc -l ...`
  - `git status --short docs`
  - `pixi run verify-changed`

## Out of Scope

- Starting screen 3 implementation.
- Backend/runtime changes.
- Editing Stitch export files.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
