# Contributing

By contributing to this repository, you agree that your contributions are licensed under the Apache License 2.0 (`LICENSE`).

## Quick start (no secrets needed)

- Install Flutter via Pixi/FVM: `pixi run setup-flutter`
- Install git hooks (fast pre-commit + full pre-push verification): `pixi run install-git-hooks`
- Run formatting:
  - Check (matches CI): `pixi run fmt-check`
  - Auto-fix: `pixi run fmt`
- Run tests:
  - Flutter: `pixi run i18n-refresh` once on a fresh clone, then `pixi run flutter test`
  - Rust: `pixi run cargo test`
- Run the full local CI suite (same scope as `pre-push` / CI): `pixi run ci`
- Shared verification entrypoints:
  - Check-only local gate (same non-mutating engine as CI, narrower than `verify_full`): `bash scripts/verify_changed.sh`
  - Full local/CI gate: `bash scripts/verify_full.sh`

## Common development commands

- Generate Rust bridge code: `pixi run frb-generate`
- Refresh generated i18n Dart output: `pixi run i18n-refresh`
- Check missing / outdated / unused translations: `pixi run i18n-analyze`
- Sync zh-CN translations from English source files: `pixi run i18n-translate`
- Run app locally:
  - `pixi run run-macos` (macOS only)
  - `pixi run run-linux` (Linux only)
  - `pixi run run-windows` (Windows only; default flow is Flutter hot-reload/debugger)
  - `pixi run run-windows-msi` (Windows only; package + install + launch MSI)
- Windows direct script toggles:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_windows.ps1 -UseFlutterRun` (hot-reload/debugger)
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_windows.ps1` (package + install + launch MSI)
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

## I18n workflow

- Source of truth lives in `lib/i18n/*.i18n.json`.
- `lib/i18n/strings.g.dart` is a generated local artifact. Do not edit it and do not resolve merge conflicts in it by hand.
- After changing locale source files or `slang.yaml`, run `pixi run i18n-refresh`.
- Before opening a PR, run `pixi run i18n-analyze` to catch missing, outdated, or unused translations.
- If English copy changes meaningfully and the secondary locale is not updated yet, mark it outdated first. Example:

```bash
pixi run flutter pub "run slang outdated settings.about.title"
```

- In namespace mode, use `<namespace>.<path>` when marking a translation as outdated.

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
- `HOMEBREW_TAP_TOKEN` (PAT with `contents:write` to `dale0525/SecondLoopHomebrew`)
- `WINGET_PKGS_TOKEN` (PAT that can push to your `winget-pkgs` fork and open PRs)
- Optional secret: `RELEASE_LLM_BASE_URL`
- Optional local env: `RELEASE_LLM_ENDPOINT` (full endpoint override, e.g. `/chat/completions`)
- Optional local env: `RELEASE_LLM_AUTH_HEADER` / `RELEASE_LLM_AUTH_SCHEME` (custom auth header for non-standard gateways)
- Optional local env: `RELEASE_LLM_CA_BUNDLE` (CA file path when custom LLM endpoint uses private CA)
- Optional variable: `RELEASE_NOTES_LOCALES`
- Optional variable: `WINGET_PKGS_FORK_REPO` (default: `<github.repository_owner>/winget-pkgs`)
- Optional variable: `WINGET_AUTO_AGREE_CLA` (default: `true`)
- Optional variable: `WINGET_CLA_COMPANY` (example: `Microsoft`)

Notes:
- `WINGET_PKGS_FORK_REPO` must already exist as a fork of `microsoft/winget-pkgs`.
- Official Windows releases are MSI-only; the workflow no longer publishes `Setup.exe`, Velopack metadata, or `.nupkg` artifacts.
- The Windows release contract is exact: `SecondLoop-win.msi` plus `SecondLoop-win.msi.sha256`. Downstream release steps should consume those exact paths instead of scanning `dist/` heuristically.
- If release-note generation fails in GitHub Actions, rerun the workflow manually; there is no automatic fallback notes path.
- The WinGet publication script resolves the upstream default branch via the GitHub API first and only falls back to `master` as a compatibility fallback.
- WinGet PRs can trigger a Microsoft CLA check. When `WINGET_AUTO_AGREE_CLA=true`, the release workflow polls briefly for a CLA prompt comment from `microsoft-github-policy-service[bot]` before auto-posting the reply.
- If submissions are made on behalf of a company, set `WINGET_CLA_COMPANY` so automation posts `@microsoft-github-policy-service agree company="<your-company>"` instead.
- Set `WINGET_AUTO_AGREE_CLA=false` to disable auto-commenting and handle CLA replies manually.
- Release workflow now auto-opens a WinGet PR and updates `dale0525/SecondLoopHomebrew` on each `vX.Y.Z` tag.
- WinGet manifest syntax is validated on `windows-latest` with `winget validate --manifest ...` before the external WinGet PR job runs.
- If the GitHub Release already exists and only the external WinGet publication failed, rerun only the WinGet publication job/path instead of rebuilding artifacts.
- Windows Sandbox validation is a manual or self-hosted follow-up step when installer identity or Apps & Features matching changes materially; it is not a required GitHub-hosted runner gate.

See `RELEASE_CHECKLIST.md` for the full checklist, including Windows MSI verification, release retry guidance, and Android signing + Play/App Store readiness notes.
