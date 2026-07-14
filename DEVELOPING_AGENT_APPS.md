# Developing Agent Apps

English | [简体中文](./DEVELOPING_AGENT_APPS.zh-CN.md)

AgentWeave follows a “framework + App definition + optional extension packages” development model. A downstream product should derive its differences primarily from `agent-app.json`, prompts, Skills, Connectors, and a branded interface—not from changes to the turn loop in `crates/agent-runtime`.

This guide is for developers building downstream applications with AgentWeave. If you have not run the repository yet, complete the [README quick start](./README.md#5-minute-quick-start) first. If you plan to change the framework, hosts, or Foundation packages, also read the [Contributing Guide](./CONTRIBUTING.md). Run every command below from the AgentWeave repository root.

Choose a starting point before you begin:

- `templates/agent-app`: the minimal scaffold template, with permissions denied by default.
- `examples/minimal-agent`: the smallest consumer application, enabling only Filesystem.
- `examples/secretary-agent`: a cross-platform reference app combining Mail, Memory, and an app-private Skill.

## 1. Create an application

Run from the repository root:

```bash
pixi run scaffold-agent-app -- \
  --name "My Agent" \
  --app-id com.example.my-agent \
  --output output/my-agent
```

The scaffold creates:

```text
output/my-agent/
  agent-app.json
  prompts/system.md
  prompts/developer.md
  locales/en.json
  locales/zh-CN.json
  themes/
  fonts/
  packages/
```

The template denies network access and background execution by default. It does not generate credential files or enable Owner Skill management. Start with the minimum permissions, then add capability, runtime tool, and Connector declarations only as required by actual package dependencies.

## 2. Define App behavior

`agent-app.json` is the versioned application contract shared across Desktop, Android, and Server. It defines:

- App and package identities, versions, and supported platforms;
- Runtime compatibility ranges;
- Enabled Skill packages;
- Required capabilities, runtime tools, and Connectors;
- Policies for external side effects, networking, background execution, Memory, and Skill management;
- Brand information, packageable languages, theme and font directories, and system/developer instruction resources.

A system prompt can define the product persona and domain behavior, but it cannot grant permissions. Operations such as sending mail, changing a calendar, or persisting sensitive Memory remain subject to deterministic Runtime, Host, and Connector policies.

After making changes, run:

```bash
pixi run scaffold-agent-app -- --validate output/my-agent
```

Validation rejects future schemas, unknown fields, path escapes, symbolic links, missing packages, platform incompatibilities, undeclared dependencies, and secrets embedded in the Manifest.

### 2.1 Discover trusted Host features

After an App Manifest has been loaded and validated against the active Runtime inventory, `ResolvedAgentApp::host_discovery()` returns a versioned, serializable snapshot for Host feature decisions. The snapshot contains the trusted App identity and public branding, the effective platform and Runtime version, the Manifest content hash, declared `features`, validated package/capability/runtime-tool/Connector requirements, and App policies.

Hosts use this snapshot to decide whether optional surfaces such as Memory, accounts, approvals, or Skill management should be reachable. Until discovery succeeds, a Host must fail closed and expose only its minimum safe surface. Unknown feature identifiers remain in the snapshot for forward compatibility, but a Host ignores identifiers it does not understand.

Discovery is not a permission grant. The `features` array can describe product behavior and presentation, while capabilities, policies, Actor grants, and Runtime state remain the authority for access and external side effects. A Host must not infer permissions from Prompt text, package directory names, branding, or an unverified Renderer configuration.

The discovery wire contract has its own schema version so Hosts can reject incompatible future snapshots without weakening Runtime compatibility checks. The Manifest hash lets a Host verify that presentation decisions and the active App instructions came from the same resolved package.

### 2.2 Bootstrap the Desktop Renderer

When `AGENTWEAVE_APP_ROOT` resolves successfully, the local sidecar retains the discovery snapshot alongside the matching App prompt and serves it from `GET /host/bootstrap`. The sidecar rejects a discovery snapshot whose identity or capability set does not match the active prompt. If no App is configured, the endpoint returns `404` instead of synthesizing product capabilities.

Electron Main requests this fixed API path through its private authenticated sidecar transport, accepts calls only from the main Renderer window, limits the response size, and validates the complete discovery wire contract before returning it through `window.agentWeave.hostBootstrap.load()`. The Preload bridge does not expose a Manifest path, endpoint, transport credential, configurable headers, or direct file access. Host discovery and local transport authentication remain separate checks; neither one replaces the other.

The Desktop Renderer always keeps Chat and Settings reachable. It opens optional surfaces only when all relevant declarations agree:

- Memory requires `memory-management`, `memory-provider`, and a `memoryPersistence` policy other than `disabled`.
- Mail accounts require `mail-workflows`, `mail-connector`, and at least one declared Connector.
- Pending actions require `action-center`, `durable-actions`, `approval-engine`, and an external-side-effect policy other than `deny`.
- Owner Skills and Developer Tools require an App `skillManagement` policy other than `disabled`, in addition to their existing authenticated Host policy or development API checks.

Loading, malformed, unsupported, unavailable, and non-Desktop bootstrap results all fail closed. Direct navigation to a closed route returns to Settings without briefly rendering the restricted surface. The Renderer may show a retry action, but it must not cache a failed or stale discovery snapshot as authority.

### 2.3 Choose themes and fonts

The Desktop Host reads the optional `appearance` configuration from `agent-app.json`. `themes.builtins` determines which built-in themes are visible in the final App, while `defaultTheme` determines the theme used on first launch. New scaffolds include the same 19 color themes as the current VS Code 1.128 release and use `vscode.dark-2026` by default.

To keep only the default dark and light themes, use:

```json
{
  "appearance": {
    "defaultTheme": "vscode.dark-2026",
    "themes": {
      "builtins": [
        "vscode.dark-2026",
        "vscode.light-2026"
      ],
      "custom": []
    }
  }
}
```

Place custom themes in the App root's `themes/` directory. Theme files use the VS Code color theme JSON or JSONC format and may inherit another theme in the same directory through `include`. Then declare a stable ID, optional display label, and relative path in `themes.custom`:

```json
{
  "id": "com.example.brand-dark",
  "label": "Brand Dark",
  "path": "themes/brand-dark-color-theme.jsonc"
}
```

Desktop builds map VS Code workbench colors to chat, settings, form, border, and status colors. Syntax token colors may remain in the theme file, but they do not change syntax highlighting in the chat body.

Place fonts in the App root's `fonts/` directory; they do not need Manifest entries. Filenames determine their role: `ui.woff2` is used for interface text, `display.woff2` for headings, and `mono.woff2` for code. You can add weight and italic suffixes, such as `ui-600.woff2` or `ui-400-italic.woff2`. Desktop supports WOFF2, WOFF, TTF, and OTF, preferring WOFF2. Android loads TTF and OTF through the platform `Typeface` and safely falls back to the system font for WOFF or WOFF2.

Use the same App root for local development and production builds:

```bash
AGENTWEAVE_APP_ROOT=output/my-agent pixi run dev
AGENTWEAVE_APP_ROOT=output/my-agent pixi run npm --prefix apps/desktop run build
```

Themes and fonts contribute to the App content hash. Regenerate and validate release artifacts after changing any related file.

### 2.4 Manage interface languages

`localization` declares the interface languages an App can provide, the default language, and the corresponding UTF-8 JSON dictionaries. Dictionaries use stable flat keys so they are easy to review, merge, and process with translation tools:

```json
{
  "localization": {
    "defaultLocale": "en",
    "locales": [
      {
        "id": "en",
        "label": "English",
        "resource": "locales/en.json"
      },
      {
        "id": "zh-CN",
        "label": "简体中文",
        "resource": "locales/zh-CN.json"
      }
    ]
  }
}
```

Every dictionary must contain the same keys and preserve the same `{placeholder}` values. The Host includes base English and Simplified Chinese copy. App dictionaries may override keys such as `app.name` and `app.tagline`; Host copy that is not overridden falls back first to the matching language and then to English. At runtime, users only see languages declared by the final release package, and their selection is persisted.

`pixi run scaffold-agent-app -- --validate <app>` also checks locale IDs, resource paths, JSON encoding, key alignment, and placeholder alignment. To add a language, copy the default dictionary, translate each entry, and run validation. Do not add hard-coded user-facing copy to components.

## 3. Add a custom Skill

Place app-private Skills in `packages/<skill-name>/`. Every package must contain at least:

```text
packages/my-workflow/
  agentweave.json
  SKILL.md
  agents/openai.yaml
```

An instruction Skill may add `references/`, `scripts/`, and `assets/` as needed. Resource reads are bound to the package revision captured for the current turn; path escapes, symbolic links, and out-of-bounds sizes are rejected. Scripts must run through a controlled helper or sandbox and must not use Skill instructions to bypass Host permissions.

When creating or updating a Skill, follow Skill Creator's progressive-disclosure principles: put trigger conditions in the frontmatter `description`, keep `SKILL.md` concise, and move detailed material to references that are read only when needed. Validate app-private Skills with the runtime package validator:

```bash
pixi run cargo run -p agent-server --bin check-skills -- \
  --root output/my-agent/packages
```

Then enable the package in `agent-app.json` under `requires.packages` and fully declare its required capabilities, runtime tools, and Connectors.

## 4. Choose Foundation Skills

The machine-readable catalog is located at `catalog/foundation-skills.json`. Every Foundation Skill is an optional package that can be disabled or replaced.

- Stable foundation: Memory and the existing Filesystem foundation capability.
- Preview foundation: Mail, Calendar, Tasks, Web Research, Documents, Contacts, Notifications, Notes, Messaging, and Scheduler.
- Developer-only: authoring tools such as Skill Creator, which are not automatically included in consumer Apps.

Mail defines general mail workflows, while account access is provided by Fake, IMAP/SMTP, or future vendor adapters. Memory provides auditable Agent context; Notes contains content explicitly owned by the user, and the two must not be conflated. Tasks store work state, Scheduler triggers work, and Notifications deliver results.

## 5. Run locally

Server:

```bash
AGENTWEAVE_APP_ROOT=output/my-agent pixi run server
```

Desktop development mode:

```bash
AGENTWEAVE_APP_ROOT=output/my-agent pixi run dev
```

Android packages `examples/secretary-agent` by default and writes a frozen App lock and Skill bundle lock. To use a different Android reference App, change the build-time App input instead of adding domain branches to the Runtime.

## 6. Test with fake implementations

Default tests must not depend on external accounts. Mail, Memory, Calendar, Tasks, Web Research, Documents, Contacts, Notes, and Messaging all provide deterministic fake or local backing for coverage of pagination, conflicts, approvals, idempotency, isolation, and error paths.

The Secretary reference app lives in `examples/secretary-agent`. It uses local Fake Mail and SQLite Memory to validate the combined path of remembering preferences, reading mail, creating a draft, obtaining approval, and sending exactly once.

## 7. Generate frozen release artifacts

Development mode may read mutable source directories. Release mode should use frozen artifacts:

```bash
pixi run package-agent-app -- \
  --input output/my-agent \
  --output output/my-agent-release \
  --runtime-version 0.1.0 \
  --locales en,zh-CN \
  --default-locale en
```

`--locales` selects the languages from the Manifest dictionaries that will actually ship in this release. Unselected dictionaries are not copied into the release. If the original default language is excluded, the packager uses the first language in the list, or you can choose one explicitly with `--default-locale`. The source directory is not rewritten.

Android packaging follows the same selection rules. When building a downstream App, set `AGENTWEAVE_APP_ROOT` and optionally use `AGENTWEAVE_APP_LOCALES` and `AGENTWEAVE_APP_DEFAULT_LOCALE` to specify the APK's language set:

```bash
AGENTWEAVE_APP_ROOT=output/my-agent \
AGENTWEAVE_APP_LOCALES=en,zh-CN \
AGENTWEAVE_APP_DEFAULT_LOCALE=en \
pixi run android-assemble
```

The release artifact contains:

```text
output/my-agent-release/
  agent-app.lock.json
  app/
  packages/
```

The lock pins the App identity, Runtime version, platform, language set, package versions and SHA-256 hashes, capabilities, runtime tools, and host-provided Connector or provider requirements. Artifacts do not record absolute local source paths and reject `.env` files, private keys, and credential or secret JSON files.

Validate again before publishing or launching:

```bash
pixi run package-agent-app -- --verify output/my-agent-release
```

Any tampering with a prompt, Skill, or lock causes verification to fail.

## 8. Minimum quality gate

```bash
pixi run cargo fmt --all --check
pixi run cargo clippy --workspace --all-targets -- -D warnings
pixi run cargo test --workspace
pixi run check-skills
pixi run test-dev-script
pixi run npm --prefix apps/desktop test
pixi run npm --prefix apps/desktop exec tsc -- --noEmit -p apps/desktop/tsconfig.vitest.json
pixi run mobile-mvp-check
pixi run source-lines
```

Live tests against external services must remain opt-in. The default gates use only local fake servers and credential-free tests.

## 9. Troubleshooting

### The Desktop page reports missing dependencies

Install the Desktop dependencies again after the first checkout or whenever `package-lock.json` changes:

```bash
pixi run npm --prefix apps/desktop ci
```

### The Server cannot bind to its port

The local Server listens on `127.0.0.1:49321`, and the Desktop development page uses `127.0.0.1:5173`. Stop the old development process occupying the port, then run `pixi run dev` again.

### The page opens, but messages cannot be sent

The startup path does not require a model, but conversations need a reachable model endpoint. Check the Base URL, endpoint type, and model name on the Settings page, then run the connection test. Responses, Chat Completions, and Completion are different protocols; the endpoint type must match the protocol actually supported by the service.

### Manifest validation fails

Start with the first error. The validator rejects unknown fields, future schemas, path escapes, symbolic links, missing packages, platform incompatibilities, undeclared dependencies, and secrets. Do not weaken validation to bypass the application contract; correct the Manifest or package declarations instead.

### The Android build cannot find the SDK or NDK

Android tasks use `.tool/android-sdk` by default, and Rust native builds look for `.tool/android-sdk/ndk/28.2.13676358`. See the [Android environment section of the Contributing Guide](./CONTRIBUTING.md#android-environment) for complete requirements and staged diagnostic commands.
