# Frontend Quality Guidelines

Write focused Flutter tests around the behavior being changed. Do not rely on
manual inspection when existing test seams can verify the flow.

## Widget Tests

- Use `testWidgets` for pages, dialogs, cards, and shell behavior.
- Wrap UI with the same scopes the production widget expects:
  `AppBackendScope`, `SessionScope`, `CloudAuthScope`, `SubscriptionScope`, and
  `AppPlatformCapabilityScope`.
- Use `wrapWithI18n(...)` when testing text that depends on generated
  translations.
- Set a fixed surface size for responsive shell or workbench tests and reset it
  in `addTearDown`.
- Interact through stable `ValueKey` values where available.

Reference files:

- `test/agent_conversation_test_support.dart`
- `test/agent_conversation_runtime_approval_test.dart`
- `test/app_shell_agent_tabs_test.dart`
- `test/web_app/web_app_gate_test.dart`

## Client And Service Tests

Use `MockClient` to verify HTTP method, path, headers, body, and response
handling. Avoid live network calls in unit/widget tests.

Reference files:

- `test/runtime_api_client_test.dart`
- `test/secretary_runtime_client_test.dart`
- `test/web_app/web_app_service_http_test.dart`
- `test/core/cloud/http_json_client_test.dart`

## Verification

- Run `pixi run verify-changed` before committing changed app code.
- Run targeted `pixi run flutter test <paths>` for the feature under change.
- Run `pixi run ci` before sharing broad UI or runtime-client changes.
- If a test touches preferences, initialize `SharedPreferences` with mock values.

Reference files:

- `pixi.toml`
- `scripts/verify_changed.sh`
- `scripts/run_full_ci_parallel.sh`

## Accessibility And QA Handles

Keys are not a substitute for accessible labels, but the current test strategy
depends on stable keys for repeatable QA and widget tests. Add keys to new
important actions and rendered runtime cards.
