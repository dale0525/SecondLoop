# Stitch canonical screen continuation

## Goal

Continue the local Stitch-based SecondLoop frontend implementation from the
current in-progress state, preserving the user's source-of-truth constraints
and making each canonical product screen independently verifiable.

The immediate state is that canonical screen 2 has been implemented enough for
manual acceptance and automated checks, with uncommitted local changes still in
the working tree. The next work must either close out screen 2 cleanly or move
to the next canonical screen through the same per-screen mapping,
difference-analysis, real functionality, visual restoration, and verification
loop.

## Confirmed Facts

- Authoritative local design export:
  `docs/stitch-export/secondloop-operating-system/`.
- Source-of-truth entry screen:
  `3b8ef30093554bf2bc42e296ee36be6c`
  (`SecondLoop Final Stitch Source of Truth`).
- Canonical implementation register:
  `a5874f74133b435a9feb498e76a23fe4`.
- Retired register:
  `43a2a241349e40a4b3dd3d61c0d3c76b`.
- Superseded / incomplete index
  `3aa56b7a88194a37a3c38abb3ef76618` must not be used.
- Current completed/manual-reviewed product screen:
  `99cc1523c51a4e1d9017fb53a2bac9bb`
  (`Chat: Web Research Follow-up Continuity (Approved)`).
- Current uncommitted files include the screen 2 web-research follow-up UI,
  composer state, tokens, and widget test:
  - `lib/features/agent_ui/agent_conversation_layouts.dart`
  - `lib/features/agent_ui/agent_conversation_page.dart`
  - `lib/features/agent_ui/agent_operating_research_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_tokens.dart`
  - `test/agent_conversation_stitch_second_screen_test.dart`
- Screen 2 verification already run in the session:
  - `pixi run flutter test test/agent_conversation_stitch_second_screen_test.dart`
  - targeted `pixi run flutter analyze ...`
  - `pixi run verify-changed`
  - `git diff --check`
- Screen 2 manual review used Computer Use against a local macOS debug app and
  verified the web-research header, source cards, follow-up context chip,
  extracted evidence expansion, trace footer, and follow-up composer.

## Requirements

- Use only the local Stitch export directory listed above as visual/design
  source. Do not use stale local zips, retired/superseded screens, or Stitch
  drafts outside the canonical register.
- Before each screen implementation, read and use these local sources as the
  evidence base:
  - `docs/stitch-export/secondloop-operating-system/README.md`
  - `docs/stitch-export/secondloop-operating-system/manifest.json`
  - the corresponding screen HTML under
    `docs/stitch-export/secondloop-operating-system/html/`
  - the corresponding screen screenshot under
    `docs/stitch-export/secondloop-operating-system/screens/`
  - `docs/product/final-product-shape.md`
  - `docs/qa/final-product-acceptance.md`
  - `docs/development/final-product-development-plan.md`
- Treat `SecondLoop Final Stitch Source of Truth`
  (`3b8ef30093554bf2bc42e296ee36be6c`) as the entry point. Implement only the
  13 product screens in the canonical register
  (`a5874f74133b435a9feb498e76a23fe4`).
- Treat the retired register (`43a2a241349e40a4b3dd3d61c0d3c76b`) and
  superseded / incomplete index (`3aa56b7a88194a37a3c38abb3ef76618`) as
  negative evidence only. Do not implement from them.
- Maintain a screen-by-screen mapping from Stitch `screenId` to local
  route/component/state/API behavior before implementation.
- Work one screen, or one tightly related flow, at a time.
- For each screen, compare Stitch HTML and screenshot against local UI and
  record:
  - UI differences
  - functionality differences
  - state-flow differences
  - data/API wiring differences
- If a Stitch screen shows a product capability that belongs to the final
  product docs, acceptance docs, or canonical register, implement or wire the
  real capability before polishing the static UI.
- Use explicit degraded states for unavailable runtime, permissions, connector,
  or backend dependencies. Do not ship fake buttons, fake approval cards, or
  unbacked result panels.
- Keep implementation inside existing Flutter architecture. Do not copy the
  Stitch HTML directly into the app.
- Prefer shared tokens, primitives, and reusable components when a pattern
  appears across screens.
- Preserve product boundaries:
  - SecondLoop is a vault-first personal secretary agent, not an AIOps or
    monitoring tool.
  - Formal action execution goes through runtime, not local natural-language
    parsing.
  - Current facts require `web-research` with citations.
  - Formal mutations and external side effects require approval by default.
  - Email/calendar unavailable states must degrade to draft,
    `needs_configuration`, or `tool_unavailable`.
  - Purchase/payment/local shell/local computer operation must be refused or
    safely degraded.
  - Managed pro and self-managed expose the same user-facing capabilities.
- After each screen, perform Computer Use manual review at the manifest/canonical
  width and run fresh relevant checks before reporting completion.
- Each screen-specific widget test should include a lightweight responsive width
  matrix that covers narrow mobile, the manifest/canonical width, and desktop
  width. Add extra Computer Use spot checks for non-canonical widths only when
  the automated width matrix catches a layout issue or the screen includes
  layout-sensitive controls.
- Do not delete or revert user changes. Do not track `docs/` unless explicitly
  requested. Do not modify Stitch export source HTML/screenshots.
- If a canonical screen requires server behavior that is absent in the app's
  runtime/API contract, implement the server change in
  `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer` on its local
  main branch and push it so staging deployment can run.
- Each screen completion report must include: Stitch screenId, local
  route/component mapping, missing functionality filled, modified files,
  screenshot/manual verification result, known non-1:1 differences with
  reasons, and fresh test/lint/typecheck/build evidence.

## Canonical Screen Mapping Register

Initial mapping from `manifest.json` before continuing screen implementation:

| # | Stitch screenId | Canonical title | Local route/component/state/API target |
| --- | --- | --- | --- |
| 1 | `7478ab2f8f9b4ef2b89f2e8c6c1df11e` | Agent Chat: Personal Secretary Flow (Refined) | `AppShell` Chat tab -> `AgentConversationPage` mobile operating shell; `RuntimeAgentState` conversation turns, tasks, memory approvals; `SecretaryRuntimeClient` send/fetch agent state. |
| 2 | `99cc1523c51a4e1d9017fb53a2bac9bb` | Chat: Web Research Follow-up Continuity (Approved) | `AgentConversationPage` -> `_OperatingMessageList` -> `agent_operating_research_cards.dart`; runtime `web_research_drafts`, `citations_json`, `tool_trace`, context snapshot; runtime web-research skill result. |
| 3 | `2584c8e54d014209adbd37b562e3ced1` | Chat: Recurring Reminder Clarification (Approved) | `AgentConversationPage` mobile shell; runtime pending intent / clarification state, `memory_confirmation` and `recurring_reminder_confirmation` approval items; runtime approval patch/approve/reject API. |
| 4 | `0632921a825a4f1b9e91c2f66a4c97e3` | Task Mutation Approval: Recent Reference (Approved) | `AgentConversationPage` approval cards and task summary surfaces; runtime `task_mutation_confirmation`, recent entity refs, task-management skill, approval API. |
| 5 | `585ce0f7d36b4f55a8511bea0e2ef655` | Calendar Approval: Email Extraction (Approved) | Agent chat calendar/email candidate surfaces (`agent_calendar_email_*` patterns); runtime email/calendar extraction, draft/event candidate, `calendar_event_confirmation` approval API. |
| 6 | `2384fe0e4de54f4e97f9935f813ecd01` | Chat: File OCR With Attachment Tile (Approved) | Agent chat attachment tile and `agent_runtime_media_results.dart`; vault attachment upload/read, runtime media result / OCR metadata, document-ocr skill. |
| 7 | `3656acaa364f4e58b9d71c1d79f41809` | Chat: Meeting Audio Action Candidates (Approved) | Agent chat attachment/media result and action candidate surfaces; vault audio attachment, runtime transcript/minutes/action candidates, audio-meeting skill, approval API for formal actions. |
| 8 | `a8435575721c43b9a5398a242abc28d0` | Email Unauthorized: Draft Only (Approved) | Agent chat email degraded/draft surface; runtime email skill `needs_configuration` / `tool_unavailable` / draft-only response, no send side effect. |
| 9 | `8c87969f58254457bfb9dd85718fdd49` | Safety: Purchase Payment Refusal (Approved) | Agent chat safety refusal surface; runtime purchase-payment-safety skill, `external_side_effect_blocked`, no payment/purchase tool call. |
| 10 | `b1bc92c06b364d0594dea7c27cf02802` | Safety: Local Computer Operation Refusal (Approved) | Agent chat safety refusal surface; runtime local-computer-safety skill, no local shell/computer side effect. |
| 11 | `113754579c364c3b994e7bfbaa6f99d6` | Self-managed Setup: Provider Secrets and Capability Verification (Approved) | Settings runtime mode -> `SelfManagedSetupPage` / sections; setup controller, provider secrets, capability verification, runtime manifest persistence. |
| 12 | `7296ed1e87b9466489af5de513f0e24b` | Setup: Connect Cloudflare (Security Refinement) | Settings self-managed Cloudflare connection flow; Cloudflare authorization handoff, deployment helper state, secret safety boundary. |
| 13 | `37821c63daf74e7d96972338375758e7` | Desktop Agent Workbench: Research Continuity Refined | `AgentConversationPage` desktop workbench -> `agent_desktop_workbench_layout.dart` / primitives; runtime research continuity, approvals, context snapshot, web-research citations. |

## Acceptance Criteria

- [ ] Current screen 2 changes are either committed/handed off cleanly or
      explicitly preserved as the base for the next screen.
- [ ] The active next canonical screen has a documented
      `screenId -> local route/component/state/API` mapping.
- [ ] The active next screen has a documented Stitch-vs-local difference list
      before implementation.
- [ ] Any required missing product capability is implemented, wired, or
      represented by a real degraded state.
- [ ] Visual implementation is reviewed against manifest dimensions and local
      screenshot/HTML baselines.
- [ ] Each screen has automated responsive coverage for narrow mobile,
      manifest/canonical, and desktop widths, with any discovered overflow fixed.
- [ ] Computer Use manual review is performed for each completed screen at the
      manifest/canonical width, with targeted non-canonical spot checks when the
      automated width matrix exposes a responsive risk.
- [ ] Relevant Flutter tests, analyze/typecheck, and changed-file verification
      run with fresh evidence.
- [ ] Completion output for each screen includes:
      screenId, local mapping, missing functionality filled, modified files,
      screenshot/manual verification result, known non-1:1 differences, and
      commands run.

## Out of Scope

- Implementing retired register screens.
- Using superseded screen `3aa56b7a88194a37a3c38abb3ef76618`.
- Replacing the app architecture with generated Stitch HTML.
- Tracking or editing exported Stitch source files.
- Broad backend work unless a canonical screen requires a runtime/API contract
  that is absent or cannot reasonably degrade in the app.

## Open Questions

- Resolved: this task is a parent coordination task. Each independently
  verifiable canonical screen should be owned by a child task.

## Child Task Map

- `05-24-stitch-screen-01-personal-secretary-flow`: adopt and close out the
  already-implemented first canonical screen,
  `7478ab2f8f9b4ef2b89f2e8c6c1df11e`
  (`Agent Chat: Personal Secretary Flow (Refined)`).
- `05-24-stitch-screen-02-web-research-closeout`: adopt and close out the
  existing screen 2 implementation and validation evidence.
- `05-24-stitch-screen-03-reminder-clarification`: implement and verify the next
  canonical screen,
  `2584c8e54d014209adbd37b562e3ced1`
  (`Chat: Recurring Reminder Clarification (Approved)`).
- `05-24-stitch-screen-04-task-mutation-approval`: implement and verify
  `0632921a825a4f1b9e91c2f66a4c97e3`
  (`Task Mutation Approval: Recent Reference (Approved)`).
- `05-24-stitch-screen-05-calendar-email-approval`: implement and verify
  `585ce0f7d36b4f55a8511bea0e2ef655`
  (`Calendar Approval: Email Extraction (Approved)`).
- `05-24-stitch-screen-06-file-ocr-attachment`: implement and verify
  `2384fe0e4de54f4e97f9935f813ecd01`
  (`Chat: File OCR With Attachment Tile (Approved)`).
- `05-24-stitch-screen-07-meeting-audio-action-candidates`: implement and
  verify `3656acaa364f4e58b9d71c1d79f41809`
  (`Chat: Meeting Audio Action Candidates (Approved)`).
- `05-24-stitch-screen-08-email-unauthorized-draft-only`: implement and verify
  `a8435575721c43b9a5398a242abc28d0`
  (`Email Unauthorized: Draft Only (Approved)`).
- `05-24-stitch-screen-09-safety-purchase-payment-refusal`: implement and
  verify `8c87969f58254457bfb9dd85718fdd49`
  (`Safety: Purchase Payment Refusal (Approved)`).
- `05-24-stitch-screen-10-safety-local-computer-operation-refusal`: implement
  and verify `b1bc92c06b364d0594dea7c27cf02802`
  (`Safety: Local Computer Operation Refusal (Approved)`).
- `05-24-stitch-screen-11-self-managed-setup-provider-secrets`: implement and
  verify `113754579c364c3b994e7bfbaa6f99d6`
  (`Self-managed Setup: Provider Secrets and Capability Verification
  (Approved)`).
- `05-24-stitch-screen-12-connect-cloudflare-security-refinement`: implement
  and verify `7296ed1e87b9466489af5de513f0e24b`
  (`Setup: Connect Cloudflare (Security Refinement)`).
- `05-24-stitch-screen-13-desktop-agent-workbench-research-continuity`:
  implement and verify `37821c63daf74e7d96972338375758e7`
  (`Desktop Agent Workbench: Research Continuity Refined`).

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
