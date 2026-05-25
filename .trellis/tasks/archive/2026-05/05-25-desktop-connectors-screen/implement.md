# Restore desktop Connectors screen - Implementation Plan

1. Add connector view model and selection state.
2. Add `DesktopConnectorsWorkbenchPage` using shared desktop tokens/components.
3. Wire refresh/capability/degraded actions to repository refresh or snackbar.
4. Add tests for connector selection, degraded email/calendar actions, runtime
   capability check, and mobile nav isolation.
5. Run:
   - `pixi run flutter test test/agent_conversation_stitch_thirteenth_screen_test.dart`
   - new focused desktop Connectors test
6. Manual Computer Use review at desktop viewport.
