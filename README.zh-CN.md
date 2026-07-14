# SecondLoop

[English](./README.md) | 简体中文

SecondLoop 是一款本地优先的 macOS 私人秘书。项目已经基于 [AgentWeave](https://github.com/dale0525/agentweave) 完全重构：产品界面使用 React/Electron，本地能力由 Desktop Host 管理的 Rust sidecar 提供。

当前 Desktop Beta 关注“每一步都可核对”的工作闭环：持续对话、有来源的 Today、持久任务与提醒、受审批约束的外部行动、可检查的记忆，以及加密本地备份。它不提供云端账户、托管模型网关或跨设备同步。

## 产品界面

- **今天**只汇总已经持久化的任务、计划、审批和已连接 Mail 来源。
- **对话**恢复本地会话历史，并通过可信文件选择器导入附件；原始文件路径不会进入模型输入。
- **行动**展示不可变预览、审批决定、幂等状态和 `uncertain` 结果。
- **记忆**展示已确认记录、证据、保留信息，并提供导出和明确遗忘。
- **连接**管理 BYOK 模型准备状态和邮箱公开状态，不向 Renderer 暴露秘密。
- **设置**管理外观、语言、加密备份与恢复、通知、Runtime 身份和许可证。

全新安装时，模型和 Mail 均为未配置状态。确定性的 Fake Mail 数据只能在开发或测试中显式启用，正式打包产品不会把测试账户显示成用户已经连接的邮箱。

## 架构

```text
SecondLoop React Renderer
  产品路由、本地交互状态、用户决定
                 |
                 v
Electron Main / Preload
  可信 IPC、安全存储、文件选择、sidecar 生命周期
                 |
                 v
本地 Rust sidecar
  会话、turn、审批、记忆、任务、计划、连接器、SQLite
                 |
                 v
AgentWeave Runtime + Foundation packages
```

Renderer 不会收到模型 API Key、邮箱密码、sidecar 传输 token、备份密钥或附件原始路径。外部副作用仍由 Runtime 的审批和幂等规则约束。

## 准备开发环境

预先安装 Git 和 [Pixi](https://pixi.prefix.dev/latest/)，然后运行：

```bash
pixi install
pixi run npm --prefix apps/desktop ci
pixi run validate-secondloop
```

项目工具链由 Pixi 管理。生成的工具和 QA 产物应放在已忽略的 `.tool/` 目录中，不要把项目依赖安装到系统环境。

## 构建 macOS App

```bash
pixi run package-macos-secondloop
open dist/macos/secondloop/SecondLoop-darwin-arm64/SecondLoop.app
```

产物包含 Electron Host、受管 Rust sidecar、带锁的 Agent App 资源、选中的 Foundation packages 和许可证文件。没有稳定分发签名时，反复进行本地 ad-hoc 签名可能触发 macOS Keychain ACL 提示；隔离 QA 可以显式使用 mock keychain：

```bash
dist/macos/secondloop/SecondLoop-darwin-arm64/SecondLoop.app/Contents/MacOS/SecondLoop \
  --use-mock-keychain \
  --user-data-dir="$PWD/.tool/secondloop-qa-userdata"
```

mock keychain 只用于本地 QA。稳定签名的分发构建继续使用操作系统安全存储。

## 质量门禁

通过 Pixi 运行产品与共享框架检查：

```bash
pixi run validate-secondloop
pixi run validate-agent-assets
pixi run test-dev-script
pixi run source-lines
pixi run npm --prefix apps/desktop test
pixi run npm --prefix apps/desktop exec tsc -- --noEmit -p apps/desktop/tsconfig.vitest.json
pixi run cargo fmt --all --check
pixi run cargo clippy --workspace --all-targets -- -D warnings
pixi run cargo test --workspace
```

Desktop 视觉验收覆盖 `1440 × 900`、`1280 × 800` 和 `390 × 844`。路由和状态标准记录在 [SECONDLOOP_UI_DESIGN.zh-CN.md](./SECONDLOOP_UI_DESIGN.zh-CN.md)，重构过程与上下游边界记录在 [AGENTWEAVE_REBUILD_PLAN.zh-CN.md](./AGENTWEAVE_REBUILD_PLAN.zh-CN.md)。

## 上游协作

本仓库保留两个 remote：

- `origin`：现有 `dale0525/SecondLoop` 仓库及其仓库级集成。
- `upstream`：`dale0525/agentweave`，作为通用 Runtime、Host、sidecar、打包和 Foundation 能力的权威来源。

可复用变更从 `upstream/main` 创建独立分支，在 AgentWeave 提交聚焦 PR；只有上游采纳合并后，产品主线才同步该能力。SecondLoop 品牌、路由、Prompt、私有 Skills、onboarding 和产品工作流继续保留在下游。

## 当前边界

- 首个产品 Host 是 macOS Desktop。
- 模型采用 BYOK，需要提供兼容 Responses、Chat Completions 或 Completion 的端点。
- IMAP/SMTP 是当前真实 Mail adapter；本 Beta 不包含 Gmail API、Microsoft Graph 或 OAuth onboarding。
- 加密备份使用 AES-256-GCM 和操作系统保护的密钥；活动 SQLite 数据库目前未提供静态加密。
- Android 产品化、云同步、旧 SecondLoop 数据迁移、OCR 和音频工作流不在本次发布范围内。

## 许可证

除另行标识的第三方材料外，本仓库由使用者任选 [Apache License 2.0](./LICENSE-APACHE) 或 [MIT](./LICENSE-MIT) 授权。详情见 [LICENSE](./LICENSE) 和 [NOTICE](./NOTICE)。
