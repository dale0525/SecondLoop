# SecondLoop

English | [简体中文](./README.zh-CN.md)

SecondLoop is a local-first personal secretary for macOS. It is rebuilt as a thin downstream product on [AgentWeave](https://github.com/dale0525/agentweave), with a React/Electron interface and a Rust sidecar managed by the Desktop host.

The current Desktop Beta focuses on accountable work: conversations, source-backed Today items, durable tasks and reminders, approval-aware actions, inspectable memory, trusted connections, and encrypted local backup. It does not provide a cloud account, hosted model gateway, or cross-device sync.

## Product surfaces

- **Today** shows only persisted tasks, schedules, approvals, and connected Mail sources.
- **Chat** restores local conversation history and supports trusted attachment import without exposing source paths to the model.
- **Actions** keeps immutable previews, approval decisions, idempotency state, and uncertain outcomes visible.
- **Memory** exposes committed records, evidence, retention information, export, and explicit forgetting.
- **Connections** manages BYOK model readiness and the public state of Mail accounts without rendering secrets.
- **Settings** covers appearance, language, encrypted backup and restore, notifications, runtime identity, and licenses.

Fresh installations start with the model and Mail unconfigured. Deterministic fake Mail data is available only when explicitly enabled for development or tests; it is not presented as a connected user account in the packaged product.

## Architecture

```text
SecondLoop React Renderer
  product routes, local state, and user decisions
                 |
                 v
Electron Main / Preload
  trusted IPC, secure storage, file dialogs, sidecar lifecycle
                 |
                 v
Local Rust sidecar
  sessions, turns, approvals, memory, tasks, scheduler, connectors, SQLite
                 |
                 v
AgentWeave Runtime + Foundation packages
```

The Renderer never receives model API keys, mailbox passwords, the sidecar transport token, backup keys, or original attachment paths. External side effects remain subject to Runtime approval and idempotency rules.

## Prepare the development environment

Install Git and [Pixi](https://pixi.prefix.dev/latest/), then run:

```bash
pixi install
pixi run npm --prefix apps/desktop ci
pixi run validate-secondloop
```

Pixi manages the project toolchain. Keep generated tools and QA artifacts inside the ignored `.tool/` directory instead of installing project dependencies system-wide.

## Build the macOS app

```bash
pixi run package-macos-secondloop
open dist/macos/secondloop/SecondLoop-darwin-arm64/SecondLoop.app
```

The package contains the Electron host, managed Rust sidecar, locked Agent App resources, selected Foundation packages, and repository license files. Without a stable distribution signature, repeated local ad-hoc builds may trigger macOS Keychain ACL prompts. Isolated QA runs can use the mock keychain explicitly:

```bash
dist/macos/secondloop/SecondLoop-darwin-arm64/SecondLoop.app/Contents/MacOS/SecondLoop \
  --use-mock-keychain \
  --user-data-dir="$PWD/.tool/secondloop-qa-userdata"
```

The mock keychain is for local QA only. Stable signed distributions use the operating-system secure storage path.

## Quality gates

Run the product and shared framework checks through Pixi:

```bash
pixi run validate-secondloop
pixi run validate-agent-assets
pixi run test-dev-script
pixi run source-lines
pixi run npm --prefix apps/desktop test
pixi run npm --prefix apps/desktop exec tsc -- --noEmit -p apps/desktop/tsconfig.vitest.json
pixi run cargo fmt --all --check
pixi run cargo clippy --workspace --all-targets -- -D warnings
pixi run cargo test --workspace
```

Desktop visual acceptance covers `1440 × 900`, `1280 × 800`, and `390 × 844`. The route and state criteria are recorded in [SECONDLOOP_UI_DESIGN.zh-CN.md](./SECONDLOOP_UI_DESIGN.zh-CN.md); the rebuild history and upstream/downstream boundary are recorded in [AGENTWEAVE_REBUILD_PLAN.zh-CN.md](./AGENTWEAVE_REBUILD_PLAN.zh-CN.md).

## Upstream collaboration

This repository keeps two remotes:

- `origin`: the existing `dale0525/SecondLoop` repository and its repository-level integrations.
- `upstream`: `dale0525/agentweave`, the authoritative source for reusable Runtime, Host, sidecar, packaging, and Foundation capabilities.

Reusable changes are developed here on branches based on `upstream/main`, submitted as focused AgentWeave pull requests, and merged back into the product only after upstream adoption. SecondLoop-specific branding, routes, prompts, private Skills, onboarding, and product workflows remain downstream.

## Current boundaries

- macOS Desktop is the first supported product host.
- Models are BYOK and must expose a compatible Responses, Chat Completions, or Completion endpoint.
- IMAP/SMTP is the current real Mail adapter; Gmail API, Microsoft Graph, and OAuth onboarding are not included in this Beta.
- Encrypted backup uses AES-256-GCM and an operating-system protected key. The active SQLite database is not currently encrypted at rest.
- Android productization, cloud sync, legacy SecondLoop data migration, OCR, and audio workflows are outside this release.

## License

Except for separately identified third-party material, this repository is dual-licensed under [Apache License 2.0](./LICENSE-APACHE) or [MIT](./LICENSE-MIT), at your option. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE) for details.
