# AgentWeave

[English](./README.md) | 简体中文

AgentWeave 是一个面向开发者的 **Agent App Framework**。它提供可复用的 Agent runtime、模型适配、扩展系统、安全边界和跨平台宿主，让一个新 Agent App 的差异主要来自 Prompt、Skills、Connectors、策略和产品界面，而不是对核心 turn loop 的复制与重写。

你可以用它构建个人秘书、研究助手、内容工作流、企业内部 Agent 或其他垂直应用；仓库中的秘书应用只是参考实现，不是框架的固定产品形态。

> [!IMPORTANT]
> 项目仍处于 `0.1.x` 阶段，Manifest、Host API 和 Foundation Skill 契约可能在形成稳定版本前调整。当前更适合原型验证、框架开发和受控环境集成，不建议在未经安全评审的情况下直接处理生产凭据或高风险外部操作。

## 先选一条路径

| 目标 | 从这里开始 |
| --- | --- |
| 先把项目跑起来 | 继续阅读下方“5 分钟快速开始” |
| 基于框架开发自己的 Agent App | [开发 Agent App](./DEVELOPING_AGENT_APPS.zh-CN.md) |
| 为 runtime、宿主或 Foundation Skill 贡献代码 | [贡献指南](./CONTRIBUTING.zh-CN.md) |
| 接入真实 IMAP/SMTP 邮箱 | [Mail Connector 配置](./MAIL_CONNECTOR_SETUP.zh-CN.md) |
| 集成受管桌面 sidecar | [本地 Sidecar 传输协议](./LOCAL_SIDECAR_TRANSPORT.zh-CN.md) |
| 集成持久对话历史 | [对话生命周期](./CONVERSATION_LIFECYCLE.zh-CN.md) |
| 流式运行、停止并恢复 turn | [流式 Turn 生命周期](./STREAMING_TURN_LIFECYCLE.zh-CN.md) |
| 接入加密本地备份与恢复 | [本地数据保护与备份](./DATA_PROTECTION.zh-CN.md) |

## 5 分钟快速开始

### 1. 准备环境

你只需要预先安装 Git 和 [pixi](https://pixi.prefix.dev/latest/)。Rust、Node.js、Python、OpenJDK 和其他命令行依赖由项目的 Pixi 环境管理，不需要系统级安装。

当前 `pixi.toml` 已声明 macOS Apple Silicon、macOS Intel 和 Linux x86_64。Android 构建还需要项目本地的 Android SDK/NDK，首次体验 Desktop/Server 时可以暂时跳过。

```bash
git clone https://github.com/dale0525/agentweave.git
cd agentweave

pixi install
pixi run npm --prefix apps/desktop ci
```

第二条安装命令只写入 `apps/desktop/node_modules`。项目生成物、缓存和本地工具应保留在已忽略的目录中，不要把依赖安装到系统环境。

### 2. 验证仓库资产

```bash
pixi run validate-agent-assets
pixi run test-dev-script
```

这两组快速检查会验证 App Manifest、示例 App、脚手架/打包脚本和本地开发入口，不需要模型 API Key 或外部账号。

### 3. 启动最小示例

```bash
AGENTWEAVE_APP_ROOT=examples/minimal-agent pixi run dev
```

命令会同时启动本地 Agent Server 和 Desktop 的开发页面：

- 开发页面：<http://127.0.0.1:5173>
- Server 健康检查：<http://127.0.0.1:49321/health>

看到健康检查返回 `ok`，并且开发页面能够加载，就说明本地链路已经跑通。模型不是启动必需项；需要实际对话时，在设置页填写兼容 Responses、Chat Completions 或 Completion 协议的模型地址、端点类型和模型名。按 `Ctrl+C` 会同时停止两个进程。

### 4. 创建自己的 Agent App

```bash
pixi run scaffold-agent-app -- \
  --name "Research Agent" \
  --app-id com.example.research-agent \
  --output output/research-agent

pixi run scaffold-agent-app -- --validate output/research-agent
AGENTWEAVE_APP_ROOT=output/research-agent pixi run dev
```

生成目录中的 `agent-app.json` 定义应用身份、兼容性、可用语言、能力和安全策略，`locales/` 管理界面词典，`prompts/` 定义 Agent 行为，`packages/` 放应用私有 Skills。完整的 Manifest、i18n、主题、字体、Skill 和发布说明见 [开发 Agent App](./DEVELOPING_AGENT_APPS.zh-CN.md)。

如需生成包含 Rust sidecar 和带锁 App 资源的自包含 macOS 应用，请参阅 [macOS Desktop 打包](./DESKTOP_PACKAGING.zh-CN.md)。

## 框架如何组合

```text
Custom Agent App
  agent-app.json + prompts + app packages + branding
                         |
                         v
AgentWeave Framework
  runtime + model gateway + skills + policy + storage + events
                         |
                         v
Desktop / Android / Server Hosts
  credentials + connectors + approvals + platform capabilities
```

核心设计原则是：

- **应用行为可替换**：人格、领域流程和默认能力由 App Manifest、Prompt 与可选 package 决定。
- **扩展契约稳定优先**：通用能力进入 runtime、SDK、Host Tool 或 Connector 协议，特定产品逻辑留在下游 App。
- **Prompt 不是安全边界**：凭据访问、持久写入、网络和外部副作用必须由 runtime/host 的确定性权限与审批机制约束。
- **Foundation Skills 可选**：第一方基础能力独立打包，下游应用可以启用、替换、禁用或不随产品分发。
- **默认测试不依赖外部服务**：Mail、Memory 等能力提供 fake/local backing，用于可重复地覆盖审批、幂等和错误分支。

## 仓库结构

```text
apps/
  desktop/                 Electron + React 宿主
  android/                 Kotlin Compose + Rust FFI 宿主
crates/
  agent-runtime/           turn、会话、工具、策略、存储和扩展生命周期
  model-gateway/           模型端点与流式协议适配
  agent-server/            本地 HTTP API、开发诊断和后台运行入口
  mobile-ffi/              Android 与 Rust runtime 的桥接层
skills/                    内置、Foundation 和开发者 Skills
catalog/                   Foundation Skills 与主题的机器可读目录
examples/                  可运行的 Agent App 参考实现
templates/agent-app/       App 脚手架模板
scripts/                   开发、校验、打包和移动端构建脚本
```

如果一个改动只服务于某个领域或产品，优先把它放进 `skills/`、独立 Connector 或 `examples/`；只有可被多类 Agent App 复用的协议、状态模型和安全机制才应进入核心 crates。

## 扩展点

### Agent App 与 Prompt

`agent-app.json` 是 Desktop、Android 和 Server 共用的版本化应用契约。System prompt 和 developer instructions 可以定义人格与行为，但不能授予权限，也不能绕过 Host 审批。

### Skills

Skill 描述“如何完成一类任务”，可以包含 `SKILL.md`、`references/`、`scripts/`、`assets/` 和 runtime tool manifest。Skill 不应自行承担通用 OAuth、凭据保存或高风险业务审批。

### Connectors 与 Host Tools

Connector 和 Host Tool 确定性地访问邮箱、日历、浏览器或设备能力，并通过框架的认证、权限、超时、取消、审计和幂等机制运行。厂商适配器可以独立发布，核心 runtime 只维护协议和安全执行边界。

### 跨平台宿主

Desktop、Android 和 Server 共享同一 App/Skill 契约，但由各自宿主实现凭据存储、平台能力与 UI。新增能力时应先明确哪一部分属于 runtime，哪一部分必须由 host 提供。

## 当前能力与成熟度

当前仓库已包含版本化 Agent App Manifest、可替换 Prompt、多轮会话、Skill 资源与发布生命周期、持久 Memory、Durable Run、审批、Credential Vault、Connector Runtime、Scheduler，以及 Desktop、Android、Server 三类宿主。

Foundation Catalog 是能力状态的唯一机器可读来源，位于 [`catalog/foundation-skills.json`](./catalog/foundation-skills.json)。当前概况如下：

- Stable：Filesystem、Memory；Skill Creator 面向开发者使用。
- Preview：Mail、Calendar、Tasks、Web Research、Documents、Contacts、Notifications、Notes、Messaging、Scheduler。
- Reference only：`echo` 等用于验证扩展机制的示例，不代表框架的产品方向。

Preview package 已实现并通过本地 package 校验，但 API、Provider/Connector 覆盖和跨平台行为仍可能变化。应用是否启用某项能力，始终由自己的 Manifest 决定。

## 常用开发命令

| 命令 | 用途 |
| --- | --- |
| `pixi run dev` | 同时启动 Server 与 Desktop 开发页面 |
| `pixi run server` | 只启动本地 Server |
| `pixi run test` | 运行 Rust workspace 测试 |
| `pixi run check-skills` | 校验仓库内 Skill packages |
| `pixi run test-dev-script` | 测试脚手架、打包和其他 Node 脚本 |
| `pixi run source-lines` | 检查代码类文件不超过 1000 行 |
| `pixi run skill-lifecycle-check` | 运行包含 Android 构建在内的完整质量门禁 |

完整门禁需要本地 Android SDK/NDK。按改动范围选择测试、准备 Android 环境和提交 Pull Request 的规则见 [贡献指南](./CONTRIBUTING.zh-CN.md)。

## 安全模型摘要

- App 与 Skill 声明能力需求，Host 决定实际授予范围。
- 外部副作用必须经过可恢复审批，并使用幂等标识避免重复执行。
- 凭据由 Host Credential Vault 保存，不进入 Prompt、Skill 包、Manifest 或 Git。
- Workspace 工具必须限制在批准目录内，不能把应用、Skill、缓存或数据库控制目录当成普通工作区。
- 外部服务测试必须显式启用；默认测试只使用 fake server 或本地存储。

发现潜在安全问题时，不要在示例配置、测试日志或公开 Issue 中附上真实凭据、邮件内容或个人数据。

## 文档导航

- [贡献指南](./CONTRIBUTING.zh-CN.md)：环境初始化、改动边界、测试矩阵和 PR 清单。
- [开发 Agent App](./DEVELOPING_AGENT_APPS.zh-CN.md)：Manifest、Prompt、Skill、主题、字体和发布产物。
- [Minimal Agent](./examples/minimal-agent/README.md)：最小消费者应用。
- [Secretary Agent](./examples/secretary-agent/README.zh-CN.md)：组合 Mail、Memory 与应用私有 Skill 的参考应用。
- [Managed Gateway Agent](./examples/managed-gateway-agent/README.zh-CN.md)：使用可替换身份、权益与 Cloudflare 网关 Provider 的 App 托管模型参考应用。
- [Mail Connector 配置](./MAIL_CONNECTOR_SETUP.zh-CN.md)：IMAP/SMTP 与 Credential Vault 的本地配置。
- [本地数据保护与备份](./DATA_PROTECTION.zh-CN.md)：加密备份、可信 Desktop 密钥处理和安全重启恢复。
- [项目协作约定](./AGENTS.md)：架构边界、工具、编码与仓库级约束。

## 参与贡献

欢迎贡献可复用的 runtime 能力、Host/Connector 契约、Foundation Skills、测试夹具、示例和文档。开始编码前，请先阅读 [贡献指南](./CONTRIBUTING.zh-CN.md)，确认改动应该进入核心、可选 package 还是示例应用，并为涉及权限、凭据、持久化或外部副作用的路径补充失败与恢复测试。

## License

除另行标识的第三方材料外，AgentWeave 由使用者任选 [Apache License 2.0](./LICENSE-APACHE) 或 [MIT License](./LICENSE-MIT) 授权。贡献条款见 [LICENSE](./LICENSE)，仓库级归属声明见 [NOTICE](./NOTICE)。

第三方 Skill、脚本、主题、协议、Connector、依赖和资产继续适用各自的许可证与版权声明；再分发时必须保留对应 package 内的许可证和 notice 文件。
