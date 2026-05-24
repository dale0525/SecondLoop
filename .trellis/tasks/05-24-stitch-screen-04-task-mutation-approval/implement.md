# Stitch screen 04 task mutation approval implementation plan

## Pre-Implementation Checklist

- [ ] Load `trellis-before-dev` before editing code.
- [ ] Read relevant frontend specs from `.trellis/spec/frontend/`.
- [ ] Re-open the local evidence sources:
      `README.md`, `manifest.json`, screen 04 HTML/screenshot,
      `docs/product/final-product-shape.md`,
      `docs/qa/final-product-acceptance.md`, and
      `docs/development/final-product-development-plan.md`.
- [ ] Inspect current approval components and runtime approval tests before
      changing any values or payload parsing.

## Ordered Implementation Checklist

- [ ] Add or refine focused task mutation display data extraction for:
      target task, current title, proposed title, mutation kind, resolver
      detail, source, audit id, context snapshot, runtime tool, and risk label.
- [ ] Update the task mutation approval card UI so title-change approvals can
      render the Stitch hierarchy: target entity, resolver detail, proposed
      title diff, metadata, pending notice, and approve/edit/reject actions.
- [ ] Preserve existing due-date mutation rendering or migrate it to the same
      display model without losing behavior.
- [ ] Ensure approve/reject busy/error state remains wired to
      `RuntimeSecretaryAppService`.
- [ ] Implement edit as a real approval patch when supported, or an honest
      unavailable/degraded state when unsupported.
- [ ] Add a screen 04 widget fixture/test at manifest width `780` that covers
      the create-task turn, relative title-change request, current task preview,
      pending approval card, title diff, runtime metadata, and action controls.
- [ ] Update existing task mutation approval tests only where the refined UI
      changes expected text/keys, without weakening runtime-first assertions.
- [ ] Run Computer Use manual review against the local debug app at the screen
      width after code changes.

## Validation Commands

- `pixi run flutter test test/agent_conversation_stitch_fourth_screen_test.dart`
- `pixi run flutter test test/agent_conversation_runtime_approval_test.dart`
- Targeted analyzer command for changed Dart files.
- `pixi run verify-changed`
- `git diff --check`

## Risky Files and Rollback Points

- `lib/features/conversation_cards/approval_preview_card.dart`: high visual and
  existing-test impact because it is shared by task approvals.
- `lib/features/agent_ui/agent_conversation_page.dart`: approval decision and
  display-data wiring; avoid changing runtime sender semantics.
- `lib/features/agent_ui/agent_conversation_layouts.dart`: operating-shell
  approval rendering; keep memory/reminder cards stable.
- New focused test fixture: keep all runtime data local to the test and avoid
  relying on live backend state.

## Review Gate Before Start

- Planning is ready when this PRD, design, and implementation plan have been
  reviewed and the user approves `task.py start` for
  `05-24-stitch-screen-04-task-mutation-approval`.
