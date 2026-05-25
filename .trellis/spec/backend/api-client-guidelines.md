# API Clients And Auth

SecondLoop's app code talks to external services through Dart HTTP clients. New
work should follow the visible client contracts in this repository and must not
document or depend on private service implementation details.

## Client Boundaries

- Put runtime profile based clients in `lib/core/cloud/`. `RuntimeApiClient`
  resolves request paths against the saved runtime manifest and injects profile
  bearer auth. `SecretaryRuntimeClient` builds feature-specific paths on top of
  that lower-level client.
- Put web shell proxy clients in `lib/web_app/`. `WebAppServiceHttp` owns
  browser-relative `/api/...` paths and bridges web-only settings adapters.
- Use injectable `http.Client` parameters for testability. Tests use
  `package:http/testing.dart` `MockClient` and assert method, URL, headers, and
  body.

Reference files:

- `lib/core/cloud/runtime_api_client.dart`
- `lib/core/cloud/secretary_runtime_client.dart`
- `lib/web_app/web_app_service.dart`
- `test/runtime_api_client_test.dart`
- `test/secretary_runtime_client_test.dart`
- `test/web_app/web_app_service_http_test.dart`

## Path Construction

- Runtime client paths are string paths such as
  `/v1/runtime/vaults/$vaultId/agent-state`; `RuntimeApiClient` resolves them
  with `Uri.parse(connection.manifest.apiBaseUrl).resolve(path)`.
- Web app paths are browser-relative `Uri(path: ...)` requests. Keep shared path
  constants near the top of `lib/web_app/web_app_service.dart`.
- Encode user-controlled path segments when the existing helper does so. For
  note and attachment clients, follow the local `Uri.encodeComponent` patterns
  before adding new untrusted segments.
- Do not add server route handler guidance in this repo; only document client
  contracts that are visible in app code and tests.

## Auth Checks

- UI code obtains cloud auth through `CloudAuthScope`, `SubscriptionScope`, and
  helper functions in `cloud_auth_access.dart` or `cloud_capability_auth.dart`.
- Background auth should use `CloudAuthAccessMode.background`; interactive
  foreground flows may use `CloudAuthAccessMode.interactive`.
- Client calls send bearer tokens as `authorization: Bearer <token>`. Web vault
  requests also include `x-secondloop-vault-id`.
- Missing tokens should fail closed. Existing examples return `401` in
  `WebFormalSettingsHttpClient` or throw `StateError('missing_id_token')` in
  billing adapters.

Reference files:

- `lib/core/cloud/cloud_auth_access.dart`
- `lib/core/cloud/cloud_capability_auth.dart`
- `lib/core/cloud/cloud_auth_scope.dart`
- `lib/web_app/web_formal_settings_adapters.dart`
- `test/agent_conversation_route_test.dart`
- `test/web_app/web_formal_settings_adapters_test.dart`

## Response Contracts

- Decode JSON into explicit Dart model classes near the client that consumes the
  endpoint.
- For list fields, accept absent or malformed arrays by returning an empty list
  only when the surrounding client already follows that pattern.
- Preserve runtime wire naming in runtime models instead of mapping authoritative
  runtime state into legacy local `Todo` or `MemoryPageRecord` models.

Avoid parsing assistant text to infer state changes. Product behavior should be
driven by machine-readable metadata and approved runtime/vault responses.

## Scenario: Self-Managed Setup Helper Authorization

### 1. Scope / Trigger

- Trigger: self-managed setup spans Flutter UI state, `SelfManagedSetupRequest`,
  local setup-helper process input, deployment runner behavior, and persisted
  runtime connection metadata.
- Treat Cloudflare management authorization as setup-helper session data, not a
  saved app/runtime business configuration.

### 2. Signatures

- Dart request owner:
  `SelfManagedSetupRequest(cloudflareAuthorizationMethod, cloudflareAccountId, cloudflareApiToken, cloudflareAccountLabel, provider, apiKey, embeddingApiKey, multimodalApiKey)`.
- Helper JSON input fields:
  `cloudflare_authorization_method`, `cloudflare_account_id`,
  `cloudflare_api_token`, `cloudflare_account_label`, `provider`, `api_key`,
  `embedding_api_key`, `multimodal_api_key`.
- Persisted output remains `CloudRuntimeConnection(profile, manifest)` plus
  runtime auth token and capability manifest id. It must not include the
  Cloudflare management token.

### 3. Contracts

- `cloudflare_authorization_method == "oauth"` means the helper owns the
  authorization handoff. If no OAuth handoff is wired, UI must show
  `tool_unavailable:cloudflare_oauth`.
- `cloudflare_authorization_method == "manual"` requires both
  `cloudflare_account_id` and `cloudflare_api_token`.
- `cloudflare_api_token` is only passed to setup-helper deployment automation.
  It is not written to `RuntimeConnectionStore`, runtime manifest JSON,
  profile metadata, logs, or user-visible setup summaries.
- Runtime BYOK/provider secrets are written by the helper to the user's own
  Cloudflare runtime secrets and should be represented in app state only as
  setup progress or capability results.

### 4. Validation & Error Matrix

- OAuth path unavailable -> `tool_unavailable:cloudflare_oauth`.
- Manual method with empty account id -> `missing_cloudflare_account_id`.
- Manual method with empty API token -> `missing_cloudflare_api_token`.
- Missing provider secret inputs during deploy -> `missing_ai_provider_config`.
- Capability verification missing a required check -> fail setup and do not save
  runtime connection.
- Runtime manifest missing required capabilities -> fail setup and do not save
  runtime connection.

### 5. Good/Base/Bad Cases

- Good: manual account id and token validate locally, helper receives token for
  deployment, verification passes, app saves only runtime profile/manifest.
- Base: OAuth button is clicked in a local build without a handoff; app renders
  a degraded unavailable state and does not reveal fake connected UI.
- Bad: app stores Cloudflare API token in preferences, secure blobs, runtime
  profile, manifest, logs, or a long-lived settings card.

### 6. Tests Required

- Controller/unit tests: OAuth unavailable state, missing manual account id,
  missing manual token, and helper-not-called when validation fails.
- Helper/deploy runner tests: manual token bypasses OAuth helper, is passed to
  deployment resources, and is absent from result manifest/profile strings.
- Widget tests: setup screen renders at narrow, manifest-width, and desktop
  sizes; manual validation errors and OAuth degraded state are visible.

### 7. Wrong vs Correct

#### Wrong

```dart
await connectionStore.saveConnection(
  connection.copyWith(authToken: cloudflareApiToken),
);
```

#### Correct

```dart
final cloudflareToken = request.usesManualCloudflareCredentials
    ? request.cloudflareApiToken.trim()
    : await cloudflareAuth.authorize(request.cloudflareAccountLabel);
await deployResources(request, cloudflareToken, plan);
// Save only runtime connection returned after deployment and verification.
```
