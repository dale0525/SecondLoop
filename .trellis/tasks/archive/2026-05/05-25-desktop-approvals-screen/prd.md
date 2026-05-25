# Restore desktop Approvals screen

## Goal

Restore the desktop Approvals workbench from Stitch screen
`147110e76d524b1f90a2f936123aef4e` as the desktop sidebar Approvals
destination. The screen must manage real runtime approval items and guardrails.

## Requirements

- Local mapping: desktop sidebar `Approvals` ->
  `DesktopApprovalsWorkbenchPage`.
- Use `RuntimeAgentState.approvalItems` as the primary queue.
- Render queue filters, selected detail, proposed diff, audit trace, status
  badges, and degraded system notices.
- Approve/reject must call `ChatRuntimeApprovalSender.submitApprovalDecision`
  for actionable pending items.
- Refused purchase/payment items and `needs_configuration` items must not offer
  a fake approval path.
- Request changes/configure/retry must show or trigger honest degraded behavior
  unless a real runtime endpoint exists.
- Include loading, empty, and fetch-error states.

## Acceptance Criteria

- [ ] At `2560x2048`, the first viewport matches the Stitch Approvals layout:
      queue column, diff detail column, audit/guardrail column.
- [ ] Selecting a queue item updates the detail and status panels.
- [ ] Approve/reject is wired to runtime approval sender and refresh path.
- [ ] Blocked/degraded items are visibly non-successful and cannot fake mutation.
- [ ] Targeted widget tests pass.

## Notes

- UI differences to close before coding: existing Review page is a generic
  queue/detail page and is pushed as a separate route.
- Functional differences to close before coding: current desktop shell has no
  full approval diff/audit surface.
- State/API differences to close before coding: action must use runtime
  approval sender and avoid local-only review state.
