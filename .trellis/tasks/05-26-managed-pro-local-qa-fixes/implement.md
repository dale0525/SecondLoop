# Implementation Plan

## Checklist

- [ ] Reproduce the focused app-side failures with targeted commands:
      `app_runtime_first_semantics`, `cloud-runtime-scenarios-test`, and
      `managed-pro-agent-ui-acceptance` where environment allows.
- [ ] Fix app shell/test harness navigation so desktop Settings can be opened
      deterministically by scenario tests and integration wrappers.
- [ ] Fix Agent conversation rendering regression:
      - desktop context rail appears at desktop sizes;
      - assistant markdown and rich markdown render;
      - suggestion and evidence footers render when metadata exists;
      - refreshed runtime state is associated with the correct turn.
- [ ] Fix UI acceptance reachability for media `Fields` and related storyboard
      tabs without depending on brittle text-only navigation.
- [ ] Fix QA asset path resolution in `scripts/managed_pro_acceptance.py`.
- [ ] Fix task creation / task approval rendering so applied state, diffs,
      source/risk/audit metadata, and formal Tasks visibility match runtime
      state.
- [ ] Fix search answer/citation visibility and fail-closed trace labels.
- [ ] Fix safety refusal visibility for purchase/payment and local-computer
      blocked operations.
- [ ] Fix or honestly degrade Quick Capture desktop entry behavior; remove or
      repurpose misleading floating `+` where it is not a real Quick Capture
      entry.
- [ ] Run focused Flutter tests after each area, then run broader managed pro
      acceptance commands.
- [ ] If server-side contract gaps remain after app fixes, make a private
      runtime change, push its `main` branch, wait for staging, and rerun live
      evidence. Do not commit private details in this repository.
- [ ] Continue manual QA with the local managed pro test account and update the
      user with pass/fail/live-pending outcomes.

## Validation Commands

- `pixi run flutter test test/agent_conversation_test.dart`
- `pixi run flutter test test/quick_capture_test.dart test/quick_capture_runtime_first_semantics_test.dart`
- `pixi run cloud-runtime-scenarios-test`
- `pixi run managed-pro-agent-ui-acceptance`
- `pixi run managed-pro-acceptance-dry-run`
- `pixi run cloud-runtime-automation-test`
- `pixi run flutter test test/no_rust_dependency_for_runtime_client_test.dart`
- `pixi run managed-pro-acceptance`
- Live/manual QA commands from `docs/qa/managed-pro-local-qa.md` when
  credentials, providers, and staging are available.

## Risky Files And Rollback Points

- `lib/features/agent_ui/agent_conversation_page.dart`
- `lib/features/agent_ui/agent_conversation_layouts.dart`
- `lib/features/agent_ui/agent_conversation_widgets.dart`
- `lib/features/agent_ui/agent_desktop_workbench_layout.dart`
- `lib/features/agent_ui/*operating*_cards.dart`
- `lib/app/router.dart`
- `integration_test/support/dynamic_app_harness.dart`
- `integration_test/managed_pro_agent_ui_acceptance_test.dart`
- `scripts/managed_pro_acceptance.py`
- Tests under `test/agent_conversation*`, `test/scenarios`, and
  `integration_test/scenarios`.

Rollback by reverting the smallest area-specific file set after a failed
focused test, then rerun the same focused command before proceeding.

## Review Gates

- Do not start implementation until this plan is approved.
- Before editing code, load `trellis-before-dev` for the relevant frontend/core
  files.
- After code changes, run `trellis-check` and the validation commands that match
  the changed areas.
