# Implementation Plan: Stitch screen 07 meeting audio action candidates

## Ordered Checklist

1. Read pre-development specs for the app frontend layer with
   `trellis-before-dev`.
2. Inspect the current runtime media, attachment, processing label, and approval
   rendering paths:
   - `lib/features/agent_ui/agent_conversation_page.dart`
   - `lib/features/agent_ui/agent_conversation_attachments.dart`
   - `lib/features/agent_ui/agent_conversation_attachment_widgets.dart`
   - `lib/features/agent_ui/agent_conversation_layouts.dart`
   - `lib/features/agent_ui/agent_operating_message_bubbles.dart`
   - `lib/features/agent_ui/agent_runtime_media_results.dart`
   - `lib/features/agent_ui/agent_conversation_widgets.dart`
   - relevant conversation card primitives.
3. Record the final Stitch-vs-local difference list before implementation edits
   in this task's closeout notes or by updating `design.md` if new evidence is
   found.
4. Extend attachment projection only as needed for audio metadata:
   - duration label from runtime attachment fields;
   - size label fallback still works;
   - audio media type detection stays compatible with MIME type fallback.
5. Refine `_MessageAttachmentTile` so audio attachments render with a stable
   play/audio affordance and a duration/size secondary line, without changing
   image preview behavior.
6. Refine processing labels so audio media results show audio-specific runtime
   work such as transcription, meeting minutes, high-fidelity confirmation, and
   Vault source sync. Preserve OCR labels for image/PDF media.
7. Extend runtime media display projection for audio meeting fields:
   meeting id, duration/source metadata if present, transcript, meeting minutes,
   decisions, action items, confidence, saved-to-vault state, and citations.
8. If needed, add a dedicated operating action-item candidate card for runtime
   approval items that represent audio action candidates. It should support
   Create/Approve and Dismiss through the existing approval sender and state
   refresh path.
9. Ensure the screen fixture can render:
   - uploaded `q3_planning_sync_raw.m4a` attachment;
   - high-fidelity processing confirmed state;
   - assistant meeting media result for `MTG-Q3-2026-001`;
   - transcript, minutes, decisions, sources, and saved-to-vault metadata;
   - action candidates `ACT-091`, `ACT-092`, and `ACT-093`;
   - approve/create and dismiss interactions without direct local task writes.
10. Check for any required `SecondLoopServer` contract gap. Only modify server
    if the App cannot honestly represent runtime state with existing fields.
11. Add a focused widget test for screen 07 with runtime-state fixture data:
    - canonical content and audio metadata;
    - candidate create/approve interaction removes or updates the candidate;
    - candidate dismiss interaction is wired or covered in a second fixture;
    - responsive widths: `390`, `780`, and desktop.
12. Run focused checks, analyzer/typecheck, changed-file verification, and
    `git diff --check`.
13. Perform Computer Use manual review at manifest width `780`.
14. Record completion with screenId, mapping, filled functionality, modified
    files, manual review, non-1:1 differences, and fresh command evidence.

## Validation Commands

Use `pixi` from
`/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoop`.

```bash
pixi run flutter test test/agent_conversation_stitch_seventh_screen_test.dart
pixi run flutter test test/agent_conversation_stitch_sixth_screen_test.dart
pixi run flutter test test/agent_conversation_runtime_state_source_test.dart
pixi run flutter test test/agent_conversation_attachment_test.dart
pixi run flutter test test/agent_conversation_runtime_approval_test.dart
pixi run flutter analyze lib/features/agent_ui lib/features/conversation_cards test/agent_conversation_stitch_seventh_screen_test.dart
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
- Do not claim high-fidelity audio processing was confirmed unless runtime
  state or approval history supports it.
- Do not claim transcript, meeting minutes, decisions, saved-to-vault state, or
  action candidate creation unless runtime evidence supports it.
- Do not write local tasks directly when approving action candidates; route
  through runtime approval decisions.
- Do not accept storyboard/demo-only coverage as sufficient for this screen.
- Do not let any single non-document file exceed 1000 lines.
- Do not skip Computer Use review after UI changes.

## Rollback Points

- Audio metadata parsing should be isolated enough to revert without touching
  attachment sending.
- Audio attachment tile refinements should stay in the attachment widget part
  file.
- Audio media projection changes should stay in the runtime media results part
  file.
- Action candidate UI should fall back to the existing generic runtime
  candidate card if a dedicated card causes layout or approval regressions.
- Widget fixture data should live in the screen 07 test and not leak into
  production runtime state.
- Any server contract change must be additive and verified against existing
  media result and approval-item parsing.

## Completion Evidence

- ScreenId: `3656acaa364f4e58b9d71c1d79f41809`
  (`Chat: Meeting Audio Action Candidates (Approved)`).
- Mapping: `AppShell` Chat tab -> `AgentConversationPage` mobile operating
  shell, with audio attachment metadata in
  `agent_conversation_attachments.dart`, audio tile rendering in
  `agent_conversation_attachment_widgets.dart`, processing labels in
  `agent_conversation_layouts.dart`, media result projection in
  `agent_runtime_media_results.dart`, media result rendering in
  `agent_runtime_media_result_widgets.dart`, and action candidates in
  `agent_operating_action_candidate_cards.dart`.
- Filled functionality:
  - runtime audio attachment tile renders filename, play affordance, duration,
    and size;
  - audio media results project transcript, meeting minutes, decisions, action
    items, meeting id, duration, source id, confidence, sources, and
    saved-to-vault metadata from runtime fields;
  - high-fidelity processing confirmation is only shown when runtime media
    fields explicitly report confirmation;
  - `action_item_candidate` approval items render as Create/Dismiss candidates
    and submit through the existing runtime approval sender and refresh path;
  - non-runtime send-result approvals keep their existing acceptance-card path
    when no `RuntimeAgentState` is present.
- Modified files:
  - `lib/features/agent_ui/agent_conversation_attachments.dart`
  - `lib/features/agent_ui/agent_conversation_attachment_widgets.dart`
  - `lib/features/agent_ui/agent_conversation_layouts.dart`
  - `lib/features/agent_ui/agent_conversation_page.dart`
  - `lib/features/agent_ui/agent_runtime_media_results.dart`
  - `lib/features/agent_ui/agent_runtime_media_result_widgets.dart`
  - `lib/features/agent_ui/agent_operating_action_candidate_cards.dart`
  - `test/agent_conversation_stitch_seventh_screen_test.dart`
  - `.trellis/spec/frontend/component-guidelines.md`
- Manual review: Computer Use inspected a Flutter-rendered 780px-wide screenshot
  in macOS Preview. Verified the audio tile, high-fidelity confirmation strip,
  meeting result card, three action candidate cards, Create/Dismiss controls,
  bottom composer, and bottom navigation without visible overlap.
- Known non-1:1 differences: local UI uses the existing operating-shell tokens,
  cards, bottom navigation, and runtime media result sections instead of
  importing the Stitch HTML. Runtime action candidates are backed by approval
  decisions rather than creating tasks directly from the screenshot fixture.
- Server changes: none required; existing runtime state and approval item fields
  can honestly represent the screen.
- Fresh verification:
  - `pixi run flutter test "test/agent_conversation_stitch_seventh_screen_test.dart"`
  - `pixi run flutter test "test/agent_conversation_stitch_sixth_screen_test.dart test/agent_conversation_runtime_state_source_test.dart test/agent_conversation_attachment_test.dart test/agent_conversation_runtime_approval_test.dart"`
  - `pixi run flutter analyze "lib/features/agent_ui lib/features/conversation_cards test/agent_conversation_stitch_seventh_screen_test.dart"`
  - `pixi run verify-changed`
  - `git diff --check`
