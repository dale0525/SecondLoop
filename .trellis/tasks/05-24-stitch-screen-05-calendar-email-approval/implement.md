# Implementation Plan: Stitch screen 05 calendar email approval

## Ordered Checklist

1. Read pre-development specs for the app frontend layer with
   `trellis-before-dev`.
2. Inspect the current runtime approval rendering paths:
   - `lib/features/agent_ui/agent_conversation_page.dart`
   - `lib/features/agent_ui/agent_conversation_layouts.dart`
   - `lib/features/agent_ui/agent_conversation_attachments.dart`
   - `lib/features/conversation_cards/calendar_email_card.dart`
   - `lib/features/conversation_cards/approval_preview_card.dart`
3. Add or refine runtime-backed calendar event approval display data:
   - parse safe title, start/end, participants, source/tool metadata, audit id,
     sync priority, and approval status from `SecretaryRuntimeApprovalItem`.
4. Add/refine a calendar event approval card in the existing component system.
   Reuse shared tokens and primitives; avoid Stitch HTML.
5. Wire `_OperatingMessageList` / `AgentConversationPage` so
   `calendar_event_confirmation` renders the new card while existing approval
   kinds keep their current behavior.
6. Ensure memory candidate and calendar event approval can render together.
7. Wire approve/reject to the existing runtime approval callbacks and expose
   busy/error state.
8. Handle Edit:
   - use approval patch when a supported editable field exists;
   - otherwise show an honest unavailable/degraded state.
9. Add a focused widget test for screen 05 with runtime-state fixture data:
   - user message and email attachment;
   - assistant response;
   - `memory_confirmation`;
   - `calendar_event_confirmation`;
   - context/audit metadata;
   - approve/reject interaction;
   - responsive widths: `390`, `780`, and desktop.
10. Check for any required `SecondLoopServer` contract gap. Only modify server
    if the app cannot honestly represent the runtime state with existing
    fields.
11. Run focused checks, analyzer/typecheck, changed-file verification, and
    `git diff --check`.
12. Perform Computer Use manual review at manifest width `780`.
13. Record completion with screenId, mapping, filled functionality, modified
    files, manual review, non-1:1 differences, and fresh command evidence.

## Validation Commands

Use `pixi` from `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoop`.

```bash
pixi run flutter test test/agent_conversation_stitch_fifth_screen_test.dart
pixi run flutter test test/agent_conversation_runtime_approval_test.dart
pixi run flutter test test/agent_conversation_stitch_fourth_screen_test.dart
pixi run flutter analyze lib/features/agent_ui lib/features/conversation_cards test/agent_conversation_stitch_fifth_screen_test.dart
pixi run verify-changed
git diff --check
```

If server changes are required:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer
pixi run test
pixi run cloud-runtime-scenarios-test
```

## Review Gates

- Do not start implementation until the planning artifacts are reviewed and
  `task.py start` has moved this child task to `in_progress`.
- Do not claim external calendar creation unless runtime evidence says it
  happened.
- Do not accept demo-only `AgentUiAcceptanceController` coverage as sufficient
  for this screen.
- Do not skip Computer Use review after UI changes.

## Rollback Points

- New calendar approval rendering should be isolated enough to revert without
  touching task mutation or recurring reminder approval behavior.
- Widget fixture data should live in the screen 05 test and not leak into
  production runtime state.
- If a server contract change is necessary, keep it additive and verify old
  approval item parsing still works.
