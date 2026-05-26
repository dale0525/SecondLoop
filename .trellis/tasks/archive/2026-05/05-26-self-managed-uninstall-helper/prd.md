# Add self-managed uninstall helper

## Goal

Add a self-managed runtime uninstall helper and connect it to the self-managed
setup UI so users and QA can remove a previously deployed personal Cloudflare
runtime through the same helper boundary used for self-managed deployment.

The helper must align with the final product shape: self-managed users own their
Cloudflare resources, provider secrets, costs, and operations; Cloudflare
management authorization is session-scoped helper input and must not be stored
as app business configuration.

## Requirements

- Provide a helper API/entry path for uninstalling a self-managed runtime.
- Provide a user-facing uninstall entry in the self-managed setup screen after a
  runtime is connected/ready.
- Require an explicit confirmation before starting uninstall from the UI.
- Clear saved self-managed runtime connection metadata only after helper
  uninstall succeeds.
- Reuse the existing self-managed helper style:
  - JSON input from the caller.
  - Structured JSON output for automation.
  - Progress events for observable steps.
  - `LocalRuntimeHelperException` error codes for actionable failures.
- Require valid Cloudflare authorization input before uninstalling:
  - Manual authorization requires `cloudflare_account_id` and
    `cloudflare_api_token`.
  - OAuth authorization may use the existing helper authorization handoff.
- Identify resources from the existing self-managed resource plan instead of
  duplicating resource names in multiple places.
- Delete or mark deleted the self-managed runtime resources created by the
  deploy helper, including runtime workers, D1/KV/R2 bindings/resources,
  agent/runtime resources, and runtime secrets.
- Wire the App-side helper bridge so local desktop QA can invoke the helper
  process from the self-managed setup UI.
- For the current repository, real deployment may use a minimal local-QA
  Cloudflare runtime artifact when the production shared runtime artifact is
  not available in this app repo. The QA artifact must expose health and model
  capability verification routes and must be clearly treated as setup-helper
  verification infrastructure, not the final production runtime.
- Return a machine-readable uninstall summary without including the
  Cloudflare management token, provider secrets, or runtime auth token.
- Preserve the existing deployment helper behavior and tests.
- Keep implementation inside app-visible helper contracts in this repository;
  do not document or hard-code private backend infrastructure details.

## Acceptance Criteria

- [x] A focused unit test proves the uninstall helper validates missing manual
      Cloudflare account id and API token before calling uninstall resources.
- [x] A focused unit test proves manual Cloudflare token is passed only to the
      uninstall runner and does not appear in the uninstall output.
- [x] A focused unit test proves uninstall progress events and structured output
      are emitted.
- [x] A controller test proves successful uninstall calls the helper and clears
      the saved runtime connection.
- [x] A widget test proves the ready self-managed setup UI exposes an uninstall
      entry, asks for confirmation, and drives the uninstall flow.
- [x] A widget or controller test proves missing Cloudflare manual credentials
      block uninstall before helper execution.
- [x] Existing self-managed deploy helper tests continue to pass.
- [x] Verification uses project-managed `pixi` commands.
- [x] App default helper process invokes `tools/self_managed_runtime_helper.dart`
      on desktop/local IO platforms and preserves unavailable behavior on
      unsupported platforms.
- [x] Cloudflare OAuth authorization can drive a real Cloudflare resource
      deployment for local QA: D1, KV, R2, Worker scripts, runtime secrets, and
      capability verification endpoint.
- [x] Cloudflare OAuth authorization can drive a real Cloudflare resource
      uninstall that deletes the local-QA resources by deterministic names.

## Notes

- Source docs inspected:
  - `docs/product/final-product-shape.md`
  - `docs/development/final-product-development-plan.md`
  - `docs/qa/self-managed-local-qa.md`
  - `.trellis/spec/backend/api-client-guidelines.md`
