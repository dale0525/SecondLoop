# Stitch screen 01 personal secretary flow closeout

## Goal

Close out the already-implemented first canonical Stitch product screen:
`Agent Chat: Personal Secretary Flow (Refined)`.

This child task adopts existing local work for the first canonical mobile chat
screen and verifies that it still renders from runtime state rather than static
demo markup.

## Confirmed Facts

- Stitch screenId:
  `7478ab2f8f9b4ef2b89f2e8c6c1df11e`.
- Manifest dimensions: mobile, width `798`, height `2114`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/10-agent-chat-personal-secretary-flow-7478ab2f8f9b4ef2b89f2e8c6c1df11e.html`
  - `docs/stitch-export/secondloop-operating-system/screens/10-agent-chat-personal-secretary-flow-7478ab2f8f9b4ef2b89f2e8c6c1df11e.jpg`
- Stitch source shows the managed-pro chat shell, bottom navigation order,
  user request `帮我创建一个任务：完成周报。记住：任务回复请使用中文。`,
  processing chain `router / task-management / memory-capture / vault write`,
  an applied `Task Created` card for `完成周报`, and a pending
  `Memory Candidate` for `任务相关回复默认使用中文`.
- Existing automated coverage includes
  `test/agent_conversation_stitch_first_screen_test.dart`.
- The user confirmed this screen has already been completed and requested
  verification.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `7478ab2f8f9b4ef2b89f2e8c6c1df11e` | `AppShell` Chat tab -> `AgentConversationPage` mobile operating shell; state from `RuntimeAgentState.conversationTurns`, `tasks`, `approvalItems`, `recentEntityRefs`, and audit refs; task opening through the local task detail sheet; memory approval through `ChatRuntimeApprovalSender.submitApprovalDecision`. |

## Requirements

- Preserve the implemented runtime-backed first screen rather than replacing it
  with static Stitch HTML.
- Render the applied ordinary task only from runtime task state returned by the
  agent state repository.
- Render the memory candidate as a pending approval item and submit approval
  through the real approval sender path used by the app.
- Keep the managed-pro mobile shell and final Stitch bottom navigation order:
  Briefing, Chat, Vault, Tasks, Settings.
- Keep responsive behavior covered for canonical mobile width, bottom-nav
  widths, intermediate desktop width, and desktop workbench breakpoints.
- Do not introduce app-side natural-language parsing for task or memory
  creation; runtime remains the semantic authority.
- Do not use retired or superseded Stitch screens as visual evidence.

## Acceptance Criteria

- [x] `pixi run flutter test test/agent_conversation_stitch_first_screen_test.dart`
      passes.
- [x] Targeted analyze for the touched first-screen implementation/test surface
      passes or no changed production files require a new analyze run.
- [x] The verification report records screenId, local mapping, functionality
      covered, modified files, known non-1:1 differences, and commands run.
- [x] Any remaining manual review gap is explicitly called out instead of
      implied as complete.

## Closeout Evidence

- Stitch screenId:
  `7478ab2f8f9b4ef2b89f2e8c6c1df11e`.
- Local route/component mapping:
  `AppShell` Chat tab -> `AgentConversationPage` mobile operating shell;
  runtime state from `RuntimeAgentState.conversationTurns`, `tasks`,
  `approvalItems`, `recentEntityRefs`, and audit refs; memory approval through
  `ChatRuntimeApprovalSender.submitApprovalDecision`.
- Functionality covered:
  managed-pro chat shell, final Stitch bottom navigation order, runtime-backed
  applied task card, pending memory candidate, task detail opening, memory
  approval decision submission, bottom-nav/intermediate desktop behavior, and
  desktop workbench frame checks.
- Modified files in this closeout:
  Trellis planning artifacts only. The existing implementation/test surface was
  already present in the repository and was verified in place.
- Computer Use manual review:
  launched a temporary local harness with the real `AppShell` and
  `AgentConversationPage` components at the canonical mobile size, using the
  screen 01 runtime state from the widget test. Verified the managed-pro header,
  user prompt, `router / task-management / memory-capture / vault write` trace,
  applied `Task Created` card for `完成周报`, mutation/audit metadata, pending
  `Memory Candidate` card for `任务相关回复默认使用中文`, context strip, composer,
  and bottom nav order. Clicked `Open Task`; it opened the task detail sheet
  with title `完成周报`, status `Not completed`, and due `No due time`. Clicked
  `APPROVE`; the memory candidate card was removed from the rendered screen.
- Manual screenshot evidence:
  `build/manual-qa/stitch-screen-01-after-memory-approve.png`.
- Known non-1:1 differences:
  the first attempt used the live dev app state, but that current local
  conversation did not contain screen 01 and Computer Use could not inject text
  into the Flutter macOS composer. Manual visual review therefore used a
  deterministic local harness with the production screen components and fake
  runtime state, avoiding live cloud/runtime side effects.
- Fresh commands run:
  - `pixi run flutter test test/agent_conversation_stitch_first_screen_test.dart`
    -> passed, 6 tests.
  - `pixi run flutter analyze lib/features/agent_ui/agent_conversation_page.dart lib/features/agent_ui/agent_conversation_layouts.dart lib/features/agent_ui/agent_desktop_workbench_layout.dart test/agent_conversation_stitch_first_screen_test.dart`
    -> initial unquoted `pixi` invocation failed because the `flutter` task
    accepts `command_args` as a single argument; rerun with quoted file list
    passed with no issues.
  - `pixi run verify-changed` -> passed, including full analyze with no issues.
  - `git diff --check` -> passed.
  - `python3 ./.trellis/scripts/task.py validate 05-24-stitch-screen-01-personal-secretary-flow`
    -> passed.
  - `bash scripts/flutter_with_defines.sh run -d macos -t tool/stitch_screen_01_manual_app.dart`
    -> launched the manual review harness; stopped after Computer Use review.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
