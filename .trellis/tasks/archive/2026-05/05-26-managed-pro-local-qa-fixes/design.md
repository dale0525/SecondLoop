# Technical Design

## Architecture And Boundaries

The app remains the only tracked-code implementation target in this repository.
Managed Pro behavior must be rendered from app-visible runtime contracts:

1. Runtime conversation send result.
2. Refreshed `RuntimeAgentState`.
3. Runtime approval items.
4. Runtime working-set records, tool traces, web research drafts, citations, and
   attachment/media records.

Flutter UI must not parse assistant prose to infer whether a task, memory,
approval, search result, media item, or safety refusal exists. When evidence is
missing, the UI should show an honest degraded state or no success label.

Private managed runtime work, if needed, is treated as a separate source of
truth that exposes only public app-visible request/response contracts back to
this repo. Tracked files in this repo must not include private paths,
repository names, logs, secrets, deployment internals, or account identifiers.

## Data Flow

### Chat Send And Render

`AgentConversationPage`
→ `ChatRuntimeConversationSender.send(...)`
→ `SecretaryRuntimeConversationResult`
→ refresh `RuntimeAgentStateRepository.fetchAgentState(...)`
→ `AgentConversationLayout`
→ typed operating cards, markdown message body, suggestions footer, evidence
footer, and context rail.

The page should keep immediate send-result metadata available while refreshed
runtime state is loading or unavailable, but should prefer refreshed runtime
state once present.

### Task And Approval State

Task creation display should use authoritative applied mutation metadata or
refreshed runtime task records. Existing-task mutations remain approval-backed:
approval cards render due/status/title diffs from `SecretaryRuntimeApprovalItem`
and its typed record fields, and only show applied state after approval decision
and refresh.

### Search Citations

Search evidence can come from assistant citations, web research drafts,
context snapshots, or tool trace metadata. The visible chat answer and footer
must be associated with the relevant assistant turn. Tool trace labels must not
say `CITATIONS: PRESENT` unless visible citation evidence is available for that
turn or state snapshot.

### Safety Refusals

Purchase/payment and local-computer safety remain separate card families. They
render from explicit runtime records or approval/state metadata, display
no-external-action/no-local-operation evidence, and provide no approve path for
the blocked side effect.

### Quick Capture

Desktop managed pro layouts should not expose a misleading floating in-app `+`
that reopens or misplaces the main window. Quick Capture must be invoked through
the existing controller/hotkey path when available; otherwise the UI should
surface an honest unavailable state. Tests should cover both the controller path
and the desktop shell visibility/behavior.

### Acceptance Harnesses And Scripts

Scenario harnesses should navigate real app shell destinations by stable keys.
The QA asset script should resolve the app repo root from the script location,
not from a parent workspace current directory.

## Compatibility And Migration

- No persistent data migration is expected.
- Existing test keys should be preserved where possible; add stable keys for new
  runtime-backed evidence surfaces and Quick Capture behavior.
- Keep generated i18n conventions in mind, but narrowly scoped legacy strings
  may remain when existing screens already use them.

## Operational Notes

- If a private managed runtime change is necessary, keep all notes out of
  tracked files except generic statements about app-visible contract changes.
- Staging deployment after private runtime push is asynchronous; rerun live
  checks only after the deployed contract is available.
- Manual QA screenshots may be collected under QA artifacts, but should not
  include credentials or private runtime internals.

## Rollback

- App-side changes can be reverted by file if a focused test shows regression.
- Private runtime changes, if any, should be rolled back in that repository and
  redeployed before repeating live checks.
