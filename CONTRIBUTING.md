# Contributing

## Quick start (no secrets needed)

- Install Flutter via Pixi/FVM: `pixi run setup-flutter`
- Install git hooks (auto-format on commit): `pixi run install-git-hooks`
- Run formatting:
  - Check (matches CI): `pixi run fmt-check`
  - Auto-fix: `pixi run fmt`
- Run tests:
  - Flutter: `pixi run test`
  - Rust: `pixi run rust-test`
- Run the full local CI suite: `pixi run ci`

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

Release workflow: `.github/workflows/release.yml` (tag `v*`).

See `RELEASE_CHECKLIST.md` for the full checklist, including Android signing + Play/App Store readiness notes.
