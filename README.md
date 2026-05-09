<div align="center">
  <img src="web/icons/Icon-192.png" width="96" alt="SecondLoop" />

  <h1>SecondLoop</h1>
  <p><b>Close your open loops.</b></p>
  <p>Personal AI assistant with long-term memory and an encrypted vault, powered by either self-managed BYOK runtime or SecondLoop Cloud.</p>
  <p><a href="https://secondloop.app">https://secondloop.app</a></p>
  <p>
    English · <a href="README.zh-CN.md">简体中文</a>
  </p>
  <p>
    <a href="CONTRIBUTING.md">Contributing</a>
  </p>

</div>

> ✅ **Official launch**
> SecondLoop Community Edition is now officially launched for macOS, Windows, Android, and Linux (x64). We no longer plan destructive data format changes in normal releases.

## ✨ What is SecondLoop?

SecondLoop is an **open-source** (Community Edition), privacy-first “second brain” that helps you **capture**, **remember**, and **act** through a required AI runtime — without turning your life into folders and tabs.

The core mental model is **One Timeline** (a single “Main Stream”): capture first, then ask when needed.

## ⭐ Highlights

- 🧠 **Long-term memory in an encrypted vault**: your timeline is protected at rest and can be connected to the runtime mode you choose.
- 🧲 **Ask AI with relevant context**: get answers grounded in your own notes, with streaming output.
- 🤖 **Unified AI runtime**: chat, embeddings, semantic parsing, media understanding, and multimodal understanding are required capabilities in both supported modes.
- 🗂️ **Simple filters when needed**: narrow what you are viewing without juggling chat threads.
- 📥 **Capture from anywhere**: mobile share sheet + desktop global hotkey for quick capture.
- 🔐 **Privacy by design**: encrypted vault and clear control over where your data lives.
- 🌍 **Cross-platform**: one app experience across mobile and desktop.

## 🤖 Runtime Modes

SecondLoop supports two runtime modes. Core AI capabilities are not optional: the app expects a working LLM, embedding, semantic parsing, media understanding, and multimodal-capable model path.

| Runtime mode | Who configures model providers | Required AI capabilities | User-facing capability set |
| --- | --- | --- | --- |
| Self-managed / BYOK | You provide compatible LLM, embedding, and multimodal model endpoints and keys. | Chat, working set, embeddings, semantic parsing, task intelligence, media understanding, multimodal LLM. | Same app capabilities as Managed Pro. |
| Managed Pro / SecondLoop Cloud | SecondLoop configures and operates the hosted LLM, embedding, and multimodal providers. | Chat, working set, embeddings, semantic parsing, task intelligence, media understanding, multimodal LLM. | Same app capabilities as Self-managed. |

There is no supported “AI off” product mode, and the app no longer presents local AI fallback as a third runtime mode. Device-native helpers may still be used for platform integration, import, rendering, or performance, but core AI behavior is provided through the active runtime.

## 🚀 Usage

### Availability

- Download from [GitHub Releases](https://github.com/dale0525/SecondLoop/releases) (macOS/Windows/Android/Linux assets).
- iOS is **not live yet**.
- If you want to run from source, see `CONTRIBUTING.md`.

### Package manager install (optional)

- macOS (Homebrew):
  - `brew tap dale0525/SecondLoopHomebrew`
  - `brew install --cask secondloop`
- Windows (WinGet):
  - `winget install --id SecondLoop.SecondLoop --exact`
- Package indexes may lag behind GitHub Releases for a short period after each tag.

### Linux notes (current limitations)

- Linux currently ships as a portable `.tar.gz` package (no Snap/Flatpak/APT package yet).
- Markdown → PDF export is not available on Linux yet.
- Desktop biometric unlock integration is not available on Linux yet; use your app password to unlock.

### Quick walkthrough

1) **Create your vault** (first run)
   Vault data is encrypted at rest. You’ll enter your master password when the vault is first locked/unlocked.

2) **Capture (Send)**
   Use the chat input to quickly save thoughts/links, or:
   - Mobile: share text/URL/images from other apps into SecondLoop
   - Desktop: press `⌘⇧K` (macOS) / `Ctrl+Shift+K` (Windows/Linux) for quick capture

3) **Connect a runtime and use AI**
   Use self-managed/BYOK if you want to provide your own model endpoints and keys, or sign in to Managed Pro to use SecondLoop Cloud. Once a runtime is available, **Ask AI** and smart organization use only the relevant context needed for the task.


### Privacy note (what gets uploaded)

When SecondLoop calls a model through self-managed/BYOK or SecondLoop Cloud, the client uploads **your question + only the relevant context needed for that answer or action**. It does **not** upload your master password, provider keys, or your entire vault/history.

## 🔄 Desktop update strategy (current)

- **Windows**: MSI-only release path; updates are manual via MSI download, release page, or WinGet.
- **Windows artifact contract**: the official release asset is `SecondLoop-win.msi`, with checksum file `SecondLoop-win.msi.sha256`.
- **macOS**: manual DMG download/update (no paid signing/notarization yet).
- If release-note generation fails in GitHub Actions, rerun the workflow manually; there is no automatic fallback notes path.
- Windows release automation uses `.github/workflows/release.yml` and `scripts/publish_winget_manifest.sh`.

## 🧩 Editions (Community vs Cloud)

- **Community Edition (this repo)**: open-source app with self-managed/BYOK runtime support, encrypted vault, and BYOS (bring your own storage) sync backends.
- **SecondLoop Cloud / Managed Pro (premium, managed)**: hosted runtime services, account, AI providers, managed vault, realtime sync, billing, and quota infrastructure.

## 📄 License

- The **SecondLoop Community Edition (this repository)** is licensed under the **Apache License 2.0**. See `LICENSE`.
- **SecondLoop Cloud** (managed hosted services and billing infrastructure) is not distributed in this repository and is offered under separate commercial terms.

## 🤝 Contributing

If you want to contribute, please read `CONTRIBUTING.md` for development setup, commands, platform prerequisites, and release process details.
