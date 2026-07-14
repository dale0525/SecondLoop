# 为 AgentWeave 贡献

[English](./CONTRIBUTING.md) | 简体中文

感谢你愿意改进 AgentWeave。本指南面向修改框架仓库本身的贡献者；如果你只想基于框架创建自己的产品，请先阅读 [开发 Agent App](./DEVELOPING_AGENT_APPS.zh-CN.md)。

AgentWeave 是 Agent App Framework，而不是固定领域的最终 Agent 产品。一次改动是否应该进入核心，通常比代码具体怎么写更重要。

## 开始前先判断改动归属

| 改动类型 | 优先位置 |
| --- | --- |
| 多类 Agent App 都需要的会话、执行、存储或安全机制 | `crates/agent-runtime/` |
| 模型协议和 Provider 适配 | `crates/model-gateway/` |
| HTTP API、开发诊断、后台 worker | `crates/agent-server/` |
| Android/Rust 桥接 | `crates/mobile-ffi/` |
| Desktop 或 Android 平台交互 | `apps/desktop/`、`apps/android/` |
| 厂商中立、可替换的基础工作流 | 独立 Foundation Skill/Connector package |
| 某个产品的人格、SOP、品牌或领域页面 | 下游 App 或 `examples/` |
| 验证框架组合方式的最小实现 | `examples/` 或测试夹具 |

以下内容不应仅靠 Prompt 约束：凭据访问、网络权限、持久写入、外部副作用、审批、幂等、租户隔离和审计。它们需要 runtime、Host Tool 或 Connector 的确定性实现与测试。

如果一个设计只解决单个示例的特殊路径，请先尝试把它表达为稳定扩展契约或可选 package，不要在 turn loop 中加入领域分支。

## 初始化开发环境

### 前置条件

- Git。
- [pixi](https://pixi.prefix.dev/latest/)。
- macOS Apple Silicon、macOS Intel 或 Linux x86_64；这是当前 Pixi workspace 声明的平台集合。
- 只有修改或验证 Android 时，才需要额外准备项目本地 Android SDK/NDK。

仓库使用 Pixi 固定 Rust、Node.js、Python、OpenJDK 和本地开发工具。请不要为本项目系统级安装或升级这些依赖。

### 首次安装

```bash
git clone https://github.com/dale0525/agentweave.git
cd agentweave

pixi install
pixi run npm --prefix apps/desktop ci
pixi run validate-agent-assets
pixi run test-dev-script
```

可选安装仓库自带的 pre-commit hook：

```bash
pixi run install-hooks
```

该 hook 当前只运行 `pixi run check-skills`。它能尽早发现 Skill package 问题，但不能代替提交前的完整测试。

本地工具、SDK、缓存和临时产物放在 `.tool/`、`.pixi/`、`target/`、`output/` 等已忽略目录。不要把凭据、数据库、构建产物或依赖目录提交到仓库。

## 本地运行

运行最小示例：

```bash
AGENTWEAVE_APP_ROOT=examples/minimal-agent pixi run dev
```

开发页面位于 <http://127.0.0.1:5173>，Agent Server 位于 <http://127.0.0.1:49321>。可以在另一个终端检查：

```bash
curl http://127.0.0.1:49321/health
```

开发服务器会生成本地 SQLite 数据。结束验证后可以保留它继续调试；若确认不再需要，也只能删除本次任务明确创建的数据库及其 `-shm`、`-wal` 文件，不要执行无差别清理命令。

## 推荐工作流

1. 阅读根目录 [AGENTS.md](./AGENTS.md) 和与你改动最接近的现有实现、测试与 package manifest。
2. 用 `git status --short` 确认工作区状态，保留所有与当前任务无关的用户改动。
3. 先定义可观察行为、安全边界和失败恢复方式，再改实现。
4. 为新行为添加最小且确定性的测试；默认使用 fake/local backing，不依赖真实账号和网络服务。
5. 运行与改动范围对应的快速检查，修复后再运行组合门禁。
6. 更新 README、示例、Manifest 或契约文档，使文档和实际命令保持一致。
7. 提交前检查 diff 中是否包含 secret、绝对用户路径、生成物或无关格式化改动。

## 编码约定

- 代码、标识符和代码注释使用英文；面向特定语言受众的 README、Prompt 和 i18n 文件可以使用对应语言。
- 所有文本文件使用 UTF-8。涉及中文或其他非 ASCII 字符时，提交前检查实际渲染和 diff，避免编码损坏。
- Rust 使用 workspace 的 2024 edition，并通过 `rustfmt` 与无警告 `clippy`。
- TypeScript/React、Node 脚本、Kotlin、CSS 和配置应延续相邻文件的结构与命名，不做与目标无关的全文件重排。
- 代码类文件必须少于 1000 个物理行；长篇说明、契约、研究记录和其他纯文档不受该限制。
- 新依赖必须说明为何不能复用现有依赖，并通过项目内 Pixi/npm/Cargo/Gradle 配置管理。
- 不把 Prompt 当作权限检查，不把 API Key、密码、token 或真实用户数据写入源码、fixture、日志和文档示例。
- 外部副作用要有明确审批点、稳定幂等键、可审计状态和失败恢复测试。
- 新的跨平台能力要声明各 Host 的支持情况；不能实现的平台应明确拒绝或降级，不能静默假装成功。

## 测试矩阵

先运行最接近改动的检查，再根据影响面扩大范围。

| 改动范围 | 最低建议检查 |
| --- | --- |
| Rust runtime、server、gateway、FFI | `pixi run cargo fmt --all --check`、`pixi run cargo clippy --workspace --all-targets -- -D warnings`、`pixi run cargo test --workspace` |
| Desktop React/Electron | `pixi run npm --prefix apps/desktop test`、`pixi run npm --prefix apps/desktop exec tsc -- --noEmit -p apps/desktop/tsconfig.vitest.json` |
| Node 开发/打包脚本 | `pixi run test-dev-script` |
| Skill 或 Foundation Catalog | `pixi run check-skills`、`pixi run validate-agent-assets` |
| App Manifest、模板或示例 | `pixi run validate-agent-assets`、对应脚本测试 |
| 源文件拆分 | `pixi run source-lines` |
| Android/Kotlin/Rust FFI | `pixi run mobile-mvp-check` |
| 跨模块或发布前检查 | `pixi run skill-lifecycle-check` |

`pixi run skill-lifecycle-check` 依次检查 Rust 格式、Clippy、Rust workspace 测试、Desktop 测试与类型、Android native/unit/APK 构建，以及源码行数。它比普通单元测试耗时更长，并要求 Android 环境已经准备好。

外部服务 live tests 必须保持 opt-in。默认测试与 PR 复现步骤不能要求维护者提供模型、邮箱或其他私有凭据。

### Android 环境

Android 任务默认从 `.tool/android-sdk` 读取 SDK，并从 `.tool/android-sdk/ndk/28.2.13676358` 读取 NDK；也可以通过 `ANDROID_NDK_HOME` 指向项目内的兼容 NDK。当前应用配置为 `compileSdk 37`、`targetSdk 36`、`minSdk 31`。

请把 Android SDK、NDK、AVD 和 Gradle 缓存保留在当前项目的 `.tool/` 或其他已忽略项目目录，不要提交本地 SDK 配置和 APK。运行完整门禁前，可以分别定位失败阶段：

```bash
pixi run android-native
pixi run android-test
pixi run android-assemble
```

## Skill 与 Connector 改动

新增或修改 Skill 时：

- 让 frontmatter `description` 清楚表达触发条件。
- 保持 `SKILL.md` 聚焦工作流，把详细材料放入按需读取的 `references/`。
- 在 `agentweave.json` 中声明 package 类型、平台、能力和 runtime tool 依赖。
- 不在 Skill 中保存凭据，不通过脚本绕过 workspace、网络或审批策略。
- Foundation Skill 应有厂商中立契约、稳定工具语义和 deterministic fake/local 测试。
- 同步更新 `catalog/foundation-skills.json` 中的稳定性、依赖和替换契约。

Connector 负责认证、网络和外部系统访问。写操作应把“准备/预览”和“执行副作用”分开，并覆盖取消、超时、重试、重复请求与部分失败。

## 文档改动

- 根目录 README 只保留新开发者选择路径所需的信息；深入的 App 开发流程写入 `DEVELOPING_AGENT_APPS.md`。
- 命令必须能从仓库根目录复制执行，并说明是否需要模型、凭据、Android SDK 或网络。
- 新增顶层概念时，同时更新仓库结构、文档导航和最接近的示例。
- `docs/` 是本地工作记录目录，已被忽略，禁止强制加入 Git。需要随仓库发布的文档应放在根目录或对应 package/example 内。
- 文档中的示例 secret 使用明显的占位符或 opaque secret ID，不能使用看似可用的真实值。

## Commit 与 Pull Request

一个 Pull Request 应聚焦一个可以独立评审的目标。提交前请确认 Git 身份、diff 范围和测试结果：

```bash
git config user.name
git config user.email
git status --short
git diff --check
```

本仓库维护者使用 `Logic Tan <logictan89@gmail.com>` 作为仓库 Git 身份。外部贡献者可以使用自己的可验证身份，不应改写其他贡献者的作者信息。

除非贡献者另有明确声明，主动提交并被 AgentWeave 接收的贡献同时按 Apache License 2.0 和 MIT License 授权，由接收者任选其一，且不附加额外条款。只有在许可证兼容且所需 notice 得到保留时，才能提交第三方材料。

PR 描述至少应包含：

- 问题与目标，以及为什么该改动属于核心、可选 package 或示例。
- 用户可观察行为和不在本次范围内的内容。
- 权限、凭据、持久化、网络、审批和外部副作用影响。
- 已运行的精确测试命令及结果。
- UI 改动检查过的路由、Desktop/Mobile viewport、截图结论和已知偏差。
- Manifest、数据格式或公开契约是否需要迁移，以及回滚方式。

## 提交前清单

- [ ] 改动符合 Agent App Framework 的领域无关边界。
- [ ] 测试覆盖正常路径、拒绝路径和相关失败恢复。
- [ ] 默认测试不需要真实凭据或外部账号。
- [ ] Prompt 没有被当作权限或安全边界。
- [ ] 文档、示例、Manifest 和实际行为一致。
- [ ] 代码类文件未达到 1000 行上限。
- [ ] 没有提交 `docs/`、`.tool/`、数据库、缓存、构建产物或 secret。
- [ ] `git diff --check` 与相关质量门禁通过。

如果完整 Android 门禁因本地环境无法运行，请在 PR 中明确列出未运行的命令和原因，不要把“未运行”写成“通过”。
