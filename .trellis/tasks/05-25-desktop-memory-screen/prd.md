# Restore desktop Memory screen

## Goal

Restore the desktop Memory workbench from Stitch screen
`7abb8269cfa74ece903f4adfab237c6e` as the desktop sidebar Memory destination.
It should be a real runtime memory management surface, not the existing generic
mobile Memory page pushed in a route.

## Requirements

- Local mapping: desktop sidebar `Memory` -> `DesktopMemoryWorkbenchPage`.
- Use `RuntimeAgentState.memoryRecords` as the authoritative list of approved
  memory records.
- Derive pending memory candidates from `RuntimeAgentState.approvalItems` whose
  kind/title/record indicates memory confirmation/candidate.
- Render the Stitch structure: top header, tabs, record table, selected detail,
  pending candidates, and runtime status banner.
- Actions must be honest:
  - Pending candidate approve/reject calls the existing approval sender when an
    approval item id exists.
  - Archive, edit proposal, request removal, and add entry must show
    `approval_required` / `tool_unavailable` until a runtime mutation endpoint
    exists.
  - Refresh/search must refresh/filter local runtime state when possible, or
    show a clear degraded state.
- Include loading, empty, and fetch-error states.

## Acceptance Criteria

- [ ] At `2560x2048`, first viewport matches the Stitch Memory layout: 64px top
      nav, 256px side nav, header, table/detail split, pending-candidate block.
- [ ] User can select a memory row and see details from runtime state.
- [ ] Pending memory candidate approve/reject records a real runtime approval
      decision in tests.
- [ ] Missing runtime data shows empty/degraded UI, not fabricated records.
- [ ] Desktop Memory selection does not affect mobile bottom nav.
- [ ] Targeted widget tests pass.

## Notes

- UI differences to close before coding: existing sidebar currently pushes
  `MemoryPage`; existing Memory page uses tab bodies rather than a desktop
  records/detail workbench.
- Functional differences to close before coding: pending memory candidates and
  archive/removal actions are not represented as approval/degraded flows in the
  current desktop shell.
- State/API differences to close before coding: current desktop action is not
  wired to runtime state or approval sender.
