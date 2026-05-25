# Restore desktop Memory Approvals Connectors screens - Design

## Architecture

The app shell already has five canonical `AppTab` entries for mobile and
desktop, plus three desktop-only sidebar actions. Replace those desktop-only
actions with stateful desktop destinations inside `_AppShellDesktopWorkbench`.

Do not add the three entries to `AppTab`; that would leak them into mobile
bottom navigation. Instead add a desktop destination enum/state that can select:

- Existing tabs: Briefing, Chat, Vault, Tasks, Settings.
- Desktop screens: Memory, Approvals, Connectors.

The selected desktop screen should occupy the same content slot as the existing
tab `IndexedStack` and inherit the same top nav/sidebar shell.

## Data Flow

All three screens use the managed-pro runtime view state where available:

- `RuntimeAgentState.memoryRecords`
- `RuntimeAgentState.approvalItems`
- `RuntimeAgentState.recentEntityRefs`
- `RuntimeAgentState.latestContextSnapshot`
- `RuntimeAgentState.auditRefs`
- `RuntimeAgentState.conversationTurns`

For action wiring:

- Approval decisions use `ChatRuntimeApprovalSender.submitApprovalDecision`.
- Refresh/capability actions trigger an actual runtime state refresh when the
  screen has a repository, otherwise show explicit `tool_unavailable`.
- Connector configuration actions route to Settings or show
  `needs_configuration`; they must not pretend OAuth or secrets were saved.
- Memory archive/edit/removal actions show approval/degraded state until a
  runtime mutation endpoint exists.

## Component Boundaries

Create desktop screen widgets under `lib/features/agent_ui/` so they can share
the existing desktop tokens and test harness without growing
`agent_conversation_page.dart`.

Expected local mapping:

- `Memory` sidebar destination -> `DesktopMemoryWorkbenchPage`.
- `Approvals` sidebar destination -> `DesktopApprovalsWorkbenchPage`.
- `Connectors` sidebar destination -> `DesktopConnectorsWorkbenchPage`.

Shared tokens/components should live in a small desktop support file if they are
needed by more than one screen. Avoid copying Stitch HTML directly.

## Compatibility

The existing `MemoryPage` and `ReviewPage` remain available for non-desktop or
legacy direct routes. The desktop sidebar no longer pushes those pages.

No server changes are planned. If runtime state lacks connector capability
metadata, derive conservative displayed states from product docs and current
runtime availability: web research/model/runtime available, email/calendar
needs configuration, media partial/budget required.

## Rollback

Rollback is contained to the new desktop destination state, new widgets, and
their tests. Restoring the old actions should leave mobile tabs unaffected.
