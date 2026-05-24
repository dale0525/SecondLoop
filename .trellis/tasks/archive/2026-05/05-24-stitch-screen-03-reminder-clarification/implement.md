# Stitch screen 03 reminder clarification implementation plan

## Pre-start checks

- Confirm the task relationship:
  parent `05-24-stitch-canonical-screen-continuation`, child
  `05-24-stitch-screen-03-reminder-clarification`.
- Confirm the source set has been read for this screen:
  - `docs/stitch-export/secondloop-operating-system/README.md`
  - `docs/stitch-export/secondloop-operating-system/manifest.json`
  - `docs/stitch-export/secondloop-operating-system/html/12-chat-recurring-reminder-clarification-2584c8e54d014209adbd37b562e3ced1.html`
  - `docs/stitch-export/secondloop-operating-system/screens/12-chat-recurring-reminder-clarification-2584c8e54d014209adbd37b562e3ced1.jpg`
  - `docs/product/final-product-shape.md`
  - `docs/qa/final-product-acceptance.md`
  - `docs/development/final-product-development-plan.md`
- Confirm no implementation reference is taken from retired screens or
  superseded index `3aa56b7a88194a37a3c38abb3ef76618`.
- Keep the implementation scoped to screen 03 and shared Agent UI primitives.
- Preserve current clean git state; do not mix this task with archived screen 02
  changes.
- Do not edit or track Stitch export source files under `docs/`.

## Implementation checklist

1. Add the screen 03 widget test.
   - Create `test/agent_conversation_stitch_third_screen_test.dart`.
   - Reuse the screen 2 test wrapper pattern: `AppShell` + `AgentConversationPage`
     + fake `RuntimeAgentStateRepository` + fake runtime approval sender.
   - Use manifest width `780` and height `2436` unless the test harness needs a
     smaller vertical size for stability.
   - Fixture state must include the two user turns, two assistant turns, one
     pending intent runtime record, one memory approval item, one recurring
     reminder approval item, and no active recurring reminder rules.

2. Render pending intent state.
   - Add a small operating-shell pending intent card in
     `agent_operating_system_cards.dart`.
   - Project pending intent records from runtime state, using shared/private
     helper functions rather than repeated raw-map reads.
   - Insert the card after the assistant clarification turn associated with the
     source user or assistant message.
   - Add stable keys such as `agent_operating_pending_intent_<id>`.

3. Render memory and recurring approvals together.
   - Update `_OperatingMessageList._approvalCards()` so memory approvals no
     longer suppress recurring reminder approvals.
   - Add an operating-shell recurring reminder candidate card with schedule,
     next trigger, risk, audit, approve, edit, and dismiss controls.
   - Route approve/dismiss through `_resolveRuntimeApproval`.
   - Route edit through `_patchRuntimeApprovalTitle` only when the runtime item
     exposes editable `title`.
   - Keep unknown approval kinds on the existing generic/degraded path instead
     of inventing fake domain cards.
   - Verify recurring reminder controls are real: approve/dismiss submit runtime
     decisions, edit patches the runtime approval title, and failure surfaces an
     honest unavailable/error state.

4. Tune screen 03 visual details.
   - Align the normal operating composer placeholder with Stitch:
     `Type a message or command...`.
   - Keep existing local avatar/profile behavior rather than using the remote
     Stitch portrait.
   - Ensure card widths, status badges, and button labels remain readable at
     the manifest width.

5. Preserve existing behavior.
   - Re-run existing first/second Stitch tests and runtime approval edit tests
     after the new card rendering is added.
   - Watch file sizes; if any edited non-document source exceeds 1000 lines,
     split private widgets or helpers before continuing.

6. Escalate only if needed.
   - If the app cannot represent screen 03 with the existing runtime view state
     and approval APIs, make the required server changes in
     `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer` on its
     local main branch and push so staging deployment can pick it up.
   - Do not add local natural-language parsing in the Flutter app to compensate
     for missing runtime semantics.

## Validation commands

Run these after implementation:

```bash
pixi run flutter test test/agent_conversation_stitch_third_screen_test.dart
pixi run flutter test test/agent_conversation_stitch_first_screen_test.dart test/agent_conversation_stitch_second_screen_test.dart test/agent_conversation_runtime_approval_edit_test.dart
pixi run flutter analyze lib/features/agent_ui/agent_conversation_layouts.dart lib/features/agent_ui/agent_conversation_page.dart lib/features/agent_ui/agent_operating_system_cards.dart test/agent_conversation_stitch_third_screen_test.dart
SECONDLOOP_APP_ID=com.secondloop.secondloopdev SECONDLOOP_APP_NAME='SecondLoop Dev' pixi run bash scripts/flutter_with_defines.sh build macos --debug
git diff --check
pixi run verify-changed
```

Manual review:

- Launch the local app in a macOS debug run or the established project manual
  review path.
- Use Computer Use at the screen 03 manifest width.
- Verify the first viewport, chat turns, pending intent, both candidate cards,
  edit/approve/dismiss controls, composer, and bottom nav.

Completion report must include:

- Stitch screenId.
- Local route/component/state/API mapping.
- Missing functionality filled.
- Modified files.
- Screenshot/manual verification method and result.
- Known non-1:1 differences and reasons.
- Fresh test/lint/typecheck/build commands and results.

## Rollback points

- If pending-intent rendering becomes too invasive, keep the runtime fixture and
  card helper isolated so the card can be removed without changing approval
  flows.
- If recurring candidate edits expose a runtime sender limitation, keep approve
  and dismiss wired and surface title edit as unavailable through existing error
  handling rather than falling back to local mutation.
- If broad source files cross the 1000-line limit, stop and extract operating
  candidate widgets into a sibling part before adding further behavior.

## Start gate

Planning is ready for Phase 1.4 once the user reviews `prd.md`, `design.md`,
and `implement.md`. Only after that approval should this run:

```bash
pixi run python ./.trellis/scripts/task.py start 05-24-stitch-screen-03-reminder-clarification
```
