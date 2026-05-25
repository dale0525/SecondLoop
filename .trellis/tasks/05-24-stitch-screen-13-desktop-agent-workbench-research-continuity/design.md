# Stitch screen 13 desktop workbench design

## Scope

Implement the canonical Stitch screen:

- Stitch screenId: `37821c63daf74e7d96972338375758e7`
- Title: `Desktop Agent Workbench: Research Continuity Refined`
- Manifest baseline: `DESKTOP`, `2560 x 2048`
- Local HTML: `docs/stitch-export/secondloop-operating-system/html/22-desktop-agent-workbench-research-continuity-37821c63daf74e7d96972338375758e7.html`
- Local screenshot: `docs/stitch-export/secondloop-operating-system/screens/22-desktop-agent-workbench-research-continuity-37821c63daf74e7d96972338375758e7.jpg`

Do not use retired Stitch screens or the superseded/incomplete index screen
`3aa56b7a88194a37a3c38abb3ef76618`.

## Screen mapping

| Stitch screenId | Local route | Local components | State/API source |
| --- | --- | --- | --- |
| `37821c63daf74e7d96972338375758e7` | App shell Chat tab / `AgentConversationPage` at desktop breakpoint | `AgentDesktopWorkbenchLayout`, `agent_desktop_workbench_primitives.dart`, `agent_conversation_layouts.dart`, `agent_operating_research_cards.dart`, `agent_operating_approval_preview.dart`, `agent_operating_system_cards.dart` | `RuntimeAgentStateRepository.fetchAgentState`, `SecretaryRuntimeConversationSender`, send-result metadata, `RuntimeAgentState.latestContextSnapshot`, `RuntimeAgentState.approvalItems`, runtime tool trace / citations metadata |

## Stitch versus current local target

### UI differences to close

- Stitch uses a desktop operating shell: fixed top bar, left navigation, 7/5
  center/right split, dense cards, 4-8 px radius, light gray surfaces, blue
  secondary action color, and compact typography.
- The center column must keep second-turn research continuity visible: previous
  Apple launch context plus the follow-up message `介绍一下新的手机产品参数。`
- The citations block is a compact table with source handles, not a generic
  assistant paragraph.
- The right column must show three stacked panels: Runtime Context, Pending
  Approvals, and Tool Trace. These panels must align with desktop workbench
  dimensions and stay responsive below the manifest width.
- The input composer and vault search are visible controls. Search must be
  functional, disabled with a reason, or explicitly degraded.

### Functional differences to close

- Runtime context cannot be fabricated from assistant text. It must render from
  `latest_context_snapshot`, recent turns, active memory, and working-set state.
- Pending approvals must render from `RuntimeAgentState.approvalItems` or the
  send-result approval metadata and keep approve/reject/patch callbacks wired.
- Tool trace must render from runtime metadata such as skill id, postprocess
  status, current-facts policy, latency, and citation presence. If the runtime
  omits trace detail, render an honest degraded state instead of a fake success.
- Research citations must come from runtime citation fields. A current-facts
  answer without citations must not be presented as successful.

### State flow differences to close

- Desktop breakpoint should use the workbench frame only when width supports it;
  mobile and intermediate widths keep the established mobile/operating shell.
- Initial load and post-send/post-approval refresh should use the runtime state
  repository. Optimistic UI may be temporary but runtime state remains the
  authority.
- Approval decisions call the shared runtime approval path, then refresh state.
- Search and side-panel interactions either call existing app routes/actions or
  expose `tool_unavailable` / `needs_configuration` style degradation.

### Data/API wiring differences to close

- `RuntimeAgentState.latestContextSnapshot` needs enough normalized accessors
  for recent turns, context status, active memory, and tool traces.
- Existing runtime state models use raw JSON maps for flexible server metadata;
  UI projection helpers should centralize map reads rather than scattering casts
  across widgets.
- Tests should use fake runtime repository/sender data with citations, tool
  trace, context snapshot, and approval item payloads to prove the screen is
  data-backed.

## Product constraints

- SecondLoop remains a vault-first personal secretary agent, not an AIOps or
  monitoring workbench.
- App UI must not parse natural language locally to execute formal actions.
- Current facts must come from `web-research` with citations.
- Task mutation and external side effects require approval.
- Email/calendar unavailable states must degrade honestly.
- Purchase/payment/local shell/local computer operation remain refused or safely
  downgraded.

## Compatibility

- Keep existing mobile canonical screen tests green.
- Keep established runtime-first guards: no local parser, Rust, FRB, or local
  semantic job path should become part of managed pro chat.
- Prefer additions in existing agent UI primitives and projection helpers.
- Do not modify Stitch export files.

## Rollback

The change should be easy to roll back by reverting:

- Desktop workbench UI projection/helper edits.
- Focused screen 13 widget tests.
- Any i18n additions needed by new user-facing strings.

Runtime data models should remain backward compatible by tolerating absent
fields and rendering degraded states.
