# Stitch screen 09 safety purchase payment refusal design

## Scope

Implement canonical screen 09:
`Safety: Purchase Payment Refusal (Approved)`.

The screen is a mobile `AgentConversationPage` safety-refusal state backed by
runtime working-set records and conversation turns. It must show that a
purchase/payment request was refused, that no external side effect occurred,
and that only safe follow-up alternatives are available.

## Evidence Base

- Stitch export root:
  `docs/stitch-export/secondloop-operating-system/`.
- Source-of-truth entry:
  `3b8ef30093554bf2bc42e296ee36be6c`.
- Canonical register:
  `a5874f74133b435a9feb498e76a23fe4`.
- Screen 09 Stitch screenId:
  `8c87969f58254457bfb9dd85718fdd49`.
- Manifest dimensions:
  mobile, width `780`, height `2182`.
- Local Stitch HTML:
  `docs/stitch-export/secondloop-operating-system/html/18-safety-purchase-payment-refusal-8c87969f58254457bfb9dd85718fdd49.html`.
- Local Stitch screenshot:
  `docs/stitch-export/secondloop-operating-system/screens/18-safety-purchase-payment-refusal-8c87969f58254457bfb9dd85718fdd49.jpg`.
- Product boundary:
  purchase, payment, ticket booking, order placement, transfer, and signing
  requests must be refused or safely downgraded.
- QA expectation:
  the assistant does not claim to buy, book, or pay, and does not call an
  undeclared external transaction tool.

## Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `8c87969f58254457bfb9dd85718fdd49` | `AppShell` Chat tab -> `AgentConversationPage` mobile operating shell -> `_OperatingMessageList`; runtime `RuntimeAgentState.workingSetRecords` carrying an `external_side_effect_blocked` / safety record; `RuntimeConversationTurn` message content and optional `tool_trace`; no approval action and no purchase/payment tool call. |

## Stitch-vs-Local Difference List

### UI

- Stitch shows a top mode row with `Managed Pro` and
  `Blocked External Transaction`; local currently has an email-specific
  unavailable mode chip path, but no purchase/payment safety mode chip.
- Stitch assistant response uses a security-protocol header with a verified-user
  icon and refusal text; local assistant bubbles can render plain assistant text
  and web-research rich responses, but no dedicated generic safety refusal
  surface is present yet.
- Stitch includes a `Safe Alternatives` card with three real actions:
  research train options, create booking checklist, and set reminder for manual
  booking. Local has task/reminder/email/action candidate cards, but no safety
  alternatives card tied to a refused transaction.
- Stitch includes a `Transaction Safety Protocol` metadata card with skill,
  blocked action, status, audit id, source id, and tool trace. Local has
  metadata chip patterns in email and research cards, but no transaction safety
  metadata card.
- Stitch mobile spacing is dense and square-edged, with the safety card placed
  between the assistant refusal and the metadata card. The local operating
  shell should preserve existing navigation/composer structure while matching
  the Stitch card hierarchy and density as closely as the shared shell allows.

### Functionality

- Local must not add purchase, payment, booking, transfer, or external
  transaction execution actions.
- Safe alternatives must be real local/runtime-backed controls or explicit
  degraded controls:
  research can route through the existing web-research/send-message path;
  checklist creation can create or draft a local non-transaction checklist/task
  candidate only; reminder can create or draft a reminder candidate only.
- If a follow-up cannot be executed from the screen without runtime support, it
  must show an explicit unavailable/degraded result rather than silently doing
  nothing.

### State Flow

- User turn:
  `帮我直接买两张明天去上海的高铁票并付款。`
- Runtime response:
  assistant message refuses direct purchase/payment and explicitly states no
  transaction was initiated.
- Working-set record:
  a safety record with kind/status equivalent to
  `external_side_effect_blocked`, `purchase-payment-safety`, blocked action
  `ticket purchase + payment`, audit id, source message id, and tool trace.
- There must be no approval item for executing the purchase/payment, because the
  action is not approvable in this product boundary.
- Safe-alternative taps may create follow-up intents/messages/candidates, but
  none may initiate the blocked external action.

### Data/API Wiring

- Prefer existing runtime state models:
  `RuntimeAgentState`, `RuntimeWorkingSetRecord`, `RuntimeConversationTurn`, and
  `SecretaryRuntimeConversationSender`.
- Add a purchase/payment safety renderer next to the existing email degraded
  renderer rather than overloading email-specific cards.
- Record matching should use explicit safety fields first:
  `skill`, `skill_id`, `runtime_skill`, `blocked_action`, `status`,
  `source_message_id`, `assistant_turn_id`, `audit_id`, and `tool_trace`.
- Test fixtures may seed runtime state directly, but the UI must consume the
  same machine-readable fields expected from runtime.
- If the current app/runtime contract lacks a needed backend field, prefer a
  compatible optional field in the UI parser. Backend repository paths,
  deployment details, environment names, secrets, or operational instructions
  must not be persisted in tracked task artifacts.

## Component Boundaries

- Add a dedicated safety part file if the implementation grows beyond a small
  helper, for example `agent_operating_safety_cards.dart`.
- Wire it from `_OperatingMessageList` similarly to
  `_operatingEmailRuntimeCards`, using source message and assistant turn ids to
  avoid rendering unrelated working-set records.
- Reuse `AgentOperatingSystemTokens`, `_OperatingCard`,
  `_OperatingDetailRow`, and existing compact button primitives where they fit.
- Keep `agent_conversation_page.dart` below the project file-size threshold; if
  the page approaches that limit, move safety helpers into a part file rather
  than expanding the main page.

## Safety Contract

- The blocked transaction is a terminal refusal, not an approval candidate.
- The UI must include the no-side-effect state in visible copy and metadata.
- The implementation must not parse natural language locally to decide whether
  a formal action is allowed; it should render runtime-provided safety records
  and use explicit follow-up controls only for safe alternatives.
- No UI button may be a fake transaction shortcut. Every clickable control must
  either call an existing safe path or clearly surface a degraded/unavailable
  state.
- The completion report may mention whether backend work was needed, but must
  not publish backend repository paths, deployment triggers, secrets, or
  environment-specific operational details into tracked docs.

## Compatibility And Rollback

- Existing email unauthorized and web-research screens must continue to render
  through their current card paths.
- Safety record parsing should tolerate missing optional fields and fall back to
  safe labels, but must never fall back to a success/completed transaction
  state.
- Rollback is limited to the new safety renderer, its `_OperatingMessageList`
  wiring, test fixture, and any optional runtime-field parser additions.
