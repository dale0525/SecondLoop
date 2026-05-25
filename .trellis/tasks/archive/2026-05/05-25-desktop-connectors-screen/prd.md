# Restore desktop Connectors screen

## Goal

Restore the desktop Connectors workbench from Stitch screen
`e3f971e3a1a84714a33d12e7b1b1f5bf` as the desktop sidebar Connectors
destination. The screen must expose real capability/degraded states instead of
the current one-line snackbar.

## Requirements

- Local mapping: desktop sidebar `Connectors` ->
  `DesktopConnectorsWorkbenchPage`.
- Render catalogue, selected binding details, tool matrix, skill packages,
  runtime metrics, BYOK safety notice, and recent connector events.
- Show product-boundary states:
  - web-research and citation policy available only when runtime capability is
    present or conservatively marked as runtime managed.
  - email/calendar unauthorized as `needs_configuration` / draft-only /
    `tool_unavailable`.
  - media jobs as partial / budget confirmation required.
  - BYOK secrets only written to user runtime secrets, never app config.
- Run capability check should refresh runtime state/capabilities if available,
  otherwise show `tool_unavailable`.
- Connect/retry/revoke/test draft actions must not fake external connector
  success.
- Keep self-managed and managed-pro user capabilities equivalent in copy/state.

## Acceptance Criteria

- [ ] At `2560x2048`, the first viewport matches the Stitch Connectors layout:
      catalogue column, binding detail column, capability/audit column, event
      timeline.
- [ ] Selecting a connector updates detail/tool matrix.
- [ ] Email/calendar actions show explicit degraded state until configuration
      exists.
- [ ] BYOK notice and managed/self-managed parity are visible without exposing
      secrets.
- [ ] Targeted widget tests pass.

## Notes

- UI differences to close before coding: current desktop Connectors action is
  only a snackbar.
- Functional differences to close before coding: capability matrix, binding
  selection, and degraded action states are missing.
- State/API differences to close before coding: no connector-specific API model
  exists in the app, so first pass derives a conservative view model from
  runtime state/capabilities and product docs.
