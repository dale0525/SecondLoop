# Restore desktop Approvals screen - Design

## Local Mapping

- Stitch screenId: `147110e76d524b1f90a2f936123aef4e`
- Route/component: desktop shell sidebar `Approvals` ->
  `DesktopApprovalsWorkbenchPage`
- State: `RuntimeAgentState.approvalItems`, `recentEntityRefs`,
  `latestContextSnapshot`, `auditRefs`
- API wiring: `RuntimeAgentStateRepository.fetchAgentState` for refresh;
  `ChatRuntimeApprovalSender.submitApprovalDecision` for approve/reject

## UI Model

Approval cards are normalized from `SecretaryRuntimeApprovalItem` and record
metadata:

- type/kind: `kind` with title fallback.
- risk: `record.risk`, `risk_level`, external flags, or derived default.
- status: `record.status`, blocked flags, `needs_configuration`, or pending.
- target/source/audit ids from `taskId`, `sourceIntentId`, `record`, and
  `auditRefs`.
- diff before/after from common record keys plus generic fallback.

## Actions

- Pending actionable approval: enable Approve and Reject.
- Refused payment/purchase/local-computer items: disable Approve and explain
  refused/degraded state.
- Needs configuration: disable Approve where the target tool is unavailable and
  route Configure to Settings/degraded notice.
- Request changes: show `tool_unavailable` until runtime supports edits.

## Edge Cases

- Empty queue: show no pending approvals with audit policy hints.
- Repository error: show retryable error.
- Missing diff metadata: show generic proposed change text from item title and
  reason, not fabricated fields.
