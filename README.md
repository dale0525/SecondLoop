<div align="center">
  <img src="web/icons/Icon-192.png" width="96" alt="SecondLoop" />

  <h1>SecondLoop</h1>
  <p><b>Close your open loops.</b></p>
  <p>Local‑first personal AI assistant with long‑term memory and an encrypted vault — built for mobile + desktop.</p>
  <p><a href="https://secondloop.app">https://secondloop.app</a></p>
  <p>
    English · <a href="README.zh-CN.md">简体中文</a>
  </p>
  <p>
    <a href="CONTRIBUTING.md">Contributing</a>
  </p>

</div>

> 🚧 **Work in progress / 未正式上线**
> SecondLoop is under active development and not officially launched yet. Expect breaking changes while we ship toward a stable public release.

## ✨ What is SecondLoop?

SecondLoop is an **open-source** (Community Edition), privacy‑first “second brain” that helps you **capture**, **remember**, and **act** — without turning your life into folders and tabs.

The core mental model is **One Timeline** (a single “Main Stream”), plus a lightweight **Focus** bar to scope context when you need it.

## ⭐ Highlights

- 🧠 **Long‑term memory, local‑first**: store your timeline in an encrypted local database.
- 🧲 **Ask AI with RAG**: answers come with context retrieved locally (Top‑K snippets), with streaming + cancel.
- 🗂️ **Focus instead of “new chats”**: narrow context by time/tags without managing sessions.
- 📥 **Capture from anywhere**: mobile share sheet, desktop global hotkey, quick “send to vault”.
- 🔐 **Encrypted vault & data sovereignty**: choose where your data lives; sync is designed around E2EE.
- 🌍 **Cross‑platform**: Flutter UI + Rust core across mobile and desktop.

## 🚀 Usage

### Availability

- SecondLoop is **not launched yet** (no stable App Store / Play Store release).
- Follow updates via the website: https://secondloop.app
- If you want to try it today, build from source (see the Developer section below).

### Quick walkthrough

1) **Create your vault** (first run)
   You’ll set a master password; local data is stored encrypted at rest.

2) **Capture (Send)**
   Use the chat input to quickly save thoughts/links, or:
   - Mobile: share text/URL/images from other apps into SecondLoop
   - Desktop: press `⌘⇧K` (macOS) / `Ctrl+Shift+K` (Windows/Linux) for quick capture

3) **Ask AI (explicit)**
   Use **Ask AI** when you want an answer; SecondLoop retrieves a small set of relevant snippets locally (RAG) and sends only what’s needed to the model.

4) **Use Focus to scope context**
   Switch Focus (e.g. “All Memories”, “Last 7 Days”, “Work”) to control what Ask AI searches.

### Privacy note (what gets uploaded)

When Ask AI uses a remote model (BYOK or SecondLoop Cloud), the client uploads **your question + a small set of retrieved text snippets** (Top‑K). It does **not** upload your keys, master password, or your entire vault/history.

## 🧩 Editions (Community vs Cloud)

- **Community Edition (this repo)**: BYOK (bring your own key), local‑first, encrypted vault, and BYOS (bring your own storage) sync backends.
- **SecondLoop Cloud (premium, managed)**: optional hosted services (account, AI gateway, managed vault, realtime sync).

## 📄 License

- The **SecondLoop Community Edition (this repository)** is licensed under the **Apache License 2.0**. See `LICENSE`.
- **SecondLoop Cloud** (managed hosted services and billing infrastructure) is not distributed in this repository and is offered under separate commercial terms.

## 🛠️ Developer / Contributor Guide

New contributors: start with `CONTRIBUTING.md`.

### Stack

- **Flutter** for cross‑platform UI (mobile + desktop)
- **Rust** for core logic via `flutter_rust_bridge` (DB, crypto, sync, embeddings)
- **SQLite** + vector search (`sqlite-vec`) for local memory retrieval

### Dev setup (Pixi + FVM)

1) Install Pixi: https://pixi.sh

2) Optional prewarm: install the pinned Flutter SDK (via FVM) ahead of first run:

```bash
pixi run setup-flutter
```

3) Common commands:

```bash
pixi run flutter analyze
pixi run flutter test
pixi run cargo test
pixi run frb-generate
pixi run run-macos
pixi run run-linux
pixi run run-android
pixi run build-android-apk
pixi run run-windows
```

Notes:
- `run-macos` is only available on macOS.
- `run-linux` is only available on Linux.
- `run-windows` is only available on Windows and auto-runs its preflight setup (downloads `nuget.exe` into `.tool/nuget/` and static `ffmpeg.exe` into `.tools/ffmpeg/windows`).
- Android tasks install SDK/NDK and Rust targets into `.tool/` (no system-wide Android SDK required).
- All `run-xxx` tasks now auto-run `setup-flutter` and `init-env` on first execution, so a fresh clone can run `pixi run run-xxx` directly.
- Desktop run tasks (`run-macos` / `run-linux` / `run-windows`) prepare bundled `ffmpeg` before launching; macOS auto-downloads a static binary into `.tools/ffmpeg/macos`, and you can always override via `.tools` or `--source-bin` (no system-wide install required).

To run arbitrary Flutter/Dart/Cargo commands:

```bash
pixi run flutter <command> [command-args]
# examples with multiple flags:
pixi run flutter test "--coverage --reporter expanded"
pixi run dart format "--output=none lib test rust_builder integration_test test_driver --set-exit-if-changed"
pixi run cargo clippy "--all-targets --all-features -- -D warnings"
```

### Optional Cloud config (maintainers / your own infra)

- Create local config: `pixi run init-env` (generates `.env.local` from `.env.example`)
- No config is required for `pixi run flutter test` / `pixi run cargo test`.
- Cloud login + Cloud Ask AI (optional) requires:
  - `SECONDLOOP_FIREBASE_WEB_API_KEY`
  - `SECONDLOOP_CLOUD_ENV=staging|prod`
  - `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING` / `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD`

### Troubleshooting

- If you see build errors referencing macOS paths like `/Users/.../fvm/versions/...` on Windows, delete generated Flutter artifacts (or run `dart pub global run fvm:main flutter clean`) and then run `pixi run setup-flutter` again.
- If `flutter pub get` fails with a TLS error to `https://pub.dev`, try `export PUB_HOSTED_URL=https://pub.flutter-io.cn` and re-run.

### Platform prerequisites

- Android: optional Android Studio. Pixi tasks provision SDK/NDK + Rust toolchain into `.tool/` (run `pixi run flutter doctor -v` to verify).
- Windows (dev/build): Visual Studio 2022 + Desktop development with C++ + Individual component `C++ ATL for latest v143 build tools (x86 & x64)` (for `atlstr.h`). End users do not need VS/ATL (they may need the VC++ runtime, which your installer should include).
- macOS/iOS: Xcode + Command Line Tools
