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

- 🧠 **Long-term memory, local-first**: your timeline stays on your device with encryption by default.
- 🧲 **Ask AI with relevant context**: get answers grounded in your own notes, with streaming output.
- 🗂️ **Focus instead of chat clutter**: narrow context by time or tags without juggling chat threads.
- 📥 **Capture from anywhere**: mobile share sheet + desktop global hotkey for quick capture.
- 🔐 **Privacy by design**: encrypted vault and clear control over where your data lives.
- 🌍 **Cross-platform**: one app experience across mobile and desktop.

## 🤖 AI Capability Matrix (Local / BYOK / Pro)

| AI capability | Local (on-device) | BYOK (your API key) | Pro subscription (SecondLoop Cloud) | Notes |
| --- | --- | --- | --- | --- |
| Image annotation | ⚠️ OCR fallback | ✅ OpenAI-compatible multimodal | ✅ Managed cloud multimodal | Local mode extracts visible text first, then builds lightweight captions from OCR signals. |
| OCR (image/PDF/doc) | ✅ Native + desktop runtime OCR | ✅ Multimodal OCR via BYOK profile | ✅ Cloud OCR (usage counted under Ask AI) | OCR source can be configured per capability in AI settings. |
| Speech recognition (audio transcription) | ⚠️ Local runtime on supported native platforms | ✅ BYOK Whisper/multimodal | ✅ Cloud Whisper gateway | Local fallback availability depends on platform/runtime state. |
| Embedding indexing | ✅ Local embedding index | ✅ BYOK embedding profile | ✅ Cloud embeddings | Pending items are indexed incrementally in the background. |
| Ask AI | ❌ (no fully local LLM route in CE) | ✅ | ✅ | Ask AI routing follows your source preference and current availability. |
| Semantic parsing (intent/time-window understanding) | ❌ | ✅ | ✅ | Auto-actions and intent parsing use BYOK or Cloud model routes. |
| Embedding search | ✅ Local vector search | ✅ BYOK embedding query | ✅ Cloud embedding query | Search can fall back across routes when configured. |

- `Local` means native on-device processing in iOS / Android / macOS / Windows / Linux clients.
- `BYOK` means you configure your own model provider/API keys in settings.
- `Pro` means an active SecondLoop Pro entitlement with signed-in cloud account.
- This repository is still work in progress; capabilities may evolve before public launch.

## 🚀 Usage

### Availability

- SecondLoop is **not launched yet** (no stable App Store / Play Store release).
- Follow updates via the website: https://secondloop.app
- If you want to try it from source today, see `CONTRIBUTING.md`.

### Quick walkthrough

1) **Create your vault** (first run)
   You’ll set a master password; local data is stored encrypted at rest.

2) **Capture (Send)**
   Use the chat input to quickly save thoughts/links, or:
   - Mobile: share text/URL/images from other apps into SecondLoop
   - Desktop: press `⌘⇧K` (macOS) / `Ctrl+Shift+K` (Windows/Linux) for quick capture

3) **Ask AI (explicit)**
   Use **Ask AI** when you want an answer; SecondLoop uses your relevant memories as context and sends only what is needed to the model.

4) **Use Focus to scope context**
   Switch Focus (e.g. “All Memories”, “Last 7 Days”, “Work”) to control what Ask AI searches.

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
