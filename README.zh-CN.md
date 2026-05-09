<div align="center">
  <img src="web/icons/Icon-192.png" width="96" alt="SecondLoop" />

  <h1>SecondLoop</h1>
  <p><b>Close your open loops.</b></p>
  <p>个人 AI 助手：长期记忆 + 加密 Vault，由 self-managed BYOK runtime 或 SecondLoop Cloud 驱动。</p>
  <p><a href="https://secondloop.app">https://secondloop.app</a></p>
  <p>
    简体中文 · <a href="README.md">English</a>
  </p>
  <p>
    <a href="CONTRIBUTING.md">贡献指南</a>
  </p>

</div>

> ✅ **正式发布**
> SecondLoop Community Edition 已正式上线（macOS / Windows / Android / Linux x64）。常规版本不再计划引入破坏性数据格式变更。

## ✨ SecondLoop 是什么？

SecondLoop 是一个（Community Edition）**开源**、隐私优先的 “Second Brain”，通过必需的 AI runtime 帮你更快地 **捕获**、**记住**、并 **执行** —— 而不是让你管理一堆文件夹和标签页。

它的核心心智模型是 **一条时间轴（Main Stream）**：先记录，再在需要时提问。

## ⭐ 亮点

- 🧠 **长期记忆与加密 Vault**：你的时间轴会加密保存，并连接到你选择的 runtime 模式。
- 🧲 **Ask AI 更贴合你的内容**：基于你的笔记与记录给出回答，并支持流式输出。
- 🤖 **统一 AI runtime**：chat、embedding、semantic parse、媒体理解、多模态理解等核心能力在两种支持模式中都是必需能力。
- 🗂️ **需要时再筛选**：按标签快速收窄查看范围，不需要维护一堆聊天线程。
- 📥 **随手收集**：移动端分享入口 + 桌面端全局快捷键，想到就记。
- 🔐 **隐私优先**：加密 Vault，数据放哪里由你决定。
- 🌍 **跨平台一致体验**：移动端和桌面端都可使用。


## 🤖 Runtime 模式

SecondLoop 支持两种 runtime 模式。核心 AI 能力不是可选项：App 需要可用的 LLM、embedding、semantic parse、媒体理解和多模态模型路径。

| Runtime 模式 | 模型服务由谁配置 | 必需 AI 能力 | 用户可见能力 |
| --- | --- | --- | --- |
| Self-managed / BYOK | 由你提供兼容的 LLM、embedding、多模态模型接口与密钥。 | Chat、working set、embedding、semantic parse、任务智能、媒体理解、多模态 LLM。 | 与 Managed Pro 一致。 |
| Managed Pro / SecondLoop Cloud | 由 SecondLoop 配置并运营托管的 LLM、embedding、多模态 provider。 | Chat、working set、embedding、semantic parse、任务智能、媒体理解、多模态 LLM。 | 与 Self-managed 一致。 |

SecondLoop 不再支持“关闭 AI 后继续作为本地模式使用”的产品模式，也不再把本地 AI fallback 表达为第三种 runtime。设备侧能力仍可能用于平台集成、导入、渲染或性能优化，但核心 AI 行为由当前 runtime 提供。

## 🚀 用法

### 获取方式

- 请从 [GitHub Releases](https://github.com/dale0525/SecondLoop/releases) 下载（包含 macOS/Windows/Android/Linux 资产）。
- iOS **暂未上线**。
- 若需从源码运行，请查看 `CONTRIBUTING.md`。

### 包管理器安装（可选）

- macOS（Homebrew）：
  - `brew tap dale0525/SecondLoopHomebrew`
  - `brew install --cask secondloop`
- Windows（WinGet）：
  - `winget install --id SecondLoop.SecondLoop --exact`
- 新标签发布后，包管理器索引相对 GitHub Releases 可能会有短暂延迟。

### Linux 版本说明（当前限制）

- Linux 目前提供便携式 `.tar.gz` 包（暂未提供 Snap/Flatpak/APT 包）。
- Linux 暂不支持 Markdown 导出 PDF。
- Linux 暂不支持桌面生物识别快捷解锁，应用锁定后需要输入应用密码解锁。

### 快速上手

1) **创建 Vault（首次启动）**
   Vault 数据会加密保存；首次需要锁定/解锁 Vault 时，会要求你输入主密码。

2) **捕获（Send）**
   在聊天输入框随手记录想法/链接，或：
   - 移动端：从其他 App 分享文字/URL/图片到 SecondLoop
   - 桌面端：按 `⌘⇧K`（macOS）/ `Ctrl+Shift+K`（Windows/Linux）快速捕获

3) **连接 runtime 并使用 AI**
   如果你希望自行提供模型接口与密钥，使用 self-managed/BYOK；如果你希望使用托管能力，登录 Managed Pro。runtime 可用后，**Ask AI** 和智能整理只会使用完成当前任务所需的相关上下文。


### 隐私说明（哪些会上传）

当 SecondLoop 通过 self-managed/BYOK 或 SecondLoop Cloud 调用模型时，客户端只会上传 **你的问题 + 这次回答或动作所需的相关上下文**。不会上传你的主密码、provider key，或整个 Vault/完整历史。

## 🔄 桌面端更新策略（当前）

- **Windows**：仅提供 MSI 发布路径；更新需通过下载 MSI、访问发布页或使用 WinGet 手动完成。
- **Windows 制品约定**：官方发布资产为 `SecondLoop-win.msi`，对应的校验文件为 `SecondLoop-win.msi.sha256`。
- **macOS**：保持 DMG 手动更新（暂不使用付费签名/公证）。
- 若 GitHub Actions 里的 release notes 生成失败，请手动重新运行 workflow；目前没有自动回退的说明生成路径。
- Windows 发版自动化入口见 `.github/workflows/release.yml` 与 `scripts/publish_winget_manifest.sh`。

## 🧩 版本：Community vs Cloud

- **Community Edition（本仓库）**：开源 App，支持 self-managed/BYOK runtime、加密 Vault，以及 BYOS（自带存储）的同步后端。
- **SecondLoop Cloud / Managed Pro（付费托管）**：托管 runtime、账号、AI provider、托管 Vault、实时同步、计费与配额基础设施。

## 📄 License

- **SecondLoop Community Edition（本仓库）** 采用 **Apache License 2.0**，详见 `LICENSE`。
- **SecondLoop Cloud**（托管服务与计费基础设施）不包含在本仓库中，采用独立商业条款提供。

## 🤝 参与贡献

如果你想参与开发或提交 PR，请查看 `CONTRIBUTING.md`（包含开发环境、常用命令、平台依赖与发布流程说明）。
