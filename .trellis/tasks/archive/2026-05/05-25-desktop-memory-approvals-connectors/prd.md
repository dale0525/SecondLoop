# Restore desktop Memory Approvals Connectors screens

## Goal

Restore the three desktop-only navigation entries that exist in the canonical
desktop sidebar but not in the mobile bottom navigation: Memory, Approvals, and
Connectors. Each restored screen must match the new Stitch MCP desktop designs
closely while staying wired to runtime-first product behavior.

## Requirements

- Use only the canonical local Stitch export plus the three new Stitch MCP
  screens created for the missing desktop entries.
- Source screen mapping:
  - Memory: `7abb8269cfa74ece903f4adfab237c6e`, DESKTOP, `2560x2048`.
  - Approvals: `147110e76d524b1f90a2f936123aef4e`, DESKTOP, `2560x2048`.
  - Connectors: `e3f971e3a1a84714a33d12e7b1b1f5bf`, DESKTOP, `2560x2048`.
- Do not use superseded / incomplete / retired screens, including
  `3aa56b7a88194a37a3c38abb3ef76618`.
- Keep the mobile bottom navigation at the existing five product tabs.
- Route desktop sidebar Memory, Approvals, and Connectors to real desktop
  content inside the app shell instead of pushing old generic pages or showing
  placeholder snackbars.
- Consume runtime view state as the authority for memory records, approval
  items, conversation context, audit refs, and capability/degraded states.
- All visible actions must either call a real existing runtime/app path or show
  an explicit degraded state such as `needs_configuration`,
  `tool_unavailable`, `approval_required`, or draft-only.
- Keep changes focused to the desktop shell, shared desktop UI primitives, and
  screen-specific state/tests.

## Acceptance Criteria

- [ ] A Stitch screenId -> local route/component/state/API mapping exists for
      all three screens.
- [ ] Memory screen renders desktop records, details, pending memory candidates,
      empty/error/loading states, and approval/degraded actions from runtime
      state.
- [ ] Approvals screen renders queue, selected detail, diff/audit metadata, and
      calls `submitApprovalDecision` for approve/reject where allowed.
- [ ] Connectors screen renders capability catalogue, selected binding details,
      tool matrix, skill packages, BYOK notice, and honest degraded actions.
- [ ] Desktop sidebar selection state works for all eight desktop entries while
      mobile remains five tabs.
- [ ] Relevant widget tests cover navigation and action wiring.
- [ ] UI is manually reviewed with Computer Use at the implementation viewport.
- [ ] Relevant `pixi` lint/typecheck/test/build commands are run and reported.

## Notes

- Parent task owns integration scope only. Implementation is tracked in the
  child tasks for Memory, Approvals, and Connectors.
