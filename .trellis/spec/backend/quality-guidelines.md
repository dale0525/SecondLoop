# Core Quality Guidelines

Use project-managed commands through `pixi`. Do not require system-level tool
installs in specs or task docs.

## Verification Commands

- For current working-tree changes, start with `pixi run verify-changed`.
- Before sharing broad changes, use `pixi run ci`.
- For web-shell changes, include the focused web tests from the existing CI
  pattern: `pixi run flutter test test/web_app/web_app_gate_test.dart
  test/web_app/web_app_service_http_test.dart`.
- For HTTP clients, add focused `flutter_test` coverage with `MockClient` and
  assert URL, method, headers, body, status handling, and decoded models.

Reference files:

- `pixi.toml`
- `.github/workflows/ci.yml`
- `scripts/verify_changed.sh`
- `scripts/run_full_ci_parallel.sh`
- `test/runtime_api_client_test.dart`
- `test/web_app/web_app_service_http_test.dart`

## Product And Privacy Boundary

The product target lives in local product docs, but these Trellis specs describe
coding patterns only. Do not put private backend implementation details,
infrastructure names, secret locations, deployment internals, or private logs in
Trellis specs.

If current code has a legacy pattern that conflicts with the target product
shape, document it as a current code pattern only when it is necessary for
implementation safety. Do not present legacy behavior as the desired product
truth.

## File Size

Follow the repository instruction in `AGENTS.md`: if a non-document source file
exceeds 1000 lines, refactor it before adding more behavior there. This rule
does not apply to plans or specs.
