# AgentWeave

English | [简体中文](./README.zh-CN.md)

AgentWeave is an **Agent App Framework** for developers. It provides a reusable Agent runtime, model adapters, an extension system, security boundaries, and cross-platform hosts so that a new Agent App is defined primarily by its prompts, Skills, Connectors, policies, and product interface—not by a copied and rewritten core turn loop.

You can use it to build personal assistants, research assistants, content workflows, internal enterprise Agents, and other vertical applications. The secretary app in this repository is only a reference implementation, not the framework's fixed product form.

> [!IMPORTANT]
> The project is still in the `0.1.x` stage. Manifests, Host APIs, and Foundation Skill contracts may change before they stabilize. It is currently best suited to prototyping, framework development, and controlled integrations. Do not use it with production credentials or high-risk external operations without a security review.

## Choose a path

| Goal | Start here |
| --- | --- |
| Run the project first | Continue to the “5-minute quick start” below |
| Build your own Agent App on the framework | [Developing Agent Apps](./DEVELOPING_AGENT_APPS.md) |
| Contribute to the runtime, hosts, or Foundation Skills | [Contributing Guide](./CONTRIBUTING.md) |
| Connect a real IMAP/SMTP mailbox | [Mail Connector Setup](./MAIL_CONNECTOR_SETUP.md) |
| Integrate a managed desktop sidecar | [Local Sidecar Transport](./LOCAL_SIDECAR_TRANSPORT.md) |
| Integrate durable conversation history | [Conversation Lifecycle](./CONVERSATION_LIFECYCLE.md) |

## 5-minute quick start

### 1. Prepare the environment

You only need Git and [pixi](https://pixi.prefix.dev/latest/) installed beforehand. The project's Pixi environment manages Rust, Node.js, Python, OpenJDK, and the other command-line dependencies, so you do not need to install them system-wide.

The current `pixi.toml` declares macOS Apple Silicon, macOS Intel, and Linux x86_64 as supported platforms. Android builds additionally require a project-local Android SDK/NDK, but you can skip that when first trying the Desktop or Server hosts.

```bash
git clone https://github.com/dale0525/agentweave.git
cd agentweave

pixi install
pixi run npm --prefix apps/desktop ci
```

The second install command only writes to `apps/desktop/node_modules`. Keep generated files, caches, and local tools in ignored project directories; do not install project dependencies into the system environment.

### 2. Validate repository assets

```bash
pixi run validate-agent-assets
pixi run test-dev-script
```

These quick checks validate the App Manifest, example Apps, scaffolding and packaging scripts, and local development entry points. They do not require a model API key or an external account.

### 3. Start the minimal example

```bash
AGENTWEAVE_APP_ROOT=examples/minimal-agent pixi run dev
```

This command starts both the local Agent Server and the Desktop development page:

- Development page: <http://127.0.0.1:5173>
- Server health check: <http://127.0.0.1:49321/health>

If the health check returns `ok` and the development page loads, the local path is working. A model is not required to start the app. To have an actual conversation, enter a model URL, endpoint type, and model name compatible with the Responses, Chat Completions, or Completion protocol on the Settings page. Press `Ctrl+C` to stop both processes.

### 4. Create your own Agent App

```bash
pixi run scaffold-agent-app -- \
  --name "Research Agent" \
  --app-id com.example.research-agent \
  --output output/research-agent

pixi run scaffold-agent-app -- --validate output/research-agent
AGENTWEAVE_APP_ROOT=output/research-agent pixi run dev
```

In the generated directory, `agent-app.json` defines the application identity, compatibility, available languages, capabilities, and security policies. The `locales/` directory contains UI dictionaries, `prompts/` defines Agent behavior, and `packages/` contains app-private Skills. See [Developing Agent Apps](./DEVELOPING_AGENT_APPS.md) for complete guidance on the Manifest, i18n, themes, fonts, Skills, and release artifacts.

## How the framework fits together

```text
Custom Agent App
  agent-app.json + prompts + app packages + branding
                         |
                         v
AgentWeave Framework
  runtime + model gateway + skills + policy + storage + events
                         |
                         v
Desktop / Android / Server Hosts
  credentials + connectors + approvals + platform capabilities
```

The core design principles are:

- **Replaceable application behavior**: Personas, domain workflows, and default capabilities are defined by the App Manifest, prompts, and optional packages.
- **Stable extension contracts first**: General-purpose capabilities belong in runtime, SDK, Host Tool, or Connector contracts. Product-specific logic stays in downstream Apps.
- **Prompts are not security boundaries**: Credential access, persistent writes, networking, and external side effects must be governed by deterministic runtime and host permissions and approvals.
- **Optional Foundation Skills**: First-party foundation capabilities are packaged independently, so downstream Apps can enable, replace, disable, or omit them.
- **Default tests do not depend on external services**: Capabilities such as Mail and Memory provide fake or local backing for repeatable coverage of approvals, idempotency, and error paths.

## Repository structure

```text
apps/
  desktop/                 Electron + React host
  android/                 Kotlin Compose + Rust FFI host
crates/
  agent-runtime/           turns, sessions, tools, policy, storage, and extension lifecycle
  model-gateway/           model endpoints and streaming protocol adapters
  agent-server/            local HTTP API, development diagnostics, and background execution
  mobile-ffi/              bridge between Android and the Rust runtime
skills/                    built-in, Foundation, and developer Skills
catalog/                   machine-readable Foundation Skill and theme catalogs
examples/                  runnable Agent App reference implementations
templates/agent-app/       App scaffolding template
scripts/                   development, validation, packaging, and mobile build scripts
```

If a change only serves one domain or product, put it in `skills/`, a standalone Connector, or `examples/` first. Only protocols, state models, and security mechanisms reusable across many Agent Apps should enter the core crates.

## Extension points

### Agent Apps and prompts

`agent-app.json` is the versioned application contract shared by Desktop, Android, and Server. System prompts and developer instructions can define a persona and behavior, but they cannot grant permissions or bypass Host approvals.

### Skills

A Skill describes how to perform a class of tasks. It may include `SKILL.md`, `references/`, `scripts/`, `assets/`, and a runtime tool manifest. A Skill should not take responsibility for general OAuth, credential storage, or high-risk operation approval.

### Connectors and Host Tools

Connectors and Host Tools access mailboxes, calendars, browsers, or device capabilities deterministically and run within the framework's authentication, permission, timeout, cancellation, audit, and idempotency mechanisms. Vendor adapters can be published independently; the core runtime maintains only the contract and the secure execution boundary.

### Cross-platform hosts

Desktop, Android, and Server share the same App and Skill contracts, while each host implements its own credential storage, platform capabilities, and UI. When adding a capability, first establish which parts belong in the runtime and which must be provided by a host.

## Current capabilities and maturity

The repository currently includes a versioned Agent App Manifest, replaceable prompts, multi-turn sessions, Skill resource and release lifecycles, persistent Memory, Durable Runs, approvals, a Credential Vault, a Connector Runtime, a Scheduler, and Desktop, Android, and Server hosts.

The Foundation Catalog at [`catalog/foundation-skills.json`](./catalog/foundation-skills.json) is the single machine-readable source of capability status. The current overview is:

- Stable: Filesystem and Memory. Skill Creator is available for developers.
- Preview: Mail, Calendar, Tasks, Web Research, Documents, Contacts, Notifications, Notes, Messaging, and Scheduler.
- Reference only: `echo` and similar examples validate extension mechanisms but do not define the framework's product direction.

Preview packages are implemented and pass local package validation, but their APIs, provider and Connector coverage, and cross-platform behavior may still change. Each App's Manifest always determines which capabilities are enabled.

## Common development commands

| Command | Purpose |
| --- | --- |
| `pixi run dev` | Start the Server and Desktop development page together |
| `pixi run server` | Start only the local Server |
| `pixi run test` | Run Rust workspace tests |
| `pixi run check-skills` | Validate Skill packages in the repository |
| `pixi run test-dev-script` | Test scaffolding, packaging, and other Node scripts |
| `pixi run source-lines` | Check that code-like files stay under 1,000 lines |
| `pixi run skill-lifecycle-check` | Run the complete quality gate, including the Android build |

The complete gate requires a local Android SDK/NDK. See the [Contributing Guide](./CONTRIBUTING.md) for test selection by change scope, Android setup, and Pull Request requirements.

## Security model summary

- Apps and Skills declare requested capabilities; the Host decides what is actually granted.
- External side effects require recoverable approval and idempotency identifiers that prevent duplicate execution.
- Credentials are stored in the Host Credential Vault and never placed in prompts, Skill packages, Manifests, or Git.
- Workspace tools must stay within approved directories and must not treat application, Skill, cache, or database control directories as ordinary workspace content.
- Tests against external services must be explicitly enabled. Default tests use only fake servers or local storage.

When reporting a potential security issue, do not include real credentials, mailbox content, or personal data in example configurations, test logs, or public issues.

## Documentation

- [Contributing Guide](./CONTRIBUTING.md): environment setup, change boundaries, the test matrix, and the PR checklist.
- [Developing Agent Apps](./DEVELOPING_AGENT_APPS.md): Manifests, prompts, Skills, themes, fonts, and release artifacts.
- [Minimal Agent](./examples/minimal-agent/README.md): the smallest consumer application.
- [Secretary Agent](./examples/secretary-agent/README.md): a reference app combining Mail, Memory, and an app-private Skill.
- [Mail Connector Setup](./MAIL_CONNECTOR_SETUP.md): local IMAP/SMTP and Credential Vault configuration.
- [Repository collaboration rules](./AGENTS.md): architecture boundaries, tooling, coding, and repository-level constraints.

## Contributing

Contributions to reusable runtime capabilities, Host and Connector contracts, Foundation Skills, test fixtures, examples, and documentation are welcome. Before writing code, read the [Contributing Guide](./CONTRIBUTING.md) to decide whether your change belongs in the core, an optional package, or an example, and add failure and recovery coverage for any path involving permissions, credentials, persistence, or external side effects.

## License

Except for separately identified third-party material, AgentWeave is dual-licensed under the [Apache License 2.0](./LICENSE-APACHE) or the [MIT License](./LICENSE-MIT), at your option. See [LICENSE](./LICENSE) for the contribution terms and [NOTICE](./NOTICE) for repository-level attributions.

Third-party Skills, scripts, themes, protocols, Connectors, dependencies, and assets retain their own licenses and copyright notices. Preserve the package-local license and notice files when redistributing them.
