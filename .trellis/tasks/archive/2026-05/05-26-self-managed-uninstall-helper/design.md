# Design

## Boundaries

The self-managed runtime helper remains the local app-visible automation
boundary for Cloudflare deployment operations. This task adds uninstall behavior
beside the existing deploy behavior rather than introducing a separate runtime
or private server contract.

The app or tests provide Cloudflare authorization as session input. The helper
may pass that token to uninstall automation, but uninstall output, manifests,
profiles, logs, and summaries must not contain it.

## Contracts

Add a small uninstall request/result model to the existing self-managed setup
model area:

- Request input: Cloudflare authorization method, account label/account id,
  API token, and optional target runtime id/name when later UI wiring needs it.
- Result output: `runtime_mode`, `account_id`, removed resource ids/names, and a
  success flag.

The app-side bridge gets a `runUninstall` method beside `runSetup`. The
`SelfManagedSetupController` gets an `uninstall(...)` method that validates the
request, calls the helper, clears `RuntimeConnectionStore` only after success,
and publishes a failed state on helper errors.

Extend the helper tool with a callable uninstall function that accepts decoded
JSON input, emits progress events, and returns JSON-safe output. The existing
`main` entry remains backward compatible for deploy input; if a future caller
passes an explicit action, the helper can route to deploy or uninstall.

Add a runner in `tools/self_managed_runtime_lib/` that:

- Validates Cloudflare authorization using the existing request validation
  semantics.
- Resolves the uninstall target from the deployment account id and the shared
  self-managed resource plan.
- Emits progress for authorizing, uninstalling, and ready/finished states.
- Calls an injectable uninstall function for testability.
- Converts validation and automation failures to `LocalRuntimeHelperException`.

## Real Local QA Deployment

Because the production shared runtime artifact is not stored in this app repo,
the helper's first real Cloudflare path deploys a minimal local-QA runtime:

- Create or reuse deterministic resource names derived from the Cloudflare
  account id and optional runtime id.
- Create or reuse D1, KV, and R2 resources.
- Upload Worker scripts through the Cloudflare Workers Script Upload API.
- Bind the created D1/KV/R2 resources and write provider secrets as Worker
  secret bindings during upload.
- The primary `secretary-runtime` worker exposes `/health` and
  `/v1/runtime/model/verify-capabilities` so setup can prove the deployment
  chain and capability verification handoff are live.

This local-QA runtime is not the final production runtime/skill package. It is a
real Cloudflare resource deployment that lets QA verify account authorization,
resource creation, secret write, health checks, setup manifest persistence, and
destructive uninstall.

## Compatibility

OAuth is the preferred local-QA path when the desktop helper process can launch
the Wrangler OAuth handoff. Manual Cloudflare credentials remain supported for
tests and degraded local environments. Both authorization methods must remain
session-scoped helper input rather than persisted app business configuration.

Existing deploy helper input and output stay unchanged.

## UI

The self-managed setup screen already owns the Cloudflare credential text fields
and provider setup flow. Add the uninstall entry to the ready/manifest section
instead of adding a new settings page. The entry should:

- Render only after setup is ready or a manifest exists.
- Use a destructive-looking `OutlinedButton.icon` or equivalent Material button
  with a stable `ValueKey`.
- Open a confirmation dialog before calling the controller.
- Reuse the current session manual Cloudflare account id/token fields for
  authorization; if the fields are empty, the controller should fail with the
  same missing-field codes used by setup.
- Avoid showing or echoing Cloudflare tokens, provider secrets, or runtime auth
  tokens.

The main page file is already near the 1000-line threshold, so keep most UI
card/dialog code in `self_managed_setup_sections.dart` /
`self_managed_setup_sections_cards.dart` and pass typed callbacks from the page.

## Risks

Uninstall is destructive. The helper contract and UI confirmation must make the
operation explicit. Live Cloudflare deletion remains behind the injectable
runner seam until real provider automation replaces the placeholder.
