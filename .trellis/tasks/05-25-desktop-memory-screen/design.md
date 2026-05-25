# Restore desktop Memory screen - Design

## Local Mapping

- Stitch screenId: `7abb8269cfa74ece903f4adfab237c6e`
- Route/component: desktop shell sidebar `Memory` ->
  `DesktopMemoryWorkbenchPage`
- State: `RuntimeAgentState.memoryRecords`, memory-like
  `RuntimeAgentState.approvalItems`, `latestContextSnapshot`, `auditRefs`
- API wiring: `RuntimeAgentStateRepository.fetchAgentState` for refresh;
  `ChatRuntimeApprovalSender.submitApprovalDecision` for pending candidate
  approve/reject

## UI Model

Memory rows are mapped from `RuntimeWorkingSetRecord`:

- title: `record.title`, with `summary/body/text` fallback in detail.
- status: `record.status` or `active`.
- source: `record.raw.source`, `source_type`, `source_message_id`, or `runtime`.
- age: `record.updatedAtMs`.
- confidence/context id: `record.raw.confidence`,
  `record.raw.context_snapshot_id`, `latestContextSnapshot.id`.

Pending candidates are mapped from approval items with memory-related kind/title
or record metadata. If none exist, show a compact empty state.

## Actions

- Candidate Approve/Reject: submit runtime decision, then request refresh.
- Archive/Edit Proposal/Request Removal/Add Entry: show explicit
  `approval_required`/`tool_unavailable`; do not mutate local memory.
- Search: client-side filter over loaded runtime records.

## Edge Cases

- No repository/auth: render `tool_unavailable` degraded page.
- Repository error: render retryable error state.
- No records: render empty memory table and status banner.
