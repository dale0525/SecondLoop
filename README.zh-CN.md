<div align="center">
  <img src="web/icons/Icon-192.png" width="96" alt="SecondLoop" />

  <h1>SecondLoop</h1>
  <p><b>Close your open loops.</b></p>
  <p>本地优先的个人 AI 助手：长期记忆 + 加密 Vault，面向移动端与桌面端。</p>
  <p><a href="https://secondloop.app">https://secondloop.app</a></p>
  <p>
    简体中文 · <a href="README.md">English</a>
  </p>
  <p>
    <a href="CONTRIBUTING.md">贡献指南</a>
  </p>

</div>

> 🚧 **开发中 / 未正式上线**
> SecondLoop 正在快速迭代中，尚未正式发布。短期内可能出现破坏性变更（breaking changes）。

## ✨ SecondLoop 是什么？

SecondLoop 是一个（Community Edition）**开源**、隐私优先的 “Second Brain”，帮你更快地 **捕获**、**记住**、并 **执行** —— 而不是让你管理一堆文件夹和标签页。

它的核心心智模型是 **一条时间轴（Main Stream）** + 一个轻量的 **Focus 语境条**：需要时再收窄上下文，而不是频繁创建/切换会话。

## ⭐ 亮点

- 🧠 **长期记忆，本地优先**：时间轴存储在本地加密数据库中。
- 🧲 **Ask AI + RAG**：回答由本地检索到的 Top‑K 片段提供上下文，支持流式输出与取消。
- 🗂️ **Focus 替代“新会话”**：用时间/标签等过滤收窄语境，不用管理 Session 列表。
- 📥 **随手收集**：移动端 Share Sheet，桌面端全局快捷键快速捕获。
- 🔐 **加密 Vault & 数据主权**：数据位置由你决定；同步围绕端到端加密（E2EE）设计。
- 🌍 **跨平台**：Flutter UI + Rust Core 覆盖移动端与桌面端。

## 🚀 用法

### 获取方式

- SecondLoop **尚未正式上线**（暂无稳定的 App Store / Play Store 发布）。
- 最新动态请关注官网：https://secondloop.app
- 想立即体验：可从源码构建（见下方“开发者/贡献者”）。

### 快速上手

1) **创建 Vault（首次启动）**
   你会设置主密码；本地数据会以加密方式落盘。

2) **捕获（Send）**
   在聊天输入框随手记录想法/链接，或：
   - 移动端：从其他 App 分享文字/URL/图片到 SecondLoop
   - 桌面端：按 `⌘⇧K`（macOS）/ `Ctrl+Shift+K`（Windows/Linux）快速捕获

3) **提问（Ask AI）**
   需要答案时再点 **Ask AI**：SecondLoop 会先在本地检索相关片段（RAG），仅上传必要文本以获得回答。

4) **用 Focus 控制语境**
   切换 Focus（如“全部记忆 / 最近 7 天 / 工作”等）来控制 Ask AI 的检索范围。

### 隐私说明（哪些会上传）

当 Ask AI 使用远程模型（BYOK 或 SecondLoop Cloud）时，客户端会上传 **你的问题 + 少量本地检索到的文本片段（Top‑K）**。不会上传你的密钥、主密码、或整个 Vault/完整历史。

## 🧩 版本：Community vs Cloud

- **Community Edition（本仓库）**：BYOK（自带 Key）、本地优先、加密 Vault、以及 BYOS（自带存储）的同步后端。
- **SecondLoop Cloud（付费托管）**：可选的托管服务（账号、AI 网关、托管 Vault、实时同步等）。

## 📄 License

- **SecondLoop Community Edition（本仓库）** 采用 **Apache License 2.0**，详见 `LICENSE`。
- **SecondLoop Cloud**（托管服务与计费基础设施）不包含在本仓库中，采用独立商业条款提供。

## 🛠️ 开发者 / 贡献者

新贡献者建议从 `CONTRIBUTING.md` 开始。

### 技术栈

- **Flutter**：跨平台 UI（移动端 + 桌面端）
- **Rust**：核心逻辑（通过 `flutter_rust_bridge`，负责 DB/加密/同步/embedding 等）
- **SQLite** + 向量检索（`sqlite-vec`）：用于本地记忆检索

### 开发环境（Pixi + FVM）

1) 安装 Pixi：https://pixi.sh

2) 可选预热：提前安装固定版本的 Flutter SDK（通过 FVM）：

```bash
pixi run setup-flutter
```

如果你使用 git worktree（尤其 worktree 路径不固定/临时目录），建议每个 worktree 初始化一次共享缓存与工具链：

```bash
pixi run bootstrap-shared-worktree-env
```

3) 常用命令：

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
pixi run package-windows-msix
pixi run generate-windows-msix-cert
```

备注：
- `run-macos` 仅在 macOS 可用。
- `run-linux` 仅在 Linux 可用。
- `run-windows` 仅在 Windows 可用，并会自动执行预检初始化（将 `nuget.exe` 下载到 `.tool/nuget/`，并将静态 `ffmpeg.exe` 下载到 `.tool/ffmpeg/windows`）。
- `package-windows-msix` 仅在 Windows 可用；当设置 `SECONDLOOP_WINDOWS_MSIX_CERT_PATH`、`SECONDLOOP_WINDOWS_MSIX_CERT_PASSWORD`、`SECONDLOOP_WINDOWS_MSIX_PUBLISHER` 后会产出签名 MSIX。
- `generate-windows-msix-cert` 会生成本地自签名 `.pfx/.cer` 与 CI 可用的 base64 文件。
- Android 相关任务会把 SDK/NDK 与 Rust targets 安装到 `.tool/`（无需系统级 Android SDK）。
- `bootstrap-shared-worktree-env` 会将 `.tool`、`.pixi/envs` 软链接到 `git rev-parse --git-common-dir` 下的共享目录，并在可用时将 `.env.local` 链接到主 worktree，避免每个 worktree 重复准备依赖。
- 所有 `run-xxx` 任务在首次执行时都会自动触发 `bootstrap-shared-worktree-env`、`setup-flutter` 与 `init-env`，因此新 clone 后可以直接执行 `pixi run run-xxx`。
- `build-android-apk` / `build-android-apk-cn` 也会在构建前自动触发 `bootstrap-shared-worktree-env`。
- 桌面运行任务（`run-macos` / `run-linux` / `run-windows`）会在启动前准备随包 `ffmpeg`；macOS 会自动下载静态二进制到 `.tool/ffmpeg/macos`，也可放在 `.tool` 或通过 `--source-bin` 指定（无需系统级安装）。
- 本地调试 `pixi run run-windows` 不需要任何 MSIX 证书变量。
- 若要安装导出的 `.msix` 包，可在 Windows 执行 `powershell -ExecutionPolicy Bypass -File scripts/install_windows_msix.ps1 -MsixPath <msix文件路径>`。

如需执行任意 Flutter/Dart/Cargo 命令：

```bash
pixi run flutter <command> [command-args]
# 多个参数可放在同一个引号字符串里：
pixi run flutter test "--coverage --reporter expanded"
pixi run dart format "--output=none lib test rust_builder integration_test test_driver --set-exit-if-changed"
pixi run cargo clippy "--all-targets --all-features -- -D warnings"
```

### 可选：Cloud 配置（维护者 / 自建基础设施）

- 创建本地配置：`pixi run init-env`（从 `.env.example` 生成 `.env.local`）
- `pixi run flutter test` / `pixi run cargo test` 不需要任何 Cloud 配置。
- Cloud 登录 + Cloud Ask AI（可选）需要：
  - `SECONDLOOP_FIREBASE_WEB_API_KEY`
  - `SECONDLOOP_CLOUD_ENV=staging|prod`
  - `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING` / `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD`
- Windows MSIX 发版（GitHub Actions `release.yml`）还需要：
  - `SECONDLOOP_WINDOWS_MSIX_CERT_BASE64`（base64 编码的 `.pfx`）
  - `SECONDLOOP_WINDOWS_MSIX_CERT_PASSWORD`
  - `SECONDLOOP_WINDOWS_MSIX_PUBLISHER`（必须与证书 Subject 一致，例如 `CN=SecondLoop Dev`）

### 排错

- 如果在 Windows 看到构建错误引用了 macOS 路径（如 `/Users/.../fvm/versions/...`），删除生成的 Flutter 构建产物（或执行 `dart pub global run fvm:main flutter clean`），然后重新跑 `pixi run setup-flutter`。
- 如果 `flutter pub get` 访问 `https://pub.dev` 出现 TLS 错误，可尝试 `export PUB_HOSTED_URL=https://pub.flutter-io.cn` 后重试。

### 平台前置依赖

- Android：可选 Android Studio。Pixi 任务会把 SDK/NDK + Rust 工具链安装到 `.tool/`（可用 `pixi run flutter doctor -v` 验证）。
- Windows（开发/构建）：Visual Studio 2022 + Desktop development with C++ + 组件 `C++ ATL for latest v143 build tools (x86 & x64)`（用于 `atlstr.h`）。终端用户不需要 VS/ATL（可能需要 VC++ runtime，安装器应包含）。
- macOS/iOS：Xcode + Command Line Tools
