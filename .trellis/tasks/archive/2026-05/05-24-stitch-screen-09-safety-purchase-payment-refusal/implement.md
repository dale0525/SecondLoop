# Stitch screen 09 safety purchase payment refusal implementation plan

## Pre-Start Review

- Confirm this task remains focused on one canonical screen:
  `8c87969f58254457bfb9dd85718fdd49`.
- Review `prd.md` and `design.md` before running `task.py start`.
- Do not modify Stitch export HTML or screenshot files.
- Do not record backend repository paths, deployment triggers, credentials,
  secrets, or environment-specific operational notes in tracked task files.
- Keep `docs/` untracked unless the user explicitly asks to track a docs change.

## Evidence Checklist

Read these before code edits:

- `docs/stitch-export/secondloop-operating-system/README.md`
- `docs/stitch-export/secondloop-operating-system/manifest.json`
- `docs/stitch-export/secondloop-operating-system/html/18-safety-purchase-payment-refusal-8c87969f58254457bfb9dd85718fdd49.html`
- `docs/stitch-export/secondloop-operating-system/screens/18-safety-purchase-payment-refusal-8c87969f58254457bfb9dd85718fdd49.jpg`
- `docs/product/final-product-shape.md`
- `docs/qa/final-product-acceptance.md`
- `docs/development/final-product-development-plan.md`
- Existing local renderers/tests:
  - `lib/features/agent_ui/agent_conversation_layouts.dart`
  - `lib/features/agent_ui/agent_operating_email_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_cards.dart`
  - `lib/features/agent_ui/agent_operating_system_tokens.dart`
  - `test/agent_conversation_stitch_eighth_screen_test.dart`

## Implementation Checklist

1. Record the final pre-edit difference notes in the working session:
   UI, functionality, state flow, and data/API wiring for screen 09.
2. Add a purchase/payment safety renderer:
   - Prefer a new part file such as
     `lib/features/agent_ui/agent_operating_safety_cards.dart` if the helper is
     more than a few small functions.
   - Detect safety records from `RuntimeWorkingSetRecord` using explicit
     `purchase-payment-safety` / `external_side_effect_blocked` fields.
   - Match records to the current user/assistant turn through source ids.
3. Wire the safety renderer into `_OperatingMessageList`:
   - Render after the assistant refusal for the matching turn.
   - Keep existing task, email, approval, web-research, and context-strip
     behavior intact.
   - Add a mode/status chip for `Blocked External Transaction` without breaking
     the existing email unavailable chip.
4. Implement the safety refusal UI:
   - assistant/security header;
   - visible refusal/no-transaction copy;
   - `Safe Alternatives` card with research, checklist, and reminder rows;
   - `Transaction Safety Protocol` metadata card.
5. Implement safe alternative interactions:
   - research path must only initiate a research/follow-up intent;
   - checklist path must create or draft a non-transaction checklist/task
     candidate, or show explicit degraded state;
   - reminder path must create or draft a reminder candidate, or show explicit
     degraded state;
   - no button may initiate purchase, payment, ticket booking, transfer, or an
     external side effect.
6. Add focused widget coverage:
   - create `test/agent_conversation_stitch_ninth_screen_test.dart`;
   - seed runtime turns and working-set safety records using production model
     fields;
   - assert refusal copy, no-side-effect status, metadata, safe alternatives,
     and absence of purchase/payment success text;
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
pixi run flutter test test/agent_conversation_stitch_ninth_screen_test.dart
pixi run flutter analyze lib/features/agent_ui/agent_conversation_page.dart lib/features/agent_ui/agent_conversation_layouts.dart
pixi run verify-changed
git diff --check
```

If a new part file or additional model/parser file is added, include it in the
targeted analyze command.

## Manual Review

- Build/run the local app in the existing project workflow.
- Use Computer Use at the manifest width `780`.
- Verify:
  - top safety chip says `Blocked External Transaction`;
  - user request and assistant refusal match the screen intent;
  - no-success/no-side-effect copy is visible;
  - safe alternatives are visible and clickable/degraded;
  - metadata includes skill, blocked action, status, audit id, source id, and
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

- Safety renderer part file and `_OperatingMessageList` wiring.
- Safety mode chip addition.
- New widget test and runtime fixture.
- Any optional runtime-field parser changes.
