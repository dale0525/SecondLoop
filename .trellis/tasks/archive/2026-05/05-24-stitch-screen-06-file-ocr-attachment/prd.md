# Stitch screen 06 file OCR attachment

## Goal

Implement and verify the sixth canonical Stitch product screen:
`Chat: File OCR With Attachment Tile (Approved)`.

The screen demonstrates a runtime-first file/media flow where the user uploads
`qa-ocr-sample.png`, asks the agent to extract and summarize the image text, the
chat shows a prominent attachment tile synced to Vault, the assistant renders a
real media/OCR result sourced from runtime/vault state, and a follow-up reminder
candidate remains pending until the user approves it.

## Confirmed Facts

- Stitch screenId:
  `2384fe0e4de54f4e97f9935f813ecd01`.
- Manifest dimensions: mobile, width `780`, height `2184`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/15-chat-file-ocr-with-attachment-tile-2384fe0e4de54f4e97f9935f813ecd01.html`
  - `docs/stitch-export/secondloop-operating-system/screens/15-chat-file-ocr-with-attachment-tile-2384fe0e4de54f4e97f9935f813ecd01.jpg`
- Stitch source shows:
  - managed-pro header with `Vault Upload` capability signal;
  - user attachment tile for `qa-ocr-sample.png`, `2.4 MB`;
  - user prompt:
    `帮我看看这张图片里写了什么，顺便总结一下。`;
  - processing chain labels including `ocr`, `summarize`, `vault`, and source
    sync state `Source synced to Vault`;
  - assistant response:
    `I've processed the image. Here is the extracted text and a summary.`;
  - `Media Result` card with `OCR TEXT` value `QA MEDIA`, summary
    `High-fidelity document scan containing operational test data.`,
    `Source ID: ATT-2026-0523-001`, `Confidence: 98%`, and
    `Saved to Vault: Yes`;
  - follow-up approval card titled `Follow up on QA Media` with subtitle
    `Create a reminder to review extraction result tomorrow.`, status
    `Pending Approval`, and `Approve` / `Dismiss` actions.
- Product docs define the media boundary:
  - attachments enter Vault, then cloud/runtime coordinates media pipeline;
  - image/PDF OCR, summaries, field extraction, source references, and
    searchable fragments are runtime/vault concerns;
  - managed pro must not present local OCR/Whisper/embedding/runtime as the
    normal product path;
  - files/media results must write back to Vault and preserve sources.
- QA docs define the image OCR acceptance path:
  - use `docs/qa-assets/qa-ocr-sample.png`;
  - the user's chat bubble must show an image thumbnail as the main attachment
    tile, with filename only as a compact label;
  - tapping the thumbnail/tile must open image or attachment detail;
  - assistant result must include a media result whose OCR text contains
    `QA MEDIA`;
  - `ocr_text` must be the visible image text, not an image description;
  - `summary` may contain the explanation/description;
  - source/attachment id must point to the uploaded attachment;
  - managed pro must not mention local OCR runtime, Rust, FRB, or desktop OCR as
    the normal path.
- Development docs define the phase 5 target:
  - implement `document-ocr` skill contract, provider simulation, source
    citation, and write-back;
  - App displays media job state, sources, summaries, extracted fields, and
    approval cards.
- Existing app code already has:
  - composer attachment upload metadata and separate runtime upload payloads;
  - user message attachment tiles in `agent_conversation_attachment_widgets.dart`;
  - runtime media result projection/rendering in `agent_runtime_media_results.dart`;
  - tests for image attachment thumbnail hydration, media result rendering, and
    attachment opening;
  - runtime approval rendering for memory, recurring reminder, task mutation,
    and calendar event approvals.
- Current local media result UI is generic and currently labels OCR text through
  the broader transcript section. It does not yet fully match the Stitch media
  result card metadata shape for OCR text, confidence, source id, saved-to-vault
  state, and a reminder approval candidate in the same screen.
- User-supplied implementation contract inherited from the parent task:
  - use only `docs/stitch-export/secondloop-operating-system/` as the Stitch
    source;
  - read README, manifest, corresponding HTML/screenshot, final product shape,
    QA acceptance, and development plan before implementation;
  - implement only canonical register product screens;
  - treat retired/superseded screens as negative examples only;
  - fill real functionality/state/API wiring before visual polish;
  - perform Computer Use review at manifest dimensions before completion;
  - run fresh `pixi` verification and report exact evidence.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `2384fe0e4de54f4e97f9935f813ecd01` | `AppShell` Chat tab -> `AgentConversationPage` mobile operating shell -> `_OperatingMessageList` user attachment and assistant media result surfaces in `agent_conversation_attachment_widgets.dart`, `agent_operating_message_bubbles.dart`, `agent_runtime_media_results.dart`, and reminder approval primitives; runtime state from `RuntimeAgentState.conversationTurns`, `RuntimeAgentState.workingSetRecords`, `RuntimeAgentState.approvalItems`, `RuntimeAgentState.latestContextSnapshot`, attachment bytes fetched through `ChatRuntimeAttachmentContentFetcher`, and approval API through `RuntimeSecretaryAppService.approveApprovalItem` / `rejectApprovalItem`. |

## Stitch-vs-Local Difference List Before Implementation

- UI differences:
  - Stitch shows a wide image-first attachment tile with thumbnail, filename,
    size, prompt text, compact processing icons, and explicit
    `Source synced to Vault` state.
  - Current local attachment tiles show image previews and filename/size, but
    may need stronger thumbnail hierarchy, manifest-width layout polish, and
    source-sync/status text for the screen 06 flow.
  - Stitch media result card uses a distinct header, grey OCR text block,
    summary block, source id, confidence, and saved-to-vault metadata.
    Current local media result rendering is a generic inline section under the
    assistant reply and does not yet expose the complete OCR metadata shape.
  - Stitch includes a follow-up approval card immediately after the media
    result. Current runtime approval surfaces support reminders, but screen 06
    needs a fixture and layout proving media result + reminder approval coexist.
- Functionality differences:
  - Stitch implies upload to Vault, OCR, summarization, source tracking, and
    reminder candidate generation in one conversation.
  - Local App must render real runtime/vault state and approval items rather
    than using storyboard/demo-only state.
  - Tapping the attachment tile must open the image/attachment detail page using
    hydrated bytes when available.
  - Approve/dismiss must use the real runtime approval path and refresh state.
- State-flow differences:
  - Media result must attach to the assistant turn related to the uploaded
    attachment, using explicit assistant/source turn ids when available and safe
    attachment matching otherwise.
  - The OCR result must remain distinct from summary text so the UI never
    treats an image description as extracted OCR.
  - The follow-up reminder candidate remains pending until approval succeeds.
  - Media result, attachment source, and approval candidate must remain visible
    together; rendering one should not hide the others.
- Data/API wiring differences:
  - Runtime media records may provide OCR through `ocr_text` / `ocrText` /
    `text`, summary through `summary` / `llm_summary`, source attachment through
    `attachment_id`, and citations/metadata through record fields.
  - The App may need typed projection for `confidence`, `source_id` /
    `sourceId`, `saved_to_vault` / `savedToVault`, `status`, and OCR label
    selection while preserving backward compatibility with audio media results.
  - If runtime payloads lack a field needed for an honest card, the App must
    show an explicit degraded/unavailable value and identify whether a
    `SecondLoopServer` contract change is required before claiming full screen
    completion.

## Requirements

- Implement the screen through existing Flutter architecture. Do not paste
  Stitch HTML.
- The fixture/user flow must include:
  - user message:
    `帮我看看这张图片里写了什么，顺便总结一下。`;
  - image attachment tile:
    `qa-ocr-sample.png`, `2.4 MB`, image preview, and tap target;
  - processing labels equivalent to OCR, summarization, Vault/source sync;
  - assistant response explaining the image was processed;
  - a media result with `OCR TEXT` / OCR-equivalent label, `QA MEDIA`, summary,
    source id, confidence, and saved-to-vault state;
  - a follow-up reminder approval candidate with Approve/Dismiss actions.
- The attachment tile must keep the preview visually dominant and the filename
  secondary, matching the QA acceptance requirement.
- Attachment tile tap must navigate to image preview or attachment detail and
  must not silently no-op when an attachment id is available.
- The media result must be runtime-backed from `working_set_records` or context
  snapshot records of `kind == media_result`.
- OCR text and summary must be separate display fields. OCR text must be the
  extracted text (`QA MEDIA` in the screen fixture), not the summary.
- Source id, confidence, and saved-to-vault metadata must render from runtime
  fields when present, with honest degraded labels when absent.
- Media results must stay associated with the correct assistant turn after a
  user attachment turn.
- The follow-up approval must be runtime-backed. It may use the existing
  reminder/recurring reminder approval surface if that is the real runtime
  contract for the candidate; do not create a fake static card.
- Approve/dismiss controls must use the real runtime approval sender/service
  and refresh visible runtime state after completion.
- Preserve product boundaries:
  - managed pro normal path is cloud/runtime/vault, not local OCR runtime;
  - high-cost media jobs must be able to degrade to budget confirmation if the
    runtime asks for it;
  - the App must not claim media was saved to Vault unless runtime state says
    it was saved or synced;
  - unavailable OCR/provider/runtime state must be visible rather than faked.
- Match the local Stitch screenshot/HTML first viewport, attachment tile,
  processing chain, assistant media result hierarchy, follow-up approval,
  composer, and bottom navigation as closely as possible within the existing
  Flutter architecture.
- Do not track or edit `docs/`; the local Stitch export is a design baseline.
- If app-side runtime/API wiring is insufficient, identify whether a real
  server change is required in
  `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer` before
  claiming the screen is complete.

## Acceptance Criteria

- [ ] A screen 06 mapping table and Stitch-vs-local difference list exist
      before implementation.
- [ ] The rendered UI matches the canonical Stitch first viewport, image-first
      attachment tile, processing labels, assistant response, media result
      hierarchy, metadata, follow-up approval, composer, and bottom nav as
      closely as the app architecture allows.
- [ ] A runtime-state fixture can render the uploaded image attachment, OCR
      media result, and follow-up approval candidate in the same conversation.
- [ ] OCR text displays `QA MEDIA` as extracted text and remains separate from
      summary/description.
- [ ] Media result details include source id, confidence, saved-to-vault state,
      attachment/source reference, and honest degraded values for missing
      optional metadata.
- [ ] The attachment tile is tappable and opens image preview or attachment
      detail in the screen fixture.
- [ ] Approve/dismiss controls are wired to the runtime approval flow and expose
      busy/error state through existing approval UI behavior.
- [ ] Existing audio/media result tests continue to pass or are updated to the
      refined contract without weakening runtime-first behavior.
- [ ] A focused widget test covers the runtime-state fixture for screen 06.
- [ ] The screen-specific widget test includes a responsive width matrix for
      narrow mobile, manifest width `780`, and desktop width.
- [ ] Computer Use manual review is performed at manifest width after the UI
      changes.
- [ ] Relevant `pixi` checks pass with fresh evidence, including focused tests,
      analyzer/typecheck, build or documented build-equivalent gate, and
      changed-file verification.
- [ ] Completion output includes screenId, mapping, functionality filled,
      modified files, screenshot/manual verification result, known non-1:1
      differences, and commands run.

## Out of Scope

- Implementing screen 07 meeting audio or later canonical screens.
- Implementing retired/superseded media designs.
- Replacing app architecture with generated Stitch HTML.
- Implementing a full document OCR provider/server pipeline unless the existing
  runtime contract cannot honestly represent the screen state.
- Claiming real Vault persistence, OCR, or reminder creation when runtime only
  provides a pending/degraded state.
- Tracking or editing exported Stitch source files.

## Open Questions

- None currently. The screen scope and product behavior are defined by the
  canonical Stitch register, final product docs, QA acceptance docs, current
  app runtime/vault surfaces, and the parent task mapping.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
- This is a complex child task because it spans attachment rendering, runtime
  media result projection, approval actions, responsive UI, and manual review.
  Add `design.md` and `implement.md` before `task.py start`.
