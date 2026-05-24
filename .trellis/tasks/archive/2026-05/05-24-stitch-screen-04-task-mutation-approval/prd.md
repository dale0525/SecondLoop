# Stitch screen 04 task mutation approval

## Goal

Implement and verify the fourth canonical Stitch product screen:
`Task Mutation Approval: Recent Reference (Approved)`.

The screen demonstrates the runtime-first task mutation flow where the user
first creates a task, then refers to it by relative language
`上一个待办事项`, and the app shows an auditable approval card before any
existing task title is changed.

## Confirmed Facts

- Stitch screenId:
  `0632921a825a4f1b9e91c2f66a4c97e3`.
- Manifest dimensions: mobile, width `780`, height `2938`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/13-task-mutation-approval-recent-reference-0632921a825a4f1b9e91c2f66a4c97e3.html`
  - `docs/stitch-export/secondloop-operating-system/screens/13-task-mutation-approval-recent-reference-0632921a825a4f1b9e91c2f66a4c97e3.jpg`
- Product docs define the task boundary:
  - clear new ordinary tasks may be applied automatically;
  - modifying, deleting, completing, or archiving existing tasks requires
    approval;
  - state-changing relative references must be resolved by a narrow skill,
    not by app-side natural-language parsing;
  - ambiguous or missing targets must clarify instead of creating the wrong
    approval.
- QA docs define the target behavior:
  - QA-TASK-REL-01: `上一个待办事项` must resolve to the just-created task,
    the title change must require approval, approval must change only that
    task to `提交报销`, and other tasks must remain unchanged.
  - QA-TASK-REL-02: ambiguous `Alex` task references must clarify instead of
    generating an arbitrary approval.
  - QA-TASK-REL-03: a bare action sentence that looks like an existing task
    must still create a new task when the user did not ask to modify one.
  - QA-TASK-REL-04: explicit due-date mutation approvals must show the changed
    due date and land after approval.
- Existing app code already routes `task_mutation_confirmation` approval items
  to `ApprovalPreviewCard` and submits approve/reject decisions through
  `RuntimeSecretaryAppService`.
- Existing `ApprovalPreviewCard` is currently due-date/status oriented. Screen
  04 requires a title-change-focused approval surface with target entity,
  resolver detail, proposed title diff, audit/context metadata, risk label, and
  clear "not applied until approved" state.
- User-supplied implementation contract inherited from the parent task:
  - use only `docs/stitch-export/secondloop-operating-system/` as the Stitch
    source;
  - read README, manifest, corresponding HTML/screenshot, final product shape,
    QA acceptance, and development plan before implementation;
  - implement only canonical register product screens;
  - treat retired/superseded screens as negative examples only;
  - fill real functionality/state/API wiring before visual polish;
  - perform Computer Use review at manifest dimensions before completion;
  - run fresh `pixi` verification and report exact evidence.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `0632921a825a4f1b9e91c2f66a4c97e3` | `AppShell` chat/task operating shell -> `AgentConversationPage` -> runtime approval card surfaces in `agent_conversation_page.dart`, `agent_conversation_layouts.dart`, and `ApprovalPreviewCard`; state from `RuntimeAgentState.approvalItems`, `RuntimeAgentState.recentEntityRefs`, task records, and latest context snapshot; API through `RuntimeSecretaryAppService.approveApprovalItem`, `rejectApprovalItem`, and existing approval patch/degraded edit handling. |

## Stitch-vs-Local Difference List Before Implementation

- UI differences:
  - Stitch shows an "Action Center" approval-focused view with a system
    context summary, user message, locked current task preview, large "Task
    Title Change Approval" card, low-risk badge, target entity, resolver
    detail, proposed title diff, metadata grid, explicit pending notice,
    approve/edit/reject actions, and small audit/confidence summary cards.
  - Current local task approval rendering uses a generic `ApprovalPreviewCard`
    whose diff is focused on due time and status. It does not yet have a
    title-change diff, resolver/audit metadata grid, target entity row, or
    Stitch-like action center hierarchy.
- Functionality differences:
  - Stitch's approve button transitions to processing/applied; local approve
    already submits runtime decisions but the focused screen must expose the
    busy state and refresh behavior clearly.
  - Stitch includes Edit and Reject. Local reject exists. Edit must call a real
    runtime patch path when available or show an honest unavailable/degraded
    state instead of pretending to edit.
- State-flow differences:
  - Stitch shows the existing task title `整理报销材料` locked while awaiting
    approval and the proposed title `提交报销` as not yet applied.
  - Local state must preserve the current task until approval succeeds and must
    not update the task list from app-side parsing before runtime approval.
- Data/API wiring differences:
  - Screen 04 needs `task_mutation_confirmation` approval data to include or
    derive target task id/title, proposed title, source message, resolver
    detail, context snapshot/audit id, risk label, and runtime tool.
  - If the runtime/API payload cannot provide a field, the UI must either use
    existing runtime state safely or render an explicit unavailable/degraded
    value, then identify whether a `SecondLoopServer` change is required.

## Requirements

- Implement the screen through existing Flutter architecture. Do not paste
  Stitch HTML.
- The fixture/user flow must include:
  - `帮我创建一个任务：整理报销材料。`
  - runtime-created task `整理报销材料`
  - `把上一个待办事项标题改为提交报销。`
  - task mutation approval targeting only that recently created task.
- The title change must remain pending until approved. Do not represent
  `提交报销` as the active task title before approval succeeds.
- The approval card must make the resolved target explicit, including task id
  or equivalent runtime target identity and current title.
- The approval card must show a clear title diff from `整理报销材料` to
  `提交报销`.
- The approval card must show why the target was selected, such as
  `recent_ref resolved to most recent task`, from runtime/context data or a
  clearly labeled degraded value.
- Approval metadata should include source, audit id, context snapshot, runtime
  tool, risk label, and an explicit "not applied until approved" notice when
  present in runtime data or safely derivable from it.
- Approve/reject controls must use the real runtime approval sender/service and
  refresh visible runtime state after completion.
- Edit must either patch the approval through a real runtime capability or
  visibly degrade with an honest unavailable/error state. Do not ship a fake
  edit path.
- Maintain product boundaries: runtime owns semantic target resolution, formal
  task mutation requires approval, and the app must not add local
  natural-language parsing to execute title changes.
- Match the local Stitch screenshot/HTML first viewport, approval hierarchy,
  context/task preview, metadata, actions, and bottom navigation as closely as
  possible within existing Flutter architecture.
- Do not track or edit `docs/`; the local Stitch export is a design baseline.
- If app-side runtime/API wiring is insufficient, identify whether a real
  server change is required in
  `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer` before
  claiming the screen is complete.

## Acceptance Criteria

- [ ] A screen 04 mapping table and Stitch-vs-local difference list exist
      before implementation.
- [ ] The rendered UI matches the canonical Stitch first viewport, task
      mutation approval hierarchy, target entity, resolver detail, title diff,
      metadata grid, pending notice, actions, supporting audit/confidence
      summaries, and bottom nav as closely as the app architecture allows.
- [ ] QA-TASK-REL-01 behavior is represented: `上一个待办事项` resolves to the
      just-created task, mutation requires approval, approval changes only that
      task to `提交报销`, and no other task is changed.
- [ ] The pre-approval task list/current state still shows `整理报销材料`, not
      `提交报销`.
- [ ] Approve/reject controls are wired to the runtime approval flow and expose
      busy/error state.
- [ ] Edit is backed by runtime patch behavior or visibly degraded with a clear
      unavailable state.
- [ ] The UI includes audit/context evidence from runtime state where
      available, including source, context snapshot, audit id, runtime tool,
      and resolver detail.
- [ ] A focused widget test covers the runtime-state fixture for screen 04.
- [ ] Existing task mutation approval tests continue to pass or are updated to
      the refined contract without weakening runtime-first behavior.
- [ ] Computer Use manual review is performed at manifest width after the UI
      changes.
- [ ] Relevant `pixi` checks pass with fresh evidence, including focused tests,
      analyzer/typecheck, build or documented build-equivalent gate, and
      changed-file verification.
- [ ] Completion output includes screenId, mapping, functionality filled,
      modified files, screenshot/manual verification result, known non-1:1
      differences, and commands run.

## Out of Scope

- Implementing screen 05 calendar/email approval.
- Implementing retired/superseded task mutation designs.
- Adding local natural-language parsing for `上一个待办事项`.
- Pretending that task title edit is supported if runtime patching cannot
  represent it.
- Backend deployment unless the existing app cannot represent the required
  runtime state or approval flow without a server contract change.

## Open Questions

- None currently. The screen scope and product behavior are defined by the
  canonical Stitch register, final product docs, QA-TASK-REL acceptance cases,
  and the existing parent task mapping.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
