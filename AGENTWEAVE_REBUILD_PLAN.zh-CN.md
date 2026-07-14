# SecondLoop 基于 AgentWeave 的完全重构计划

## 1. 文档状态

- 状态：已确认，实施中
- 基线日期：2026-07-14
- 当前产品仓库：`SecondLoop`
- 上游仓库：`dale0525/agentweave`
- 首期平台：macOS Desktop
- 首期运行方式：本地 Rust sidecar + BYOK 模型

本文定义 SecondLoop 基于 AgentWeave 完全重构的仓库策略、上游协作方式、技术边界、阶段计划、开发量、质量门禁和交付标准。

本文是实施计划，不代表立即执行仓库替换、提交、推送或发布。涉及旧仓库归档、GitHub fork 创建、历史切换和远程仓库调整的操作，必须在执行前单独确认。

## 2. 已确认的决策

以下决策作为后续设计和开发的固定前提：

1. 新产品基于 AgentWeave 完全重构，不迁移旧 Flutter UI，也不把旧 SecondLoop Rust 模块作为新运行时依赖。
2. 旧 SecondLoop 仅作为产品需求、交互经验、测试案例、文案和未来数据迁移的参考。
3. Desktop 保留本地 Rust sidecar。首期不建设云端 Server、远程账户服务或跨设备同步服务。
4. 适合多类 Agent App 使用的能力优先进入 AgentWeave 上游，不在产品 fork 中长期维护核心补丁。
5. 上游变更在本项目中开发和验证，从基于 `upstream/main` 的本地工作分支推送到 `dale0525/agentweave`，并在上游仓库内提交 Pull Request；上游采纳合并后，再将上游提交同步回产品分支。
6. 产品下游仓库保持薄定制，主要承载品牌、产品信息架构、Prompt、私有 Skills、产品工作流和产品级 UI。
7. Desktop MVP 先于 Android。iOS、云同步、旧数据迁移、OCR 和音频能力不进入首期范围。

## 3. 项目目标

### 3.1 产品目标

构建一个本地优先、边界清晰、可审计的私人秘书 Agent App。首个可用版本应能完成以下闭环：

- 用户通过 Desktop 与 Agent 持续对话，并恢复真实历史会话。
- Agent 可以使用本地 Memory，但记忆写入、修改和遗忘保持可审计。
- Agent 可以读取邮件、生成草稿、展示权威预览，并在用户批准后执行发送。
- Agent 明确区分建议、草稿、等待批准、执行中、成功、失败和结果不确定。
- 用户可以在 Action Center 中检查和处理外部副作用。
- 产品可以通过 App Manifest、Prompt、Skills、Connector 和 Host 能力继续扩展。

### 3.2 工程目标

- AgentWeave Runtime 保持领域无关，不在 turn loop 中加入私人秘书特例。
- 通用 Host、传输、安全和 Foundation 能力通过上游 PR 交付。
- 产品代码与上游基建代码保持清晰边界。
- 上游合并提交是通用能力的唯一权威来源。
- 默认测试不依赖真实模型、邮箱或其他外部账号。
- 所有代码类文件保持少于 1000 个物理行。
- 开发环境和依赖由 Pixi 及项目内工具目录管理。

## 4. 非目标

以下内容不属于 Desktop MVP：

- 复用旧 SecondLoop 的 Flutter 页面或状态管理实现。
- 直接复用旧 SecondLoop 的 Rust 数据库、同步和 RAG 实现。
- 云端用户账户、订阅、计费、托管模型网关或多租户服务。
- 跨设备实时同步和托管 Vault。
- Gmail API、Microsoft Graph 和 Calendar OAuth 的完整生产接入。
- iOS Host。
- OCR、语音转写、视频处理和本地大模型生命周期。
- 旧 SecondLoop 数据的自动迁移。
- 在上游 Runtime 中硬编码私人秘书领域页面或工作流。

## 5. 仓库拓扑

目标仓库关系如下：

```text
dale0525/agentweave
  通用 Runtime、Desktop/Android Host、sidecar、Foundation Skills
                         |
                         | 上游发布版本与合并提交
                         v
Personal Secretary downstream
  品牌、产品路由、Prompt、私有 Skills、产品级 UI
                         |
                         v
Desktop / Android 产品构建

旧 SecondLoop 仓库
  冻结为 legacy，仅用于需求和迁移参考
```

`dale0525` 同时拥有 AgentWeave 和 SecondLoop，且没有可用的组织 namespace，因此 GitHub 不支持在同一账号下创建原生 fork。本项目采用保留现有 `dale0525/SecondLoop` 仓库对象、替换产品主线历史、配置上游 remote 的独立下游模式。

目标本地 remote 约定：

- `origin`：`dale0525/SecondLoop`，保留现有 GitHub 仓库对象和仓库 ID。
- `upstream`：`https://github.com/dale0525/agentweave.git`。

旧 SecondLoop 历史通过 `legacy/*` 分支和不可变 tag 保留。不得删除并重建 GitHub 仓库，因为 GitHub Apps、Greptile 免费审核名额、issues、PRs、releases、stars 和其他仓库级集成都可能绑定现有仓库 ID。主线切换前必须确认 legacy 分支、tag 和远程备份均可恢复。

## 6. 分支模型

### 6.1 长期分支

- `main`：产品主线，包含已采纳的上游代码和私人秘书产品代码。
- `upstream/main`：上游 AgentWeave 主线的远程跟踪分支。
- `legacy/*`：只读的旧 SecondLoop 历史引用，不参与新产品构建。

### 6.2 工作分支

- `upstream/<topic>`：通用基建变更，必须从最新 `upstream/main` 创建。
- `product/<topic>`：私人秘书产品变更，从产品 `main` 创建。
- `integration/<topic>`：等待上游 PR 合并期间的临时联调分支，不直接合并到产品 `main`。

实际由 Codex 创建分支时使用 `codex/` 前缀，例如 `codex/upstream-sidecar-supervisor`。人工创建分支可以沿用团队约定，但必须保留上游变更和产品变更的语义区分。

### 6.3 上游 PR 强制流程

每一项上游变更按以下流程执行：

1. 在当前项目记录通用问题、适用场景、安全边界和可观察验收行为。
2. 执行 `git fetch upstream`，确认本地工作区干净。
3. 从最新 `upstream/main` 创建独立的 `upstream/<topic>` 分支。
4. 在当前项目工作目录中实现代码、测试、示例和必要文档。
5. 检查变更不依赖私人秘书品牌、私有 Skill、产品路由或产品数据。
6. 运行与变更范围匹配的 AgentWeave 质量门禁。
7. 使用 `Logic Tan <logictan89@gmail.com>` 提交，将上游工作分支推送到 `dale0525/agentweave`。
8. 从该上游工作分支向 `dale0525/agentweave:main` 创建聚焦的 Pull Request。
9. 根据上游评审修改同一 PR，直到被上游采纳并合并。
10. 合并后执行 `git fetch upstream`，以新的上游提交为权威实现。
11. 将更新后的 `upstream/main` 合并或变基到产品 `main`，运行产品组合测试。
12. 删除产品侧临时集成实现，避免同一能力在上游和产品层存在两份权威代码。

上游 PR 尚未合并时，依赖该能力的产品联调只能进入 `integration/<topic>`。不得把未经上游采纳的通用实现永久合入产品 `main`。

### 6.4 上游 PR 验收条件

上游 PR 必须同时满足：

- 能服务私人秘书之外的其他 Agent App。
- 不在 Runtime 中写入领域分支或产品品牌。
- 新增公开契约时包含版本兼容和失败行为说明。
- 涉及权限、凭据、持久化或外部副作用时包含拒绝、失败和恢复测试。
- 默认测试使用 fake 或 local backing，不要求真实凭据。
- Desktop、Android 或 Server 不支持的能力明确拒绝或降级。
- App Manifest、Skill Catalog、示例和实现保持一致。
- 代码类文件少于 1000 个物理行。
- 文档、日志和 fixture 不包含真实 secret 或用户数据。

## 7. 上游与产品边界

### 7.1 优先进入上游的能力

| 能力 | 目标位置 | 说明 |
| --- | --- | --- |
| 双许可证、NOTICE 和第三方资产清单 | 仓库根目录、Catalog | 所有下游发布的前置条件 |
| App Manifest 驱动的 Host 功能发现 | Runtime、Desktop、Android Host | 让能力声明控制可见界面和可用入口 |
| Electron 管理本地 Rust sidecar | Desktop Main、构建脚本 | 统一进程生命周期、日志和数据目录 |
| sidecar 安全传输 | Desktop Preload/Main、agent-server | 动态端点、会话鉴权、来源限制和最小暴露 |
| 会话列表、加载、删除和标题更新 | agent-server、Desktop API/UI | 通用会话体验 |
| 流式事件、停止、重连和恢复 | Runtime、agent-server、Host | 通用 Agent turn 能力 |
| Desktop 打包和发布基础设施 | Desktop、Pixi、CI | 安装包、sidecar 资源和签名入口 |
| 通用附件输入和文件安全边界 | Runtime、Host、Documents Foundation | 多类 Agent App 共用 |
| Tasks、Calendar、Scheduler、Notifications API | Foundation、agent-server、Host | 厂商中立的基础能力 |
| 全局热键、托盘和快速捕获 | Desktop Host | 通用平台能力 |
| 可选数据加密、备份和迁移契约 | Storage、Host | 通用本地数据安全能力 |
| Gmail、Outlook、CalDAV 等适配器 | 独立 Connector package | Provider 行为不进入产品代码 |

### 7.2 保留在产品 fork 的能力

- 产品名称、图标、字体、色彩和视觉语言。
- Chat、Today、Action Center、Memory、Connections 和 Settings 的产品级信息架构。
- 每日简报、邮件跟进、承诺提取、会议准备和行动清单。
- 产品排序、优先级和提示策略。
- One Timeline 是否保留以及具体呈现方式。
- 私人秘书专属 Prompt、私有 Skills 和组合工作流。
- 产品 onboarding、空状态、错误文案和升级引导。
- 旧 SecondLoop 数据导入工具。

### 7.3 从产品能力晋升到上游的条件

产品能力只有在满足以下条件时才提炼为上游能力：

- 至少能描述两个不同类型 Agent App 的复用场景。
- 可以定义与产品 UI 无关的稳定输入、输出和失败语义。
- 权限、审批、幂等和数据边界能够由 Runtime 或 Host 确定性执行。
- 有独立 package、Connector 或 Host capability 的合理归属。
- 可以使用 fake/local backing 构建确定性测试。

## 8. 目标 Desktop 架构

```text
React Renderer
  产品路由、交互状态、展示
        |
        v
Electron Preload / Main
  可信 IPC、模型凭据、sidecar supervisor、系统能力
        |
        v
Local Rust sidecar
  Agent API、会话、审批、后台任务、Foundation API
        |
        v
Agent Runtime / Model Gateway / Skills / Connectors / SQLite
```

本地 sidecar 属于 Desktop 产品运行时，不属于本计划排除的云端 Server。允许修改 `crates/agent-server` 来实现本地 Host 所需的通用接口、安全传输和后台任务。

sidecar 必须满足：

- 由 Electron 启动和终止，不要求用户手工启动终端进程。
- 不依赖固定的全局端口。
- Renderer 不持有长期主密钥或邮箱凭据。
- 非本 App 进程不能调用高权限接口。
- 启动超时、异常退出和重复启动有确定性处理。
- App 退出后不留下僵尸进程。
- 数据目录、缓存目录、日志目录和 App 身份明确隔离。
- 错误日志自动移除 API Key、邮箱密码、token 和邮件正文。

## 9. 产品路由和设计评审范围

在开始产品 UI 实现前，必须评审每个主要视图的桌面与窄窗口设计。

### 9.1 Chat

- 真实会话列表、创建、切换、搜索、删除和恢复。
- 流式文本、reasoning、tool call、tool result 和审批状态。
- 多行输入、发送、停止、重试和错误恢复。
- 模型未配置、sidecar 不可用、网络不可用和会话冲突状态。

### 9.2 Today

- 今日重点、需要回复、等待批准、已承诺事项和提醒。
- 每项内容必须显示来源和权威状态。
- 不存在 Calendar、Tasks 或 Mail 数据时明确显示能力缺口。
- 不把推断事项伪装成已经创建的任务或提醒。

### 9.3 Action Center

- 等待批准、执行中、成功、失败、取消和 `uncertain`。
- 展示收件人、资源目标、风险摘要、不可变预览和幂等状态。
- 批准与拒绝操作提供清晰反馈，不允许重复执行。

### 9.4 Memory

- 搜索、详情、来源、置信度、敏感度、保留策略、导出和遗忘。
- 区分 proposal、committed 和 tombstoned。
- 遗忘操作需要确认，并明确审计残留范围。

### 9.5 Connections

- 模型配置状态。
- Mail 账号状态和连接诊断。
- 后续 Calendar、Contacts 和其他 Connector 的统一入口。
- secret 只显示是否已配置，不回显明文。

### 9.6 Settings

- 外观、语言、模型、隐私、数据、通知和开发者功能。
- 开发者工具只在明确的开发模式或策略授权下显示。
- 产品构建不得暴露无关的框架调试入口。

### 9.7 视口和状态门禁

至少检查以下视口：

- Desktop：`1440 × 900`。
- Compact Desktop：`1280 × 800`。
- Narrow Window：`390 × 844`。

每个主要视图至少覆盖：

- 加载中。
- 空数据。
- 正常数据。
- 部分能力不可用。
- 可恢复错误。
- 不可恢复错误。
- 运行中。
- 等待批准。
- 成功。
- 失败。
- 结果不确定。

## 10. 阶段计划

### M0：仓库与发布合法性准备

预计：2–4 人日。

工作内容：

- 确认采用保留现有 GitHub 仓库对象的独立下游模式。
- 为旧 SecondLoop 创建不可变 legacy tag、归档分支和远程备份。
- 保持 `origin` 指向现有 SecondLoop，添加 `upstream`，并在归档完成后将产品主线切换到 AgentWeave 历史。
- 验证 SecondLoop 的 GitHub 仓库 ID、Greptile GitHub App check 和仓库级集成在主线切换后仍然存在。
- 在上游补充 `LICENSE-APACHE`、`LICENSE-MIT`、根许可证说明和第三方资产 NOTICE。
- 核对 Cargo、npm、字体、主题、Skills 和其他可分发资产的许可证。

退出条件：

- 旧仓库可以从远程和 tag 恢复。
- 产品仓库确认是基于 AgentWeave 的独立下游历史，而不是两段历史的强行合并。
- `dale0525/SecondLoop` 的 GitHub 仓库对象和仓库 ID 未变化。
- 上游许可证 PR 被合并。
- 下游发布所需的许可证文件可以由构建产物携带。

### M1：上游 Desktop Consumer Host 基线

预计：25–38 人日。

工作内容：

- App Manifest 的 Host feature discovery 和发布模式控制。
- Renderer 获取可信 App 身份、品牌、能力和策略快照。
- Electron sidecar supervisor。
- 动态端点、短期鉴权、健康检查和安全关闭。
- 会话列表、加载、删除和标题接口接入。
- 流式事件、停止生成和连接恢复。
- macOS Desktop 打包骨架和 sidecar 资源布局。
- Host、Runtime、Desktop 和打包脚本测试。

退出条件：

- `examples/minimal-agent` 和 `examples/secretary-agent` 均能由打包后的 Desktop Host 启动。
- 用户无需手工运行 `pixi run server`。
- 固定 `127.0.0.1:49321` 不再是生产依赖。
- 会话重启后可以恢复。
- 流式 turn 可以停止且不会留下不一致记录。
- sidecar 崩溃会显示可恢复状态，不会静默丢失请求。
- 上游合并并发布一个供产品固定的版本。

### M2：产品定义与界面骨架

预计：12–18 人日。

工作内容：

- 创建正式的私人秘书 App Definition，不继续把示例目录作为产品根目录。
- 定义产品 App ID、package ID、品牌、语言、主题、字体和发布能力集合。
- 完成 Chat、Today、Action Center、Memory、Connections 和 Settings 的设计评审。
- 建立产品导航、响应式 shell、共享状态和错误边界。
- 隐藏未授权的 Developer Tools 和 Owner Skills 入口。
- 建立产品视觉回归截图基线。

退出条件：

- 所有主要路由在三个目标视口通过设计评审。
- 路由结构、组件状态和视觉验收标准被记录。
- 产品构建只显示 Manifest 和策略允许的能力。
- 无真实模型或邮箱时可以使用 fake/local 数据完成 UI 验收。

### M3：Mail + Memory 垂直切片

预计：17–25 人日。

工作内容：

- 产品化真实会话历史和聊天状态。
- 接入 Memory 查询、来源、导出和遗忘。
- 接入 Mail 账号状态、读取、草稿和权威发送预览。
- 接入 Action Center 的批准、拒绝、执行和对账状态。
- 完善私人秘书 system prompt、developer instructions 和私有 routines Skill。
- 覆盖“记住偏好→读取邮件→创建草稿→批准→只发送一次”的端到端流程。

退出条件：

- fake/local 环境下端到端流程稳定通过。
- IMAP/SMTP 专用测试账号的 opt-in 验证通过。
- 外部邮件内容不能改变系统指令、收件人和审批要求。
- `uncertain` 发送不会使用新幂等键盲目重试。
- 所有目标路由通过响应式和视觉验收。

### M4：Tasks、Scheduler 与 Today

预计：额外 15–25 人日。

M4 是首个 Desktop MVP 之后的可选能力增强。它可以与 M5 并行，也可以推迟到首个 Desktop Beta 之后，不作为 Mail + Memory 垂直切片和基础 Beta 加固的阻塞项。

工作内容：

- 在上游补齐 Tasks、Scheduler、Notifications 的通用 Host/API 接口。
- 为本地任务和计划执行提供持久化 backing。
- 在产品层组合 Today、承诺提取、跟进复盘和每日简报。
- 清晰区分 Agent 建议、用户确认的任务和已经调度的自动化。

退出条件：

- 今日简报只引用权威来源。
- Scheduler 重启后保持幂等和正确 misfire 行为。
- 通知投递失败可以恢复，不会重复执行外部操作。
- 上游 Foundation 变更先合并，产品层不保留平行实现。

### M5：Desktop Beta 加固

预计：额外 25–40 人日。

工作内容：

- 普通用户可完成的模型和邮箱 onboarding。
- 安装、升级、回滚、签名和发布流程。
- 数据备份、恢复和可选加密策略。
- 通用附件输入和受控文件读取。
- 可访问性、性能、日志、诊断和崩溃恢复。
- 发布前完整视觉 QA 和手工测试。

退出条件：

- 新安装、覆盖升级、异常退出和数据恢复场景通过。
- 发布构建不包含开发 API、测试凭据和未声明能力。
- sidecar、Renderer 和外部 Connector 的信任边界通过安全复核。
- macOS 发布产物可重复构建并携带完整许可证。

## 11. 开发量汇总

| 目标 | 预计开发量 | 两名工程师预计日历时间 |
| --- | ---: | ---: |
| 可演示垂直切片：Chat + Mail + Memory + Approval | 40–55 人日 | 5–7 周 |
| 可用 Desktop 私人秘书 MVP | 56–85 人日 | 7–11 周 |
| 加入 Tasks、Scheduler 和 Today 自动简报 | 额外 15–25 人日 | 额外 2–4 周 |
| Desktop 生产 Beta | 累计 90–130 人日 | 约 12–18 周 |
| Android 产品化 | 额外 25–40 人日 | 取决于与 Desktop 的并行程度 |

推荐人员拆分：

- 上游工程线：Rust Runtime、agent-server、Electron Main/Preload、sidecar、安全和发布基础设施。
- 产品工程线：React UI、产品路由、视觉设计、Prompt、Skills 和端到端产品场景。

上游接口尚未冻结时，产品工程线先完成设计、fixture、状态模型和契约测试，不在产品层复制通用 Runtime 实现。

## 12. 首批工作项

### 上游工作项

| ID | 工作项 | 阶段 | 主要依赖 |
| --- | --- | --- | --- |
| U-001 | 补齐双许可证和 NOTICE | M0 | 无 |
| U-002 | Manifest Host feature discovery | M1 | U-001 |
| U-003 | App 身份、能力和策略的可信 Renderer bootstrap | M1 | U-002 |
| U-004 | Electron sidecar supervisor | M1 | U-003 |
| U-005 | sidecar 动态端点与鉴权 | M1 | U-004 |
| U-006 | 会话列表、恢复、删除和标题更新 | M1 | U-003 |
| U-007 | 流式事件、停止和恢复 | M1 | U-005、U-006 |
| U-008 | macOS Desktop 打包骨架 | M1 | U-004、U-005 |
| U-009 | Tasks Foundation 的 Host/API 接口 | M4 | M3 |
| U-010 | Scheduler 与 Notifications Host 接口 | M4 | U-009 |
| U-011 | 通用附件输入契约 | M5 | M3 |
| U-012 | 可选数据加密和备份契约 | M5 | M3 |

### 产品工作项

| ID | 工作项 | 阶段 | 上游依赖 |
| --- | --- | --- | --- |
| P-001 | 正式私人秘书 App Definition | M2 | U-002、U-003 |
| P-002 | 路由和多视口设计评审 | M2 | 无 |
| P-003 | 产品导航和响应式 shell | M2 | U-003 |
| P-004 | 产品化 Chat 和会话历史 | M3 | U-006、U-007 |
| P-005 | Memory ledger | M3 | U-003 |
| P-006 | Connections 和 Mail 状态 | M3 | U-003 |
| P-007 | Action Center | M3 | U-003 |
| P-008 | 私人秘书 Prompt 和 routines Skill | M3 | P-001 |
| P-009 | Today 和任务工作流 | M4 | U-009、U-010 |
| P-010 | Desktop Beta 视觉和发布 QA | M5 | U-008、U-011、U-012 |

## 13. 测试和质量门禁

### 13.1 上游变更最低门禁

根据改动范围运行：

```bash
pixi run validate-agent-assets
pixi run test-dev-script
pixi run source-lines
pixi run npm --prefix apps/desktop test
pixi run npm --prefix apps/desktop exec tsc -- --noEmit -p apps/desktop/tsconfig.vitest.json
pixi run cargo fmt --all --check
pixi run cargo clippy --workspace --all-targets -- -D warnings
pixi run cargo test --workspace
```

涉及 Android、跨 Host 契约或正式发布时，再运行完整 `pixi run skill-lifecycle-check`。若本地 Android 环境不可用，必须明确记录未运行项和原因。

### 13.2 产品变更最低门禁

- TypeScript 类型检查和 Desktop 单元测试。
- App Manifest、Prompt、Skills、locale 和 package lock 校验。
- fake/local backing 的产品端到端测试。
- Desktop `1440 × 900`、`1280 × 800` 和 `390 × 844` 截图。
- 使用 Browser 或 Computer Use 完成手工测试。
- 检查布局、间距、字体层级、颜色、状态、响应式行为和文本截断。
- 记录动态数据、字体或平台限制导致的已知视觉偏差。

### 13.3 sidecar 专项测试

- 正常启动、重复启动和超时。
- 动态端点分配和未授权访问拒绝。
- Electron 正常退出和强制退出。
- sidecar 崩溃、重启和连续崩溃熔断。
- 数据目录隔离和并发 App 实例。
- 日志脱敏。
- 运行中的 turn 停止与恢复。
- 数据库迁移失败时的回滚和只读诊断。

## 14. 安全要求

- Prompt 和 Skill 指令不得作为权限或安全边界。
- 外部副作用必须经过 Runtime 的审批、幂等和审计机制。
- Renderer 不得直接读取 API Key、邮箱密码、OAuth token 或 sidecar 主密钥。
- 模型 API Key 使用操作系统安全存储；Connector secret 使用 Credential Vault。
- 邮件正文、附件、网页和外部文档一律视为不可信输入。
- sidecar 生产接口不允许依赖开放 CORS 和固定无鉴权端口。
- `uncertain` 外部操作必须进入对账，不得自动更换幂等键重试。
- 日志、fixture、截图和错误报告不得包含真实凭据或私人邮件内容。
- Desktop Beta 前必须决定会话、Memory 和任务数据是否需要整体加密，以及对应迁移和恢复策略。

## 15. 发布和版本策略

- 产品只依赖已被上游合并的 AgentWeave 版本或明确的上游 commit。
- App Manifest 固定兼容范围，Foundation packages 使用锁文件固定版本和内容哈希。
- 上游公开契约发生破坏性变化时提升 schema 或语义版本，不静默修改行为。
- 上游版本升级先进入独立集成分支，通过组合测试后再进入产品 `main`。
- 正式产品构建不依赖 `examples/secretary-agent` 路径。
- 发布产物包含 App lock、Skill bundle lock、许可证、NOTICE 和构建版本信息。
- 首期仅发布 local-first Desktop，不宣称提供云同步、托管模型或跨设备一致性。

## 16. 旧数据与迁移

旧 SecondLoop 数据迁移不进入 Desktop MVP，但必须保留迁移可能性：

- 旧仓库和数据格式文档保持可访问。
- 不在旧 Vault 上原地升级。
- 后续迁移工具采用只读导出、校验、预览和显式导入流程。
- 迁移失败不能损坏源数据。
- 附件、标签、任务、时间线和 Memory 的映射规则单独评审。
- 加密数据只能在用户授权和正确解锁后读取。

## 17. 主要风险和缓解措施

| 风险 | 影响 | 缓解措施 |
| --- | --- | --- |
| AgentWeave 仍处于 `0.1.x` | 契约变更和返工 | 上游先稳定 Consumer Host，发布可固定版本 |
| 产品提交混入上游 PR | 上游难以评审和采纳 | 上游分支始终从 `upstream/main` 创建并直接推送到上游仓库 |
| 删除并重建 SecondLoop 仓库 | 丢失 Greptile 免费名额和仓库级集成 | 保留仓库 ID，只切换主线并归档旧历史 |
| 等待上游合并阻塞产品开发 | 关键路径延长 | 使用临时 integration 分支，产品主线只接收权威合并实现 |
| sidecar 固定端口和无鉴权访问 | 本地越权风险 | 动态端点、短期鉴权、可信 IPC 和来源限制 |
| Calendar、Tasks 等只有 fake 实现 | 产品能力不完整 | Mail + Memory 先形成可靠闭环，再扩展 Provider |
| Desktop 与 Android UI 不共享 | 移动端成本较高 | 先稳定跨 Host 契约，再启动 Android 产品化 |
| SQLite 产品数据未整体加密 | 隐私定位受限 | Beta 前完成威胁模型和加密/备份决策 |
| 旧 SecondLoop 范围过大 | MVP 失控 | 坚持明确非目标，不追求首期功能对等 |

## 18. Desktop MVP 完成定义

同时满足以下条件才视为 Desktop MVP 完成：

- 产品仓库已切换为 AgentWeave 独立下游，旧 SecondLoop 已安全归档。
- 所有通用能力来自上游已合并提交，不存在永久下游核心补丁。
- Electron 自动管理本地 Rust sidecar。
- 用户可以配置 BYOK 模型并完成真实多轮对话。
- 会话历史在 App 重启后可恢复。
- 流式 turn 可以停止、失败和重试。
- Memory 查询、来源、导出和遗忘可用。
- Mail 读取、草稿、预览、审批和幂等发送闭环可用。
- Action Center 正确显示全部终态和 `uncertain`。
- 六个主要视图在三个目标视口通过视觉评审。
- 默认测试不需要真实账号，opt-in live tests 使用专用测试账号。
- 相关上游和产品质量门禁全部通过。
- macOS 构建产物携带许可证并可以在干净环境启动。

## 19. 立即下一步

1. 评审并确认本文档。
2. 确认独立下游仓库模式、现有 SecondLoop 仓库保留策略和最终产品名称。
3. 制定旧 SecondLoop 的归档与恢复检查表。
4. 在当前项目创建第一个上游工作分支，提交许可证和 NOTICE PR。
5. 为 App Manifest Host feature discovery 编写独立设计说明和上游 PR 范围。
6. 为 Desktop sidecar supervisor 编写威胁模型、进程协议和验收测试清单。
7. 评审六个产品路由及三个目标视口，冻结 Desktop MVP 的视觉验收标准。
