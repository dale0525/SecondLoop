# Restore desktop Memory screen - Implementation Plan

1. Start this child task after planning review.
2. Add/select desktop-only destination state in `AppShell` if not already done
   by parent integration work.
3. Add `DesktopMemoryWorkbenchPage` using existing desktop tokens.
4. Wire runtime state load/refresh and approval sender callbacks.
5. Add focused widget tests for navigation, row selection, pending approval
   decision, empty/degraded states.
6. Run:
   - `pixi run flutter test test/agent_conversation_stitch_thirteenth_screen_test.dart`
   - new focused desktop Memory test
7. Manual Computer Use review at desktop viewport.
