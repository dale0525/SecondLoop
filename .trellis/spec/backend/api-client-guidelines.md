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
