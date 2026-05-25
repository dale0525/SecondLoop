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

## Scenario: Managed Pro Acceptance External Runtime Root

### 1. Scope / Trigger

- Trigger: an app-repo acceptance script needs to run commands from an external
  managed runtime checkout, reset shared test state, or collect cross-repo
  evidence.
- Keep the app repo's tracked files generic. They may name public app-visible
  contracts and local environment variable names, but not private repository
  names, local checkout paths, private logs, deployment internals, account
  identifiers, or secret values.

### 2. Signatures

- Environment key: `SECONDLOOP_SERVER_ROOT`.
- Python helper shape: `_server_root() -> Path | None`.
- Command runner shape:
  `_run_command(..., app_root: Path, server_root: Path | None, ...)`.

### 3. Contracts

- `SECONDLOOP_SERVER_ROOT` is optional for dry-runs and app-only checks.
- Server-scoped commands require `server_root` to be configured and must run
  with `cwd=server_root` only after it exists.
- The acceptance runner must not infer private checkout names from the app repo
  location. Use explicit local environment configuration instead.
- Reports may include command ids and PASS/BLOCKED/FAIL status; tracked code
  must not persist private checkout paths or secret values as defaults.

### 4. Validation & Error Matrix

- `SECONDLOOP_SERVER_ROOT` unset + server command -> `BLOCKED` with a generic
  "server root not configured" reason.
- `SECONDLOOP_SERVER_ROOT` set to a missing directory + server command ->
  `BLOCKED` with an operational path reason in the ignored local report only.
- Dry-run + missing server root -> `PASS` for planned commands, because no
  external command is executed.
- Live account env missing -> `BLOCKED`; print only missing key names, never
  values.

### 5. Good/Base/Bad Cases

- Good: run full managed-pro acceptance with `SECONDLOOP_SERVER_ROOT` injected
  by an ignored `.env.local` file or the process environment.
- Base: run `pixi run managed-pro-acceptance-dry-run` without a server root and
  verify the command/case mapping.
- Bad: default to a sibling private checkout name, commit a local absolute path,
  or write copied private runtime logs into tracked app docs.

### 6. Tests Required

- Unit-test that `_server_root()` returns `None` when the env key is absent.
- Unit-test that `_server_root()` resolves `SECONDLOOP_SERVER_ROOT` when set.
- Unit-test that missing live-account credentials are reported by key name only.
- Add a pre-commit or review grep when editing acceptance scripts for private
  checkout names, local user paths, tokens, and refresh-token fields.

### 7. Wrong vs Correct

#### Wrong

```python
def _server_root(workspace_root: Path) -> Path:
    return workspace_root / "private-runtime-checkout"
```

#### Correct

```python
def _server_root() -> Path | None:
    override = os.environ.get("SECONDLOOP_SERVER_ROOT")
    return Path(override).resolve() if override else None
```

## File Size

Follow the repository instruction in `AGENTS.md`: if a non-document source file
exceeds 1000 lines, refactor it before adding more behavior there. This rule
does not apply to plans or specs.
