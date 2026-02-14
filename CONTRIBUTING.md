# Contributing

By contributing to this repository, you agree that your contributions are licensed under the Apache License 2.0 (`LICENSE`).

## Quick start (no secrets needed)

- Install Flutter via Pixi/FVM: `pixi run setup-flutter`
- Install git hooks (auto-format + analyze on commit): `pixi run install-git-hooks`
- Run formatting:
  - Check (matches CI): `pixi run fmt-check`
  - Auto-fix: `pixi run fmt`
- Run tests:
  - Flutter: `pixi run flutter test`
  - Rust: `pixi run cargo test`
- Run the full local CI suite: `pixi run ci`

## Common development commands

- Generate Rust bridge code: `pixi run frb-generate`
- Run app locally:
  - `pixi run run-macos` (macOS only)
  - `pixi run run-linux` (Linux only)
  - `pixi run run-windows` (Windows only; default flow is package + install + launch MSI)
- Windows hot-reload/debugger flow:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_windows.ps1 -UseFlutterRun`
- Build artifacts:
  - `pixi run build-android-apk`
  - `pixi run package-windows-msi`

For arbitrary Flutter/Dart/Cargo commands:

```bash
pixi run flutter <command> [command-args]
# examples with multiple flags:
pixi run flutter test "--coverage --reporter expanded"
pixi run dart format "--output=none lib test rust_builder integration_test test_driver --set-exit-if-changed"
pixi run cargo clippy "--all-targets --all-features -- -D warnings"
```

## Platform prerequisites

- Android: Android Studio is optional. Pixi tasks provision SDK/NDK and Rust targets into `.tool/`.
- Windows (dev/build): Visual Studio 2022 + Desktop development with C++ + `C++ ATL for latest v143 build tools (x86 & x64)`.
- Windows MSI packaging: WiX Toolset v3 (`heat.exe` / `candle.exe` / `light.exe`). Scripts can install a portable WiX v3 bundle into `.tool/wix3`.
- macOS/iOS: Xcode + Command Line Tools.

## Troubleshooting

- If Windows builds reference macOS Flutter paths like `/Users/.../fvm/versions/...`, clean generated artifacts (or run `dart pub global run fvm:main flutter clean`) and then run `pixi run setup-flutter` again.
- If `pixi run setup-flutter` fails on Windows with `Filename too long` while cloning Flutter, run `git config --global core.longpaths true` once, then retry `pixi run setup-flutter`.
- If `flutter pub get` fails with TLS errors to `https://pub.dev`, try `export PUB_HOSTED_URL=https://pub.flutter-io.cn` and retry.

## Test data privacy

SecondLoop is open source. Please avoid putting real personal data (names, locations, dates tied to a real person, etc.) into test cases or fixtures. Use neutral placeholder text instead.

The repo is designed so unit tests and local builds work without any Cloud/billing configuration.

## Testing Ask AI without Cloud

Cloud sign-in / Cloud Ask AI requires private infrastructure and is optional.

To test Ask AI without Cloud, configure a BYOK profile in the app:
- Settings → LLM Profiles → add your provider key/base URL/model → activate it

## Optional Cloud config (maintainers / your own infra)

If you have access to a gateway + Firebase project, create `.env.local` via `pixi run init-env` and set:
- `SECONDLOOP_FIREBASE_WEB_API_KEY`
- `SECONDLOOP_CLOUD_ENV=staging|prod`
- `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING` / `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD`

Note: `.env.local` must NOT set `SECONDLOOP_CLOUD_GATEWAY_BASE_URL` directly (the scripts will fail fast to avoid ambiguity).

## CI note

PR CI should not require secrets (fork PRs don't have access to them). Keep Cloud/Subscription integration checks behind optional/manual workflows.

## Release (maintainers)

Release workflow: `.github/workflows/release.yml` (tag `v*`, but app release tags are validated as strict `vX.Y.Z`).

Use `pixi run release` (no positional version) to run preflight + AI bump decision + automatic tag publish. Local runs can read release env vars from `.env.local`. In local `--dry-run`, the script sets `RELEASE_LLM_INSECURE_SKIP_VERIFY=1` so LLM calls are not blocked by local TLS trust-chain issues; real release jobs on GitHub Actions still run with normal certificate verification.

Required env/secrets for release automation:
- `RELEASE_LLM_API_KEY`
- `RELEASE_LLM_MODEL`
- Optional secret: `RELEASE_LLM_BASE_URL`
- Optional local env: `RELEASE_LLM_ENDPOINT` (full endpoint override, e.g. `/chat/completions`)
- Optional local env: `RELEASE_LLM_AUTH_HEADER` / `RELEASE_LLM_AUTH_SCHEME` (custom auth header for non-standard gateways)
- Optional local env: `RELEASE_LLM_CA_BUNDLE` (CA file path when custom LLM endpoint uses private CA)
- Optional variable: `RELEASE_NOTES_LOCALES`

See `RELEASE_CHECKLIST.md` for the full checklist, including Android signing + Play/App Store readiness notes.
