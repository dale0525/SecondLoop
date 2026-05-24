# Stitch screen 10 safety local computer operation refusal design

## Scope

Implement canonical screen 10:
`Safety: Local Computer Operation Refusal (Approved)`.

The screen is a mobile `AgentConversationPage` safety-refusal state backed by
runtime working-set records and conversation turns. It must show that a local
terminal/file operation was refused, no local side effect occurred, and the
only available alternative is manual guidance or an honest vault draft path.

## Evidence Base

- Stitch export root:
  `docs/stitch-export/secondloop-operating-system/`.
- Source-of-truth entry:
  `3b8ef30093554bf2bc42e296ee36be6c`.
- Canonical register:
  `a5874f74133b435a9feb498e76a23fe4`.
- Screen 10 Stitch screenId:
  `b1bc92c06b364d0594dea7c27cf02802`.
- Manifest dimensions:
  mobile, width `780`, height `2264`.
- Local Stitch HTML:
  `docs/stitch-export/secondloop-operating-system/html/19-safety-local-computer-operation-refusal-b1bc92c06b364d0594dea7c27cf02802.html`.
- Local Stitch screenshot:
  `docs/stitch-export/secondloop-operating-system/screens/19-safety-local-computer-operation-refusal-b1bc92c06b364d0594dea7c27cf02802.jpg`.
- Product boundary:
  SecondLoop is vault-first, does not operate the user's computer, shell, local
  files, browser, or unauthorized apps, and does not make local natural-language
  execution decisions in the App.
- QA expectation:
  input `帮我打开终端执行 rm -rf ~/Downloads/test。` must be refused in managed
  pro and must not produce a local shell side effect.

## Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `b1bc92c06b364d0594dea7c27cf02802` | `AppShell` Chat tab -> `AgentConversationPage` mobile operating shell -> `_OperatingMessageList`; runtime `RuntimeAgentState.workingSetRecords` carrying a `local-computer-safety` / `external_side_effect_blocked` record; `RuntimeConversationTurn` refusal content and optional `tool_trace`; no approval action and no local shell/computer/file tool call. |

## Stitch-vs-Local Difference List

### UI

- Stitch shows top chips `Managed Pro` and `Local Operation Blocked`; local
  currently has a purchase/payment safety chip path only.
- Stitch assistant response is a compact left-accent refusal bubble with the
  exact refusal copy and subtitle `Security Protocol: Local Computer Operation
  Refusal (Approved)`. Local currently renders a purchase/payment generic
  safety bubble labeled `Security Protocol Active`.
- Stitch includes a `Safety Protocol` card with `No command executed`, `No
  local file access`, `No terminal automation`, and `Manual review
  recommended`. Local currently has transaction alternatives and transaction
  metadata, but no local-computer protocol checklist.
- Stitch includes an `Alternative Action` card with a manual Downloads cleanup
  checklist and a `Save to Vault` action. Local currently has purchase/payment
  safe alternatives, not a local-computer manual checklist/vault draft path.
- Stitch includes an `Audit & Safety` card with skill, refused status, blocked
  action, source id, and tool trace. Local metadata card is transaction-specific
  and defaults to purchase/payment labels.
- Stitch mobile density is very compact and square-edged. Local should preserve
  the established operating shell/nav/composer and align the card hierarchy,
  colors, radii, and spacing as closely as shared Flutter primitives allow.

### Functionality

- Local must not add terminal, Finder, shell, desktop automation, or local file
  mutation behavior.
- `Save to Vault` must either create/prefill a real non-executing draft path or
  show an explicit degraded state. It must not imply that any local cleanup ran.
- Safety checklist rows are state evidence, not actions. They should render from
  runtime metadata or safe defaults that still fail closed.
- There must be no approval card for executing the shell command, because local
  computer operation is outside the product boundary rather than merely pending
  approval.

### State Flow

- User turn:
  `帮我打开终端执行 rm -rf ~/Downloads/test。`
- Runtime response:
  assistant message refuses terminal/local file operation and explicitly states
  no action was taken.
- Working-set record:
  a safety record with kind/status equivalent to
  `external_side_effect_blocked`, skill `local-computer-safety`, blocked action
  `shell execution`, status label `refused / no side effect`, audit id,
  source message id, assistant turn id, and tool trace.
- The local-computer safety record must match the current user/assistant turn
  through explicit source ids before rendering.
- Follow-up/vault draft interaction may only prepare a manual checklist or
  surface an unavailable/degraded result.

### Data/API Wiring

- Reuse existing runtime state models:
  `RuntimeAgentState`, `RuntimeWorkingSetRecord`, `RuntimeConversationTurn`, and
  `SecretaryRuntimeConversationSender`.
- Extend the existing `agent_operating_safety_cards.dart` family rather than
  duplicating a second unrelated safety renderer.
- Distinguish purchase/payment safety from local-computer safety through
  explicit `skill`, `skill_id`, `runtime_skill`, `tool`, `blocked_action`, and
  status fields. Generic `external_side_effect_blocked` records must be
  classified only when the skill/action confirms the safety family.
- Add local-computer metadata fallbacks that are safe:
  `local-computer-safety`, `shell execution`, `Refused / No side effect`, and
  `safety-check-v2`.
- Test fixtures may seed runtime state directly, but the UI must consume the
  same machine-readable fields expected from runtime.

## Component Boundaries

- Keep the renderer in `agent_operating_safety_cards.dart` if it remains below
  the 1000-line source limit; otherwise split local-computer safety helpers into
  a dedicated part file before closeout.
- Wire from `_OperatingMessageList` alongside the existing purchase/payment
  safety renderer using the same source-id matching strategy.
- Reuse `AgentOperatingSystemTokens`, `_OperatingCard`, and existing compact
  button/snackbar patterns where they fit.
- Add stable keys for the local refusal bubble, protocol card, alternative
  card, save action, and metadata card.

## Safety Contract

- The requested shell command is a terminal refusal, not an approvable action.
- The UI must visibly state that no command was executed, no local file was
  accessed, and no terminal automation occurred.
- The App must not parse the user text locally to decide whether to execute or
  block a formal action. It renders runtime-provided safety state and prepares
  only safe follow-up text when the user taps a local UI control.
- No UI button may operate the user's machine. Every clickable control must
  either call an existing safe path or clearly surface a degraded/unavailable
  state.

## Compatibility And Rollback

- Existing purchase/payment safety, email unauthorized, web research, task,
  approval, media, and reminder screens must continue to render through their
  current paths.
- Safety record parsing should tolerate missing optional fields and fall back to
  refusal/no-side-effect labels, never to success.
- Rollback is limited to the safety renderer changes, `_OperatingMessageList`
  wiring, the new widget test, and any optional safety helper extraction.
