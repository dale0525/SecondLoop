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

Use `pixi run release` (no positional version) to run preflight + AI bump decision + automatic tag publish. Local runs can read release env vars from `.env.local`.

Required env/secrets for release automation:
- `RELEASE_LLM_API_KEY`
- `RELEASE_LLM_MODEL`
- Optional secret: `RELEASE_LLM_BASE_URL`
- Optional variable: `RELEASE_NOTES_LOCALES`

See `RELEASE_CHECKLIST.md` for the full checklist, including Android signing + Play/App Store readiness notes.
