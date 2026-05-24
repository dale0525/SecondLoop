# Stitch screen 10 safety local computer operation refusal implementation plan

## Pre-Start Review

- Confirm this task remains focused on one canonical screen:
  `b1bc92c06b364d0594dea7c27cf02802`.
- Review `prd.md` and `design.md` before running `task.py start`.
- Do not modify Stitch export HTML or screenshot files.
- Do not record backend repository paths, deployment triggers, credentials,
  secrets, or environment-specific operational notes in tracked task files.
- Keep `docs/` untracked unless the user explicitly asks to track a docs
  change.

## Evidence Checklist

Read these before code edits:

- `docs/stitch-export/secondloop-operating-system/README.md`
- `docs/stitch-export/secondloop-operating-system/manifest.json`
- `docs/stitch-export/secondloop-operating-system/html/19-safety-local-computer-operation-refusal-b1bc92c06b364d0594dea7c27cf02802.html`
- `docs/stitch-export/secondloop-operating-system/screens/19-safety-local-computer-operation-refusal-b1bc92c06b364d0594dea7c27cf02802.jpg`
- `docs/product/final-product-shape.md`
- `docs/qa/final-product-acceptance.md`
- `docs/development/final-product-development-plan.md`
- Existing local renderers/tests:
  - `lib/features/agent_ui/agent_conversation_layouts.dart`
  - `lib/features/agent_ui/agent_operating_safety_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_tokens.dart`
  - `test/agent_conversation_stitch_ninth_screen_test.dart`

## Implementation Checklist

1. Record the final pre-edit difference notes in the working session:
   UI, functionality, state flow, and data/API wiring for screen 10.
2. Extend the safety renderer:
   - detect `local-computer-safety` records through explicit skill/tool/action
     fields;
   - keep purchase/payment classification unchanged;
   - use source ids to associate a local-computer safety record with the current
     user/assistant turn.
3. Wire local-computer safety into `_OperatingMessageList`:
   - render the local refusal bubble instead of the generic assistant bubble for
     the matching assistant turn;
   - render local safety protocol, alternative action, and audit cards after the
     assistant refusal;
   - add a `Local Operation Blocked` top chip without breaking the existing
     transaction safety chip.
4. Implement the local-computer refusal UI:
   - left-accent assistant refusal with exact no-action copy;
   - `Safety Protocol` card with no-command/no-local-file/no-terminal evidence;
   - `Alternative Action` manual cleanup checklist;
   - `Audit & Safety` metadata card.
5. Implement safe interaction behavior:
   - `Save to Vault` prepares a non-executing manual checklist follow-up or
     draft prompt through the existing safe follow-up composer path;
   - no control may execute shell, Finder, desktop automation, or local file
     mutation.
6. Add focused widget coverage:
   - create `test/agent_conversation_stitch_tenth_screen_test.dart`;
   - seed runtime turns and a local-computer safety working-set record with
     production-like fields;
   - assert refusal copy, protocol checklist, alternative checklist, metadata,
     mode chip, safe follow-up preparation, and absence of shell success copy;
   - run a responsive matrix for narrow mobile, manifest width `780`, and
     desktop width.
7. Check file size before and after edits:
   - if any non-document file exceeds 1000 lines, refactor it before closeout.
8. If the app contract cannot represent the required safety record:
   - add optional-compatible parser/UI support first;
   - only modify backend code if UI-only compatibility is insufficient;
   - keep backend operational details out of tracked planning artifacts and
     report them only at the appropriate level in the final user-facing
     closeout.

## Validation Commands

Use repo commands, preferring `pixi`.

```bash
pixi run flutter test test/agent_conversation_stitch_tenth_screen_test.dart
pixi run flutter analyze lib/features/agent_ui/agent_conversation_layouts.dart lib/features/agent_ui/agent_operating_safety_cards.dart
pixi run verify-changed
git diff --check
```

If a new part file or additional model/parser file is added, include it in the
targeted analyze command.

## Manual Review

- Build/run the local app in the existing project workflow.
- Use Computer Use at the manifest width `780`.
- Verify:
  - top safety chip says `Local Operation Blocked`;
  - user request and assistant refusal match the screen intent;
  - no-command/no-local-file/no-terminal-automation evidence is visible;
  - alternative checklist is visible and the save action only prepares a manual
    draft/follow-up;
  - metadata includes skill, refused status, blocked action, source id, and
    tool trace where available;
  - no layout overflow or clipped long text appears.

## Completion Report Checklist

Report these after implementation and verification:

- Stitch screenId.
- Local route/component/state/API mapping.
- Missing functionality filled or safely degraded.
- Modified files.
- Screenshot/manual verification method and result.
- Known non-1:1 visual or functional differences and reasons.
- Fresh tests, lint/typecheck/build/changed-file verification commands and
  results.

## Rollback Points

- Safety renderer additions and `_OperatingMessageList` wiring.
- Safety mode chip addition.
- New widget test and runtime fixture.
- Any optional safety helper extraction.
