# Restore desktop Memory Approvals Connectors screens - Implementation Plan

1. Read frontend specs and current shell/runtime patterns.
2. Add desktop-only destination state to `AppShell` without changing `AppTab`.
3. Add shared desktop page tokens/components if needed.
4. Implement Memory screen and test its navigation/action wiring.
5. Implement Approvals screen and test approve/reject plus degraded blocked
   states.
6. Implement Connectors screen and test capability/degraded actions.
7. Run targeted widget tests, analyzer/lint/typecheck, and relevant build/test
   commands through `pixi`.
8. Launch the app and manually inspect all three screens with Computer Use.

Validation commands:

- `pixi run flutter test test/agent_conversation_stitch_thirteenth_screen_test.dart`
- Add and run a focused desktop navigation screen test.
- `pixi run flutter analyze`
- If time/runtime permits: `pixi run flutter test`

Review gates:

- Each screen must list UI/function/state/API deltas before implementation.
- Each screen must report Stitch screenId, local mapping, files changed,
  screenshot/manual review result, remaining deltas, and validation results.
