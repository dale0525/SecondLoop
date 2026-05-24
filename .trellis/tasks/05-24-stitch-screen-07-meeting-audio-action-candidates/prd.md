# Stitch screen 07 meeting audio action candidates

## Goal

Implement and verify the seventh canonical Stitch product screen:
`Chat: Meeting Audio Action Candidates (Approved)`.

The screen demonstrates a runtime-first audio meeting flow where an uploaded
meeting recording is processed into a vault-backed summary and action item
candidates. Action items must remain candidates until the user explicitly
creates or approves them.

## Confirmed Facts

- Stitch screenId:
  `3656acaa364f4e58b9d71c1d79f41809`.
- Manifest dimensions: mobile, width `780`, height `2630`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/16-chat-meeting-audio-action-candidates-3656acaa364f4e58b9d71c1d79f41809.html`
  - `docs/stitch-export/secondloop-operating-system/screens/16-chat-meeting-audio-action-candidates-3656acaa364f4e58b9d71c1d79f41809.jpg`
- Stitch source shows:
  - prompt `Process the audio recording from the Q3 Planning Sync and extract key actions.`;
  - attachment tile `q3_planning_sync_raw.m4a`, `45:12`, `42 MB`;
  - `High-fidelity processing confirmed`;
  - assistant response confirming processing;
  - meeting summary `MTG-Q3-2026-001` saved to Vault;
  - action item candidates `ACT-091`, `ACT-092`, and `ACT-093`.
- Product docs require audio understanding to be runtime/vault/provider-backed,
  with high-cost media jobs confirmed before execution.
- QA docs define `QA-FILE-03` for meeting audio: transcript, minutes,
  decisions, and action items must be visible; formal task creation goes
  through candidate or approval behavior.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `3656acaa364f4e58b9d71c1d79f41809` | `AgentConversationPage` mobile shell; user attachment tile via `agent_conversation_attachment_widgets.dart`; runtime media/audio result surfaces through `agent_runtime_media_results.dart` or shared operating-system cards; action candidates through runtime approval/candidate state and approval sender APIs. |

## Requirements

- Before implementation, compare the Stitch HTML/screenshot with the current
  local audio attachment and media result UI and record UI, functionality,
  state-flow, and runtime data differences.
- Use only runtime/vault/media state as the source for transcript, summary,
  source id, confidence, saved-to-vault state, and action candidates.
- The uploaded audio tile must be visible in the user's message with filename,
  duration, size, and audio affordance.
- The assistant result must show a meeting summary saved to Vault and expose
  transcript/source access without implying local Whisper/OCR is the managed-pro
  path.
- Action items must be rendered as candidates with real create/dismiss/approval
  behavior or an explicit degraded state.
- High-cost/high-fidelity audio processing must show budget/confirmation state
  before claiming execution.
- Do not create formal tasks from audio action candidates without user action.
- Keep responsive automated coverage for narrow mobile, manifest width, and
  desktop width.

## Acceptance Criteria

- [ ] Screen mapping and Stitch-vs-local difference list are recorded before
      implementation edits.
- [ ] Runtime-backed audio attachment, meeting summary, transcript/source
      metadata, and action candidates render at the manifest width.
- [ ] Candidate create/dismiss/approval paths are real or honestly degraded.
- [ ] A focused widget test covers narrow mobile, `780` width, and desktop
      width.
- [ ] Computer Use manual review is performed at the manifest width.
- [ ] Fresh relevant Flutter tests, analyze/typecheck, `pixi run verify-changed`,
      and `git diff --check` are recorded before closeout.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
