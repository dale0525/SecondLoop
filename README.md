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

## 🛠️ Developer / Contributor Guide

New contributors: start with `CONTRIBUTING.md`.

### Stack

- **Flutter** for cross‑platform UI (mobile + desktop)
- **Rust** for core logic via `flutter_rust_bridge` (DB, crypto, sync, embeddings)
- **SQLite** + vector search (`sqlite-vec`) for local memory retrieval

### Dev setup (Pixi + FVM)

1) Install Pixi: https://pixi.sh

2) Install the pinned Flutter SDK (via FVM):

```bash
pixi run setup-flutter
```

3) Common commands:

```bash
pixi run analyze
pixi run test
pixi run rust-test
pixi run frb-generate
pixi run run-macos
pixi run run-android
pixi run build-android-apk
pixi run run-windows
```

Notes:
- `run-macos` is only available on macOS.
- `run-windows` is only available on Windows (it depends on `setup-windows`) and will download `nuget.exe` into `.tool/nuget/` so Flutter won't auto-download it.
- Android tasks install SDK/NDK and Rust targets into `.tool/` (no system-wide Android SDK required).

To run arbitrary Flutter commands through FVM:

```bash
pixi run dart pub global run fvm:main flutter <args...>
```

### Optional Cloud config (maintainers / your own infra)

- Create local config: `pixi run init-env` (generates `.env.local` from `.env.example`)
- No config is required for `pixi run test` / `pixi run rust-test`.
- Cloud login + Cloud Ask AI (optional) requires:
  - `SECONDLOOP_FIREBASE_WEB_API_KEY`
  - `SECONDLOOP_CLOUD_ENV=staging|prod`
  - `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING` / `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD`

### CI release (GitHub Actions)

Release workflow: `.github/workflows/release.yml` (tag `v*`).

Required repo secrets:
- `SECONDLOOP_FIREBASE_WEB_API_KEY`
- `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD`

### Troubleshooting

- If you see build errors referencing macOS paths like `/Users/.../fvm/versions/...` on Windows, delete generated Flutter artifacts (or run `dart pub global run fvm:main flutter clean`) and then run `pixi run setup-flutter` again.
- If `flutter pub get` fails with a TLS error to `https://pub.dev`, try `export PUB_HOSTED_URL=https://pub.flutter-io.cn` and re-run.

### Platform prerequisites

- Android: optional Android Studio. Pixi tasks provision SDK/NDK + Rust toolchain into `.tool/` (run `pixi run doctor` to verify).
- Windows (dev/build): Visual Studio 2022 + Desktop development with C++ + Individual component `C++ ATL for latest v143 build tools (x86 & x64)` (for `atlstr.h`). End users do not need VS/ATL (they may need the VC++ runtime, which your installer should include).
- macOS/iOS: Xcode + Command Line Tools
