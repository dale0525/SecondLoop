# Fix Managed Pro local QA failures

## Goal

Repair the Managed Pro acceptance failures recorded in
`docs/qa/managed-pro-local-qa.md` so the app can pass automated prechecks and
produce reliable manual QA evidence for runtime-first chat, tasks, approvals,
search citations, Quick Capture, and safety refusal flows.

## Confirmed Facts

- The current task is complex because it spans Flutter UI, runtime client
  projections, acceptance harnesses, scripts, and live/manual QA.
- The app repository is on `main` with a clean working tree at task creation.
- The latest QA retry shows MP-SETUP-01 passing after clean reset and managed
  pro login, while chat/task/search/Quick Capture/safety flows still fail.
- App-side automated failures include:
  - `app_runtime_first_semantics`: missing desktop context rail, markdown body,
    suggestion footer, evidence footer, and rich markdown widgets.
  - `app_cloud_runtime_scenarios`: settings-tab harness timeout.
  - `managed-pro-agent-ui-acceptance`: unable to locate the `Fields` affordance.
  - `managed_pro_acceptance.py`: QA media assets falsely reported missing when
    the command runs from the parent workspace.
- Manual retry failures include task cards saying `Applied` while Tasks does not
  show the created task, incomplete approval diff/audit metadata, stale chat
  rendering after restart/resize, missing visible search answers/citations,
  visible in-app `+` that does not match Quick Capture design, inactive default
  global Quick Capture shortcut, and missing visible safety refusal states.
- Private managed runtime repository details, paths, logs, secrets, account
  identifiers, and deployment internals must not be written to tracked files in
  this repository. Tracked files may describe only the public app-visible
  request/response contract and generic private-runtime coordination.

## Requirements

- Preserve Managed Pro as runtime-first:
  - Do not add Cloudflare/BYOK/self-managed setup requirements to managed pro.
  - Do not reintroduce local semantic parsing, local OCR/Whisper, local
    embeddings, Rust/FRB runtime, or local task/memory mutation authority for
    managed pro flows.
- Restore deterministic app-side acceptance:
  - Desktop and integration harnesses can reliably open Settings and other tabs.
  - Agent conversation renders the desktop workbench context rail at desktop
    sizes, assistant markdown, suggestions, evidence footer, rich markdown, and
    runtime-backed action cards.
  - UI acceptance can reach media `Fields`, Review, Memory, Settings, and
    redacted managed pro account evidence.
  - QA asset checks resolve assets from the app repository regardless of the
    parent workspace current directory.
- Fix runtime-backed user-visible states:
  - Task creation cards must only show applied state when formal runtime state
    confirms the task exists or the send result provides authoritative applied
    mutation metadata.
  - Task mutation approvals must show the relevant diff, source/risk/audit
    metadata when available, and must not claim mutation application before
    approval is complete.
  - Search answers with citations must render visible assistant content and
    citation/evidence UI; trace labels must fail closed when evidence is absent.
  - Safety refusal requests must render visible refusal/no-side-effect state
    cards or messages for purchase/payment and local-computer operations.
  - Quick Capture must not expose a misleading in-app floating `+` in desktop
    managed pro workbench layouts; the intended entry path must either work or
    degrade visibly and honestly.
- Continue manual QA after fixes using the managed pro test account available
  in local environment configuration.
- If app-side evidence proves that a server-side contract fix is required, make
  the change in the private managed runtime repository, push its `main` branch,
  wait for staging to become available, then rerun the relevant acceptance
  checks. Do not disclose private repository details in tracked app files.

## Acceptance Criteria

- [ ] `pixi run managed-pro-acceptance-dry-run` passes.
- [ ] `pixi run cloud-runtime-automation-test` passes.
- [ ] `pixi run cloud-runtime-scenarios-test` passes.
- [ ] `pixi run flutter test test/no_rust_dependency_for_runtime_client_test.dart`
      passes.
- [ ] `pixi run managed-pro-agent-ui-acceptance` passes when the required
      managed pro test-account environment variables are available.
- [ ] `pixi run managed-pro-acceptance` no longer fails because of app-side
      runtime-first semantics, scenario harness, UI evidence, or false QA asset
      path errors.
- [ ] Live managed pro chat/task/search checks are rerun when credentials and
      staging are available; any remaining external/provider dependency is
      reported as `live QA pending`, not `pass`.
- [ ] Manual smoke QA reruns at least the previously failed core cases:
      MP-UI-01, MP-CHAT-01, MP-CHAT-02, MP-CAPTURE-01, MP-TASK-01,
      MP-TASK-02 prerequisite path, MP-REM-01, MP-SEARCH-01, MP-SAFE-01, and
      MP-SAFE-02.
- [ ] No tracked file added or changed by this task contains private managed
      runtime repository names, paths, secrets, account credentials, private
      logs, or deployment internals.

## Out Of Scope

- Redesigning the whole Agent workbench beyond the failures needed for this QA
  pass.
- Adding new provider capabilities beyond the existing Managed Pro runtime
  contract.
- Publishing private managed runtime implementation details in app docs,
  Trellis specs, or QA reports.

## Open Questions

- Resolved: proceed app-first, and modify the private managed runtime only when
  app-side evidence proves an app-visible contract mismatch.
