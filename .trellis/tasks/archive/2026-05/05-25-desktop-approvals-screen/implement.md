# Restore desktop Approvals screen - Implementation Plan

1. Implement normalized approval view models.
2. Add `DesktopApprovalsWorkbenchPage` using shared desktop tokens/components.
3. Wire item selection, filters, approve/reject, refresh, and degraded actions.
4. Add tests for queue selection, approve/reject sender calls, blocked payment
   refusal, and `needs_configuration`.
5. Run:
   - `pixi run flutter test test/agent_conversation_stitch_thirteenth_screen_test.dart`
   - new focused desktop Approvals test
6. Manual Computer Use review at desktop viewport.
