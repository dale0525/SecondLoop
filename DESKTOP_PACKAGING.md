# macOS Desktop Packaging

AgentWeave can build a self-contained macOS Electron application for any validated Agent App that declares Desktop compatibility. The package contains the trusted Renderer and Main bundles, a matching Rust `agent-server` sidecar, the locked Agent App release, first-party Skills, and the repository license set.

## Build a package

Use Pixi so Node.js, Rust, and the packaging tools come from the project environment:

```bash
pixi run package-macos \
  --input examples/minimal-agent \
  --output dist/macos/minimal \
  --overwrite
```

The convenience tasks build the checked-in examples:

```bash
pixi run package-macos-minimal
pixi run package-macos-secretary
```

The command builds the release sidecar, compiles Desktop assets against the selected App Definition, creates and verifies an Agent App lock, packages Electron with ASAR integrity, and verifies the final resource layout. The output architecture defaults to the current Mac. `--arch arm64` and `--arch x64` are accepted only when the supplied sidecar contains the same architecture.

Use `--print-plan` to review the bundle identifier, product name, version, architecture, input, and output without running a build.

## Resource contract

The generated application uses this layout:

```text
Product.app/Contents/
  MacOS/Product
  Resources/
    app.asar
    sidecar/agent-server
    agent-app/
      agent-app.lock.json
      app/
      packages/
    skills/
    licenses/
```

Electron Main derives production paths from `process.resourcesPath`. It always binds the managed sidecar to `Resources/agent-app/app` and `Resources/skills`; host environment variables cannot redirect a packaged application to a different App Definition or built-in Skill root. User data, cache, workspace, and the SQLite database remain under Electron's per-application user-data directory.

App-local packages stay inside the locked App tree. The top-level `skills/` directory contains only selected first-party packages, which prevents the same App package from being loaded as both a built-in and App-local layer.

## Signing and release handoff

Development packages receive an ad-hoc signature for local verification. An ad-hoc designated requirement is tied to the current build hash, so macOS Keychain can treat a rebuilt App as a different accessor. Such packages are for local development, not a stable credential-bearing update channel. Desktop does not access Keychain during a clean startup without Connector secrets or an explicit backup action. Pass `--sign-identity "Developer ID Application: ..."` to use a stable distribution identity during packaging. Notarization credentials, DMG creation, update metadata, and release publication remain explicit release-pipeline steps; credentials must come from the CI secret store and must never be copied into the App, lock, logs, or fixtures.

Archive `.app` bundles with `ditto` or another macOS-aware tool so executable permissions, resource forks, and signatures are preserved.

## Verification

The packaging tests validate identity, architecture normalization, sidecar permissions, App lock integrity, first-party versus App-local Skill placement, and license inclusion without downloading Electron or requiring signing credentials. The macOS workflow then builds real packages for the minimal and secretary examples.

Before publishing, launch the packaged App on a clean Mac and verify that Electron starts its bundled sidecar without a terminal, restores a conversation after restart, and leaves no sidecar process after quitting.
