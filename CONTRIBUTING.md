# Contributing to AgentWeave

English | [简体中文](./CONTRIBUTING.zh-CN.md)

Thank you for helping improve AgentWeave. This guide is for contributors changing the framework repository itself. If you only want to build your own product on the framework, start with [Developing Agent Apps](./DEVELOPING_AGENT_APPS.md).

AgentWeave is an Agent App Framework, not a finished Agent product for a fixed domain. Deciding whether a change belongs in the core is often more important than the details of its implementation.

## Decide where the change belongs

| Type of change | Preferred location |
| --- | --- |
| Session, execution, storage, or security mechanisms needed by many Agent Apps | `crates/agent-runtime/` |
| Model protocols and provider adapters | `crates/model-gateway/` |
| HTTP APIs, development diagnostics, and background workers | `crates/agent-server/` |
| Android/Rust bridge code | `crates/mobile-ffi/` |
| Desktop or Android platform interactions | `apps/desktop/`, `apps/android/` |
| Vendor-neutral, replaceable foundation workflows | A standalone Foundation Skill or Connector package |
| A product-specific persona, SOP, brand, or domain page | A downstream App or `examples/` |
| A minimal implementation that demonstrates framework composition | `examples/` or a test fixture |

Do not rely only on prompts to constrain credential access, network permissions, persistent writes, external side effects, approvals, idempotency, tenant isolation, or auditing. These require deterministic runtime, Host Tool, or Connector implementations and tests.

If a design only solves a special path in one example, first try to express it as a stable extension contract or optional package instead of adding a domain branch to the turn loop.

## Set up the development environment

### Prerequisites

- Git.
- [pixi](https://pixi.prefix.dev/latest/).
- macOS Apple Silicon, macOS Intel, or Linux x86_64—the current set of platforms declared by the Pixi workspace.
- A project-local Android SDK/NDK only when changing or validating Android.

The repository uses Pixi to pin Rust, Node.js, Python, OpenJDK, and local development tools. Do not install or upgrade these dependencies system-wide for this project.

### First-time installation

```bash
git clone https://github.com/dale0525/agentweave.git
cd agentweave

pixi install
pixi run npm --prefix apps/desktop ci
pixi run validate-agent-assets
pixi run test-dev-script
```

You can optionally install the repository's pre-commit hook:

```bash
pixi run install-hooks
```

The hook currently runs only `pixi run check-skills`. It catches Skill package problems early, but it does not replace the complete pre-submission test suite.

Keep local tools, SDKs, caches, and temporary outputs in ignored directories such as `.tool/`, `.pixi/`, `target/`, and `output/`. Do not commit credentials, databases, build outputs, or dependency directories.

## Run locally

Start the minimal example:

```bash
AGENTWEAVE_APP_ROOT=examples/minimal-agent pixi run dev
```

The development page is available at <http://127.0.0.1:5173>, and the Agent Server is available at <http://127.0.0.1:49321>. You can check it from another terminal:

```bash
curl http://127.0.0.1:49321/health
```

The development server creates a local SQLite database. You may keep it for further debugging after validation. If you are certain it is no longer needed, delete only the database created by this task and its `-shm` and `-wal` files; do not run indiscriminate cleanup commands.

## Recommended workflow

1. Read the root [AGENTS.md](./AGENTS.md) and the implementation, tests, and package manifest closest to your change.
2. Run `git status --short` to inspect the working tree and preserve all unrelated user changes.
3. Define observable behavior, security boundaries, and failure recovery before changing the implementation.
4. Add the smallest deterministic tests for new behavior. Default tests must use fake or local backing and must not depend on real accounts or network services.
5. Run the fast checks that match the change scope, then run the combined gates after fixing any failures.
6. Update the README, examples, Manifests, or contract documentation so that the docs and actual commands remain consistent.
7. Before submitting, check the diff for secrets, absolute user paths, generated files, or unrelated formatting changes.

## Coding conventions

- Use English for code, identifiers, and code comments. READMEs, prompts, and i18n files for a specific language may use that language.
- Use UTF-8 for all text files. When a change contains Chinese or other non-ASCII characters, inspect the rendered text and diff before submitting to prevent encoding damage.
- Rust uses the workspace's 2024 edition and must pass `rustfmt` and warning-free `clippy`.
- Preserve the structure and naming of adjacent files in TypeScript/React, Node scripts, Kotlin, CSS, and configuration. Avoid unrelated full-file rearrangement.
- Code-like files must stay below 1,000 physical lines. Long-form explanations, contracts, research notes, and other prose are exempt.
- New dependencies must explain why existing dependencies cannot be reused and must be managed through the project's Pixi, npm, Cargo, or Gradle configuration.
- Do not treat prompts as permission checks. Never put API keys, passwords, tokens, or real user data in source code, fixtures, logs, or documentation examples.
- External side effects require an explicit approval point, a stable idempotency key, auditable state, and failure recovery tests.
- New cross-platform capabilities must declare Host support. Platforms that cannot implement a capability must reject it explicitly or provide a documented fallback, never silently pretend to succeed.

## Test matrix

Run the checks closest to your change first, then expand the scope as appropriate.

| Change scope | Minimum recommended checks |
| --- | --- |
| Rust runtime, server, gateway, or FFI | `pixi run cargo fmt --all --check`, `pixi run cargo clippy --workspace --all-targets -- -D warnings`, `pixi run cargo test --workspace` |
| Desktop React/Electron | `pixi run npm --prefix apps/desktop test`, `pixi run npm --prefix apps/desktop exec tsc -- --noEmit -p apps/desktop/tsconfig.vitest.json` |
| Node development or packaging scripts | `pixi run test-dev-script` |
| Skill or Foundation Catalog | `pixi run check-skills`, `pixi run validate-agent-assets` |
| App Manifest, template, or example | `pixi run validate-agent-assets` and the corresponding script tests |
| Source-file splitting | `pixi run source-lines` |
| Android/Kotlin/Rust FFI | `pixi run mobile-mvp-check` |
| Cross-module or pre-release validation | `pixi run skill-lifecycle-check` |

`pixi run skill-lifecycle-check` runs Rust formatting, Clippy, Rust workspace tests, Desktop tests and type checks, Android native/unit/APK builds, and the source-line limit. It takes longer than the regular unit suite and requires a prepared Android environment.

Live tests against external services must remain opt-in. Default tests and PR reproduction steps must not require maintainers to provide a model, mailbox, or other private credentials.

### Android environment

Android tasks read the SDK from `.tool/android-sdk` by default and the NDK from `.tool/android-sdk/ndk/28.2.13676358`. You can also point `ANDROID_NDK_HOME` to a compatible NDK inside the project. The app currently uses `compileSdk 37`, `targetSdk 36`, and `minSdk 31`.

Keep the Android SDK, NDK, AVDs, and Gradle cache in the current project's `.tool/` directory or another ignored project directory. Do not commit local SDK configuration or APKs. Before running the complete gate, you can isolate failures with:

```bash
pixi run android-native
pixi run android-test
pixi run android-assemble
```

## Skill and Connector changes

When adding or changing a Skill:

- Make the frontmatter `description` state its trigger conditions clearly.
- Keep `SKILL.md` focused on the workflow and move detailed material into references that are loaded only when needed.
- Declare the package type, platforms, capabilities, and runtime tool dependencies in `agentweave.json`.
- Do not store credentials in a Skill or use scripts to bypass workspace, network, or approval policies.
- A Foundation Skill should have a vendor-neutral contract, stable tool semantics, and deterministic fake or local tests.
- Keep stability, dependencies, and replacement contracts in `catalog/foundation-skills.json` synchronized.

A Connector is responsible for authentication, networking, and access to external systems. Write operations should separate preparation or preview from side-effect execution and cover cancellation, timeout, retry, duplicate requests, and partial failure.

## Documentation changes

- Keep the root README limited to what a new developer needs to choose a path. Put the detailed App development workflow in `DEVELOPING_AGENT_APPS.md`.
- Commands must be directly executable from the repository root and state whether they require a model, credentials, an Android SDK, or network access.
- When adding a top-level concept, update the repository structure, documentation navigation, and closest example together.
- `docs/` contains ignored local work records and must never be force-added to Git. Documentation intended for distribution belongs in the root directory or the relevant package or example.
- Use obvious placeholders or opaque secret IDs for example secrets; never use values that look like real credentials.

## Commits and Pull Requests

A Pull Request should focus on one independently reviewable goal. Before committing, confirm the Git identity, diff scope, and test results:

```bash
git config user.name
git config user.email
git status --short
git diff --check
```

Repository maintainers use `Logic Tan <logictan89@gmail.com>` as the repository Git identity. External contributors may use their own verifiable identities and must not rewrite another contributor's authorship.

Unless explicitly stated otherwise, contributions intentionally submitted for inclusion in AgentWeave are licensed under both the Apache License 2.0 and the MIT License, at the recipient's option, without additional terms or conditions. Do not contribute third-party material unless its license is compatible and its required notices are preserved.

The PR description must include at least:

- The problem and goal, including why the change belongs in the core, an optional package, or an example.
- User-observable behavior and what is out of scope.
- Effects on permissions, credentials, persistence, networking, approvals, and external side effects.
- The exact test commands run and their results.
- For UI changes, the routes, Desktop and Mobile viewports, screenshot findings, and known deviations reviewed.
- Whether Manifests, data formats, or public contracts require migration and how to roll back.

## Pre-submission checklist

- [ ] The change follows the domain-neutral boundaries of an Agent App Framework.
- [ ] Tests cover the happy path, rejection paths, and relevant failure recovery.
- [ ] Default tests require no real credentials or external accounts.
- [ ] Prompts are not used as permission or security boundaries.
- [ ] Documentation, examples, Manifests, and behavior are consistent.
- [ ] Code-like files stay below the 1,000-line limit.
- [ ] The change does not commit `docs/`, `.tool/`, databases, caches, build outputs, or secrets.
- [ ] `git diff --check` and the relevant quality gates pass.

If the complete Android gate cannot run in the local environment, list the commands that were not run and explain why in the PR. Do not report “not run” checks as passing.
