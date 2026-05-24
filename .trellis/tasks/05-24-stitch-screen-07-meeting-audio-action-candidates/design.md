# Design: Stitch screen 07 meeting audio action candidates

## Architecture And Boundaries

- Keep the implementation inside the existing Flutter managed-pro chat surface:
  `AgentConversationPage`, `_OperatingMessageList`, attachment widgets, runtime
  media projection, and runtime approval card primitives.
- Treat the Stitch HTML and screenshot as product evidence only. Do not import
  or translate the HTML directly.
- The source of truth is runtime/vault state:
  `RuntimeAgentState.conversationTurns`, `workingSetRecords`,
  `latestContextSnapshot.packet['working_set'].records`, and
  `approvalItems`.
- The App may project and format runtime fields for display, but audio
  transcription, meeting minutes, decisions, action item extraction, provider
  selection, and high-cost confirmation state belong to the runtime.
- Do not represent local Whisper, local OCR, Rust/FRB, or other local media
  pipelines as the normal managed-pro path.
- Server changes are only in scope if existing runtime payloads cannot honestly
  represent audio transcript, meeting summary, saved-to-vault state, high-cost
  confirmation, or action item candidates.

## Stitch And Local Delta

- Stitch screen:
  - user prompt:
    `Process the audio recording from the Q3 Planning Sync and extract key actions.`;
  - audio attachment tile:
    `q3_planning_sync_raw.m4a`, `45:12`, `42 MB`, play affordance;
  - budget state:
    `High-fidelity processing confirmed`;
  - assistant response:
    processed recording, structured summary, proposed action items;
  - meeting summary:
    `MTG-Q3-2026-001`, saved to Vault, source/transcription access;
  - action item candidates:
    `ACT-091`, `ACT-092`, `ACT-093`, each with Create and Dismiss.
- Current local code already supports runtime `media_result` records for audio
  transcript, meeting minutes, decisions, action items, sources, and
  saved-to-vault metadata.
- Current attachment tiles are image-first or generic file tiles. Audio has an
  `isAudio` flag and hydrated bytes path, but the tile does not yet show an
  audio-specific play icon plus duration/size hierarchy.
- Current processing labels treat media results mostly like OCR/summarization.
  Screen 07 needs audio-specific labels such as transcription, meeting minutes,
  source sync, and high-fidelity confirmation.
- Current approval rendering supports known approvals plus a generic runtime
  candidate card for unknown kinds. Screen 07 can use real runtime approval
  items for action candidates, but should render them as action-item candidates
  instead of silently presenting them as generic approvals if the runtime
  exposes enough record fields.

## Data Flow And Contracts

1. Runtime state loads through
   `RuntimeAgentStateRepository.fetchAgentState`.
2. `AgentConversationPage` projects conversation turns into chat messages.
3. User turn attachments are parsed from `attachment_refs` and `attachments`.
   Audio attachments should preserve filename, media type, MIME type, duration,
   size, and hydrated bytes when available.
4. Media result records are collected from both top-level
   `workingSetRecords` and the latest context snapshot working set.
5. `kind == media_result` records are associated to assistant turns by direct
   assistant turn id, source/user turn id, or attachment id matching.
6. Audio media projection should derive:
   - attachment/source id;
   - title/filename;
   - media type;
   - transcript from transcript/transcription fields;
   - meeting minutes from meeting/minutes/summary fields;
   - decisions and action item text lists;
   - meeting id from explicit meeting/source ids;
   - duration from attachment or media-result metadata;
   - confidence and saved-to-vault state from explicit runtime fields;
   - sources/citations from attachment and media-result citations.
7. High-cost state should be read from explicit runtime response/state fields
   or approval items. The App can show "confirmed" only when runtime evidence
   says it was confirmed or completed after confirmation.
8. Formal task creation from audio action items must happen through runtime
   approval/candidate APIs. Approve/Create and Dismiss must submit runtime
   approval decisions and refresh state; they must not write local tasks
   directly.

## UI Shape

- Mobile canonical width follows the Stitch manifest width `780`.
- The first viewport should include:
  - managed-pro chat shell and Vault upload state;
  - right-aligned user prompt with audio attachment tile;
  - high-fidelity/budget-confirmed state before the assistant result;
  - assistant response with inline meeting media result;
  - transcript/minutes/decisions/action-items/source metadata;
  - action item candidate cards with create/approve and dismiss controls;
  - composer and bottom navigation.
- Audio attachment tile should use an audio/play icon, stable dimensions, and a
  compact secondary line combining duration and size. Long filenames must
  ellipsize without resizing the tile.
- Meeting media result should use audio labels, not OCR labels. Transcript,
  meeting minutes, decisions, action items, and sources should remain distinct.
- Action candidates should show title, candidate id, due label when present,
  source timestamp when present, risk if present, and clear create/dismiss
  actions. When runtime fields are missing, render an honest degraded state
  rather than claiming a task can be created.
- Metadata rows and action buttons must avoid overflow at `390`, `780`, and
  desktop widths.

## Compatibility And Migration

- Preserve existing OCR media behavior from screen 06. Image/PDF results should
  continue to use OCR-specific labels.
- Preserve existing generic audio media result rendering in tests that only
  provide transcript/minutes/decisions/action_items.
- Preserve existing task mutation, reminder, recurring reminder, memory, and
  calendar approval behavior.
- Preserve attachment send behavior: runtime-bound message attachment metadata
  must not leak base64 content after the message is recorded.
- Runtime payloads that omit optional audio metadata must still render safely
  with explicit unavailable/degraded labels.
- No local data migration is required; this screen is fixture/runtime-state
  driven.

## Risk Points

- `agent_conversation_page.dart` is close to the project 1000-line file limit.
  Add new projection/UI code in existing part files or new part files instead
  of growing the page file.
- Processing labels currently bias toward OCR when media results are present.
  Audio-specific labels must not regress OCR-specific screen 06 behavior.
- Multiple attachments or multiple assistant turns can make media association
  ambiguous. Prefer direct runtime ids over fallback association.
- A fake high-cost confirmation chip would violate the runtime-first product
  boundary.
- A fake saved-to-vault marker would violate the same boundary. Use explicit
  runtime fields or show an unavailable/degraded label.
- Approval kind support may be narrower than the product copy. If runtime does
  not expose a dedicated action-item candidate kind, use the generic candidate
  path only when approve/dismiss is real and the UI copy is honest.
- Computer Use manual review is required at manifest width after automated
  checks.

## Rollback Shape

- Keep audio attachment display changes local to the attachment projection and
  attachment widget part files.
- Keep audio media projection changes in `agent_runtime_media_results.dart`.
- Keep action candidate rendering isolated in an operating card part file or
  behind the existing generic runtime candidate rendering path.
- If the dedicated action candidate card causes regressions, fall back to the
  generic runtime candidate card while preserving real approve/dismiss behavior.
- Server contract changes, if required, must remain additive and backward
  compatible with existing media result and approval item fields.
