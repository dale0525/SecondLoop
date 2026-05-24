# Implementation Plan: Stitch screen 06 file OCR attachment

## Ordered Checklist

1. Read pre-development specs for the app frontend layer with
   `trellis-before-dev`.
2. Inspect the current runtime media and attachment rendering paths:
   - `lib/features/agent_ui/agent_conversation_page.dart`
   - `lib/features/agent_ui/agent_conversation_attachment_widgets.dart`
   - `lib/features/agent_ui/agent_operating_message_bubbles.dart`
   - `lib/features/agent_ui/agent_runtime_media_results.dart`
   - relevant runtime approval card/primitives.
3. Add or refine runtime media display projection for OCR-specific fields:
   OCR text, summary, source id, confidence, saved-to-vault state, and
   attachment/source metadata.
4. Refine the inline media result UI so image/OCR results use OCR-specific
   labels and metadata while audio results keep transcript/minutes behavior.
5. Refine the attachment tile only as needed to match the image-first hierarchy
   and responsive behavior required by QA and Stitch.
6. Ensure the screen fixture can render:
   - uploaded `qa-ocr-sample.png` image attachment;
   - assistant media result with `QA MEDIA`;
   - follow-up reminder approval candidate;
   - processing labels / source sync evidence.
7. Wire approve/dismiss to existing runtime approval callbacks and verify state
   refresh removes the candidate while keeping the media result visible.
8. Check for any required `SecondLoopServer` contract gap. Only modify server
   if the app cannot honestly represent the runtime state with existing fields.
9. Add a focused widget test for screen 06 with runtime-state fixture data:
   - canonical content and OCR metadata;
   - attachment tile tap opens image/detail;
   - approval interaction;
   - responsive widths: `390`, `780`, and desktop.
10. Run focused checks, analyzer/typecheck, changed-file verification, and
    `git diff --check`.
11. Perform Computer Use manual review at manifest width `780`.
12. Record completion with screenId, mapping, filled functionality, modified
    files, manual review, non-1:1 differences, and fresh command evidence.

## Validation Commands

Use `pixi` from `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoop`.

```bash
pixi run flutter test test/agent_conversation_stitch_sixth_screen_test.dart
pixi run flutter test test/agent_conversation_attachment_test.dart
pixi run flutter test test/agent_conversation_runtime_state_source_test.dart
pixi run flutter test test/agent_conversation_stitch_fifth_screen_test.dart
pixi run flutter analyze lib/features/agent_ui lib/features/conversation_cards test/agent_conversation_stitch_sixth_screen_test.dart
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
- Do not claim OCR, Vault save, or reminder creation unless runtime evidence
  says it happened.
- Do not accept storyboard/demo-only coverage as sufficient for this screen.
- Do not let `agent_conversation_page.dart` exceed 1000 lines; move new code to
  part files if needed.
- Do not skip Computer Use review after UI changes.

## Completion Evidence

- ScreenId: `2384fe0e4de54f4e97f9935f813ecd01`
  (`Chat: File OCR With Attachment Tile (Approved)`).
- Mapping: `AppShell` Chat tab -> `AgentConversationPage` mobile operating
  shell, with user attachment rendering in
  `agent_conversation_attachment_widgets.dart`, processing/media placement in
  `agent_conversation_layouts.dart` and `agent_operating_message_bubbles.dart`,
  OCR media projection/rendering in `agent_runtime_media_results.dart`, and
  reminder approval rendering in `agent_operating_reminder_cards.dart`.
- Filled functionality:
  - runtime `media_result` records from `workingSetRecords` / context snapshot;
  - OCR text and summary rendered as separate fields;
  - source id, confidence, and saved-to-vault metadata from runtime fields;
  - image-first attachment tile with tappable detail viewer;
  - `reminder_confirmation` candidate with Approve/Dismiss wired through the
    runtime approval sender and state refresh path;
  - fallback assistant visibility when send succeeds but runtime refresh fails.
- Manual review: Computer Use macOS run at approximately manifest width `780`;
  verified image tile preview, `ocr` / `summarize` /
  `source synced to Vault`, media result `QA MEDIA`, source metadata,
  `Reminder Candidate`, and non-overflowing action buttons. Attachment viewer
  opened and rendered image content after replacing the test/manual fixture
  bytes with a decodable PNG.
- Known non-1:1 differences: local UI uses existing app tokens, bottom nav, and
  runtime card primitives instead of importing Stitch HTML; attachment viewer
  displays real app detail controls (`Share`, `Open with system app`,
  `Download`) that are outside the Stitch chat screenshot.
- Server changes: none required; existing runtime state fields can honestly
  represent the screen.
- Fresh verification:
  - `pixi run fmt`
  - `pixi run flutter test "test/agent_conversation_stitch_sixth_screen_test.dart"`
  - `pixi run flutter test "test/agent_conversation_attachment_test.dart"`
  - `pixi run flutter test "test/agent_conversation_runtime_state_source_test.dart"`
  - `pixi run flutter test "test/agent_conversation_stitch_fifth_screen_test.dart"`
  - `pixi run flutter test "test/agent_conversation_test.dart --plain-name 'managed pro conversation localizes runtime media result labels'"`
  - `pixi run flutter analyze "lib/features/agent_ui"`
  - `pixi run flutter analyze "lib/features/conversation_cards"`
  - `pixi run flutter analyze "test/agent_conversation_stitch_sixth_screen_test.dart"`
  - `pixi run verify-changed`
  - `git diff --check`

## Rollback Points

- OCR-specific media result projection should be isolated enough to revert
  without touching attachment send or audio media behavior.
- Attachment tile refinements should stay in the attachment widget part file.
- Widget fixture data should live in the screen 06 test and not leak into
  production runtime state.
- If a server contract change is necessary, keep it additive and verify old
  media result parsing still works.
