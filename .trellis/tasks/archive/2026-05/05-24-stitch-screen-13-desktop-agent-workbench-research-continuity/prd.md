# Stitch screen 13 desktop agent workbench research continuity

## Goal

Implement and verify the thirteenth canonical Stitch product screen:
`Desktop Agent Workbench: Research Continuity Refined`.

The screen demonstrates the desktop workbench version of the agent experience:
research continuity remains visible in the main chat column while runtime
context, pending approvals, and tool trace panels make the current state
auditable.

## Confirmed Facts

- Stitch screenId:
  `37821c63daf74e7d96972338375758e7`.
- Manifest dimensions: desktop, width `2560`, height `2048`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/22-desktop-agent-workbench-research-continuity-37821c63daf74e7d96972338375758e7.html`
  - `docs/stitch-export/secondloop-operating-system/screens/22-desktop-agent-workbench-research-continuity-37821c63daf74e7d96972338375758e7.jpg`
- Stitch source shows:
  - desktop shell with operational vault search;
  - chat response continuing from previous Apple launch research context;
  - citations from `web-research`;
  - runtime context panel with previous Apple launch research and context
    snapshot status;
  - pending approval panel showing `Task Mutation Approval`;
  - tool trace panel with `web-research: executed`,
    `CITATIONS: PRESENT`, and `web-research required`.
- Existing automated coverage in
  `test/agent_conversation_stitch_first_screen_test.dart` already verifies
  desktop workbench layout frame and some runtime panel content.
- Product/QA docs require current facts to use `web-research` with citations
  and require second-turn continuity to preserve first-turn research context.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `37821c63daf74e7d96972338375758e7` | `AppShell` desktop breakpoint -> `AgentConversationPage` desktop workbench (`agent_desktop_workbench_layout.dart` / operating primitives); state from runtime conversation turns, web-research citations/tool trace, latest context snapshot, recent refs, and approval items. |

## Requirements

- Before implementation or closeout, record the Stitch-vs-local differences for
  desktop shell, chat column, right-side runtime panels, citations, pending
  approval summary, and tool trace.
- The desktop layout must use the workbench frame at desktop breakpoints and
  preserve mobile/intermediate behavior for other widths.
- Research continuity must come from runtime conversation turns and context
  snapshot state, not local copy or prompt parsing.
- Current-facts responses must expose citations and tool trace status.
- Pending approval panel must be backed by runtime approval item state.
- Search and side-panel controls must be real, disabled with reason, or
  explicitly degraded.
- Keep responsive automated coverage for desktop manifest width and key
  breakpoint widths.

## Acceptance Criteria

- [ ] Screen mapping and Stitch-vs-local difference list are recorded before
      implementation or closeout edits.
- [ ] Desktop workbench renders chat, runtime context, pending approval, and
      tool trace from runtime state.
- [ ] Web-research continuity includes citations and does not claim current
      facts without citation evidence.
- [ ] A focused widget test covers desktop manifest width `2560`, common
      desktop width, and non-workbench breakpoints.
- [ ] Computer Use manual review is performed at the manifest width.
- [ ] Fresh relevant Flutter tests, analyze/typecheck, `pixi run verify-changed`,
      and `git diff --check` are recorded before closeout.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
