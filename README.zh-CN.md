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

- 🧠 **长期记忆，本地优先**：默认加密存储在你的设备上。
- 🧲 **Ask AI 更贴合你的内容**：基于你的笔记与记录给出回答，并支持流式输出。
- 🗂️ **Focus 代替会话管理**：按时间/标签收窄语境，不需要维护一堆聊天线程。
- 📥 **随手收集**：移动端分享入口 + 桌面端全局快捷键，想到就记。
- 🔐 **隐私优先**：加密 Vault，数据放哪里由你决定。
- 🌍 **跨平台一致体验**：移动端和桌面端都可使用。

## 🚀 用法

### 获取方式

- SecondLoop **尚未正式上线**（暂无稳定的 App Store / Play Store 发布）。
- 最新动态请关注官网：https://secondloop.app
- 想立即从源码体验，请查看 `CONTRIBUTING.md`。

### 快速上手

1) **创建 Vault（首次启动）**
   你会设置主密码；本地数据会以加密方式落盘。

2) **捕获（Send）**
   在聊天输入框随手记录想法/链接，或：
   - 移动端：从其他 App 分享文字/URL/图片到 SecondLoop
   - 桌面端：按 `⌘⇧K`（macOS）/ `Ctrl+Shift+K`（Windows/Linux）快速捕获

3) **提问（Ask AI）**
   需要答案时再点 **Ask AI**：SecondLoop 会结合与你问题相关的记忆，只上传必要内容来获得回答。

4) **用 Focus 控制语境**
   切换 Focus（如“全部记忆 / 最近 7 天 / 工作”等）来控制 Ask AI 的检索范围。

### 隐私说明（哪些会上传）

当 Ask AI 使用远程模型（BYOK 或 SecondLoop Cloud）时，客户端只会上传 **你的问题 + 这次回答所需的相关上下文**。不会上传你的密钥、主密码、或整个 Vault/完整历史。

## 🧩 版本：Community vs Cloud

- **Community Edition（本仓库）**：BYOK（自带 Key）、本地优先、加密 Vault、以及 BYOS（自带存储）的同步后端。
- **SecondLoop Cloud（付费托管）**：可选的托管服务（账号、AI 网关、托管 Vault、实时同步等）。

## 📄 License

- **SecondLoop Community Edition（本仓库）** 采用 **Apache License 2.0**，详见 `LICENSE`。
- **SecondLoop Cloud**（托管服务与计费基础设施）不包含在本仓库中，采用独立商业条款提供。

## 🤝 参与贡献

如果你想参与开发或提交 PR，请查看 `CONTRIBUTING.md`（包含开发环境、常用命令、平台依赖与发布流程说明）。
