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

The core mental model is **One Timeline** (a single “Main Stream”): capture first, then ask when needed.

## ⭐ Highlights

- 🧠 **Long-term memory, local-first**: your timeline stays on your device with encryption by default.
- 🧲 **Ask AI with relevant context**: get answers grounded in your own notes, with streaming output.
- 🗂️ **Simple filters when needed**: narrow what you are viewing without juggling chat threads.
- 📥 **Capture from anywhere**: mobile share sheet + desktop global hotkey for quick capture.
- 🔐 **Privacy by design**: encrypted vault and clear control over where your data lives.
- 🌍 **Cross-platform**: one app experience across mobile and desktop.

## 🤖 AI Capability Matrix (Local / BYOK / Pro)

| AI capability | Local (on-device) | BYOK (your API key) | Pro subscription (SecondLoop Cloud) | Notes |
| --- | --- | --- | --- | --- |
| Image annotation | ⚠️ Basic on-device description | ✅ Use your own model API | ✅ Included via SecondLoop Cloud | If network AI is unavailable, the app can still provide a lightweight fallback from visible text. |
| OCR (image/PDF/doc) | ✅ On-device text recognition | ✅ Use your own model API | ✅ Included via SecondLoop Cloud | Works for images and supported documents. |
| Speech recognition (audio transcription) | ⚠️ Available on supported devices | ✅ Use your own model API | ✅ Included via SecondLoop Cloud | When offline, the app uses local transcription when available. |
| Embedding indexing | ✅ Local memory indexing | ✅ Use your own embedding API | ✅ Included via SecondLoop Cloud | New content is indexed in the background. |
| Ask AI | ❌ | ✅ Use your own chat model API | ✅ Included via SecondLoop Cloud | Route follows your source preference and current availability. |
| Semantic parsing (intent/time-window understanding) | ❌ | ✅ Use your own model API | ✅ Included via SecondLoop Cloud | Used by smart understanding and auto-actions. |
| Embedding search | ✅ Local semantic search | ✅ Use your own embedding API | ✅ Included via SecondLoop Cloud | Search can fall back across available routes. |

- `Local` means native on-device processing in iOS / Android / macOS / Windows / Linux clients.
- `BYOK` means you connect your own model service and API key in settings.
- `Pro` means an active SecondLoop Pro entitlement with a signed-in cloud account.
- This repository is still work in progress; capabilities may evolve before public launch.

## 🚀 Usage

### Availability

- SecondLoop is **not launched yet** (no stable App Store / Play Store release).
- Follow updates via the website: https://secondloop.app
- If you want to try it from source today, see `CONTRIBUTING.md`.

### Quick walkthrough

1) **Create your vault** (first run)
   Local data is encrypted at rest. You’ll enter your master password when the vault is first locked/unlocked.

2) **Capture (Send)**
   Use the chat input to quickly save thoughts/links, or:
   - Mobile: share text/URL/images from other apps into SecondLoop
   - Desktop: press `⌘⇧K` (macOS) / `Ctrl+Shift+K` (Windows/Linux) for quick capture

3) **Ask AI (explicit)**
   Use **Ask AI** when you want an answer; SecondLoop uses your relevant memories as context and sends only what is needed to the model.


### Privacy note (what gets uploaded)

When Ask AI uses a remote model (BYOK or SecondLoop Cloud), the client uploads **your question + only the relevant context needed for that answer**. It does **not** upload your keys, master password, or your entire vault/history.

## 🧩 Editions (Community vs Cloud)

- **Community Edition (this repo)**: BYOK (bring your own key), local‑first, encrypted vault, and BYOS (bring your own storage) sync backends.
- **SecondLoop Cloud (premium, managed)**: optional hosted services (account, AI gateway, managed vault, realtime sync).

## 📄 License

- The **SecondLoop Community Edition (this repository)** is licensed under the **Apache License 2.0**. See `LICENSE`.
- **SecondLoop Cloud** (managed hosted services and billing infrastructure) is not distributed in this repository and is offered under separate commercial terms.

## 🤝 Contributing

If you want to contribute, please read `CONTRIBUTING.md` for development setup, commands, platform prerequisites, and release process details.
