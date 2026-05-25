# Restore desktop Connectors screen - Design

## Local Mapping

- Stitch screenId: `e3f971e3a1a84714a33d12e7b1b1f5bf`
- Route/component: desktop shell sidebar `Connectors` ->
  `DesktopConnectorsWorkbenchPage`
- State: runtime capabilities where available, plus
  `RuntimeAgentState.latestContextSnapshot`, `auditRefs`, `conversationTurns`
- API wiring: `RuntimeAgentStateRepository.fetchAgentState` for refresh;
  existing `SecretaryRuntimeClient.fetchRuntimeCapabilities` if a repository
  path is available later; no connector mutation endpoint in this task

## UI Model

Use a local conservative connector catalogue:

- Web Research: available, citation verified when runtime trace/capability
  contains web-research/citation data.
- Email: needs configuration, draft-only; read/summarize/send unavailable or
  approval + configuration required.
- Calendar: needs configuration, approval required for event mutation.
- Files & Media: partial, budget confirmation required.
- Model Provider: available when runtime is managed/self-managed runtime ready.
- Cloudflare Runtime: hosted runtime for managed pro, setup CTA for
  self-managed.

The selected connector drives the binding detail and tool matrix.

## Actions

- Run capability check / retry health check: refresh runtime state and show a
  status message.
- Connect Email / Configure: route to Settings if possible or show
  `needs_configuration`.
- Test draft generation: show draft-only degraded state.
- Revoke access: disabled/degraded unless a real revocation endpoint exists.

## Edge Cases

- No runtime connection: show `tool_unavailable` status while still explaining
  safe setup requirements.
- No capability metadata: conservative degraded catalogue remains visible.
