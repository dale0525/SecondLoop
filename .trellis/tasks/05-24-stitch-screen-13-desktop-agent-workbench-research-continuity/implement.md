# Stitch screen 13 implementation plan

## Checklist

- [x] Confirm current desktop workbench implementation and existing screen 13
      coverage.
- [x] Add or refine typed projection helpers for runtime context, citations,
      pending approvals, and tool trace fields.
- [x] Update desktop workbench/right-panel components to match Stitch structure
      at `2560 x 2048` while preserving responsive behavior.
- [x] Ensure all visible actions are wired to real callbacks or honest degraded
      states.
- [x] Add a focused widget test for the manifest width, common desktop width,
      and non-workbench breakpoint.
- [x] Run targeted Flutter tests.
- [x] Run `pixi run verify-changed`.
- [x] Run `git diff --check`.
- [x] Launch the app or test harness and inspect with Computer Use at the
      manifest-width baseline, recording visible differences.

## Validation commands

```bash
pixi run flutter test test/agent_conversation_stitch_first_screen_test.dart
pixi run flutter test test/agent_conversation_stitch_second_screen_test.dart
pixi run flutter test test/agent_conversation_stitch_fourth_screen_test.dart
pixi run flutter test test/agent_conversation_stitch_thirteenth_screen_test.dart
pixi run verify-changed
git diff --check
```

If the thirteenth-screen test file does not exist yet, create it as the focused
screen 13 coverage.

## Risk points

- `agent_conversation_layouts.dart` and related operating-shell files may be
  close to the 1000-line limit. Split larger additions into sibling files.
- Runtime metadata is intentionally flexible. Keep parsing tolerant and avoid
  claiming successful web research when citation data is missing.
- Do not break existing mobile canonical screens while improving the desktop
  workbench.

## Review gate before coding

This task is ready to start when:

- `prd.md`, `design.md`, and `implement.md` exist.
- The user has already asked to start screen 13 implementation.
- The implementation remains scoped to the screen 13 route/component/state/API
  mapping above.

## Verification record

- `pixi run flutter analyze "lib/app/router.dart lib/features/agent_ui/agent_desktop_workbench_layout.dart lib/features/agent_ui/agent_desktop_workbench_primitives.dart test/agent_conversation_stitch_thirteenth_screen_test.dart test/app_shell_agent_tabs_test.dart test/agent_conversation_stitch_first_screen_test.dart"`: passed.
- `pixi run flutter test "test/app_shell_agent_tabs_test.dart test/agent_conversation_stitch_first_screen_test.dart test/agent_conversation_stitch_second_screen_test.dart test/agent_conversation_stitch_fourth_screen_test.dart test/agent_conversation_stitch_thirteenth_screen_test.dart"`: passed.
- `pixi run verify-changed`: passed.
- `git diff --check`: passed.
- Computer Use review: generated `.tool/screen13_workbench.png` from a Flutter
  widget screenshot and inspected it in Preview. The layout showed the desktop
  workbench frame with top bar, left navigation, center chat, right evidence
  panels, composer, and quick capture button. The direct macOS harness launch
  was blocked by the local Xcode linker error `ld: unknown option: -Xlinker`;
  widget tests remain the manifest-size source for exact geometry.
