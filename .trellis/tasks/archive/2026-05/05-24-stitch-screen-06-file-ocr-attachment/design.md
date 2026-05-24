# Design: Stitch screen 06 file OCR attachment

## Architecture And Boundaries

- Keep the implementation inside the existing Flutter chat/runtime UI:
  `AgentConversationPage`, `_OperatingMessageList`, attachment widgets, media
  result projection, and shared approval card primitives.
- Treat the Stitch export as visual evidence only. Do not import or translate
  HTML directly.
- Prefer runtime-backed rendering over storyboards or demo controllers. The
  screen should be driven by `RuntimeAgentState.conversationTurns`,
  `workingSetRecords`, `approvalItems`, attachment metadata, and hydrated
  attachment bytes.
- App code may format and project media metadata for display, but semantic
  OCR/summarization decisions remain owned by runtime/vault.
- Server changes are only in scope if the existing runtime payload cannot
  honestly represent OCR text, source attachment, saved-to-vault state, or the
  follow-up approval candidate.

## Data Flow And Contracts

1. Runtime state loads via `RuntimeAgentStateRepository.fetchAgentState`.
2. `AgentConversationPage` projects conversation turns into operating chat
   messages.
3. User turn attachments are parsed from `attachment_refs` and `attachments`.
   If a `ChatRuntimeAttachmentContentFetcher` is available, the app hydrates
   bytes so image previews can render and attachment detail can open.
4. Media result records are collected from `RuntimeAgentState.workingSetRecords`
   and `latestContextSnapshot.packet['working_set'].records`.
5. `kind == media_result` records are associated to assistant turns by direct
   assistant turn id, source/user turn id, or attachment id matching.
6. The media display projection derives:
   - attachment/source id;
   - title/filename;
   - media type;
   - OCR text from `ocr_text`, `ocrText`, or text fallback;
   - summary from `summary`, `llm_summary`, `body`, or equivalent fields;
   - source id from `source_id`, `sourceId`, `attachment_id`, `blob_id`, or
     `sha256`;
   - confidence from numeric or string confidence fields;
   - saved-to-vault state from explicit `saved_to_vault`, `savedToVault`,
     `vault_saved`, or completed/synced status fields.
7. Approval items render through existing runtime approval dispatch. Screen 06
   should use the real reminder-related approval kind exposed by runtime data
   for the follow-up candidate, with approve/dismiss calling the existing
   approval service and refreshing runtime state.

## UI Shape

- Mobile canonical width follows the Stitch manifest width `780`.
- The first viewport should include:
  - top app bar with managed-pro/vault upload signal;
  - right-aligned user prompt and image-first attachment tile;
  - compact processing labels for OCR, summarization, and Vault/source sync;
  - assistant response with left accent;
  - media result card/section with `OCR TEXT`, summary, source id, confidence,
    and saved-to-vault metadata;
  - follow-up approval card;
  - composer and bottom nav.
- Attachment tile should keep a stable thumbnail area and avoid filename-driven
  layout shifts. Filename and size are secondary text.
- OCR media results should visually distinguish extracted text from summary.
  A neutral block for OCR text is acceptable when it fits the existing design
  token system.
- Metadata rows should wrap or stack on narrow mobile. They must not overflow
  at `390`, `780`, or desktop widths.

## Compatibility And Migration

- Preserve existing audio media result behavior. Audio should keep
  transcript/minutes/decisions/action items labels.
- Preserve current attachment send behavior: upload payloads may include bytes,
  but message attachment metadata sent to runtime must not leak base64 content.
- Preserve existing reminder, recurring reminder, task mutation, memory, and
  calendar approval behavior.
- Runtime payloads that omit optional OCR metadata must still render safely with
  explicit unavailable/degraded labels.
- No migration is required for local data; the screen fixture and production UI
  read runtime state.

## Risk Points

- `agent_conversation_page.dart` is close to the 1000-line project limit. Any
  implementation that would push it over the limit should move projection or UI
  code into existing part files instead.
- Generic media result labels can make OCR appear as transcript. Screen 06 needs
  OCR-specific labeling without regressing audio.
- Media result association can be wrong when multiple attachments or assistant
  turns exist. Prefer direct runtime ids when present.
- Attachment preview and filename text can overflow or reverse hierarchy on
  narrow widths.
- A fake saved-to-vault indicator would violate the runtime-first product
  boundary.
- Manual review requires Computer Use at manifest dimensions after automated
  checks.

## Rollback Shape

- Keep OCR metadata rendering isolated inside the media result projection and
  rendering part file.
- Keep attachment tile refinements local to the attachment widget part file.
- If the refined OCR card causes regressions, the UI can fall back to the
  generic media result section while preserving runtime-backed result content
  and approval actions.
- Server-side changes, if any are required, must remain additive and backward
  compatible with current media result record fields.
