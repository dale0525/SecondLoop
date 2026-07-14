# 开发 Agent App

[English](./DEVELOPING_AGENT_APPS.md) | 简体中文

AgentWeave 的开发模型是“框架 + App 定义 + 可选扩展包”。一个下游产品应主要通过 `agent-app.json`、Prompt、Skills、Connectors 和品牌界面形成差异，而不是修改 `crates/agent-runtime` 的 turn loop。

本文面向使用 AgentWeave 构建下游应用的开发者。如果你还没有运行过仓库，请先完成 [README 的快速开始](./README.zh-CN.md#5-分钟快速开始)；如果你要修改框架、宿主或 Foundation package，请同时阅读 [贡献指南](./CONTRIBUTING.zh-CN.md)。以下命令均从 AgentWeave 仓库根目录执行。

开始前先选择一个起点：

- `templates/agent-app`：脚手架使用的最小、默认拒绝权限模板。
- `examples/minimal-agent`：只启用 Filesystem 的最小消费者应用。
- `examples/secretary-agent`：组合 Mail、Memory 和应用私有 Skill 的跨平台参考应用。

## 1. 创建应用

在仓库根目录执行：

```bash
pixi run scaffold-agent-app -- \
  --name "My Agent" \
  --app-id com.example.my-agent \
  --output output/my-agent
```

脚手架会创建：

```text
output/my-agent/
  agent-app.json
  prompts/system.md
  prompts/developer.md
  locales/en.json
  locales/zh-CN.json
  themes/
  fonts/
  packages/
```

模板默认拒绝网络和后台执行，不生成凭据文件，也不会启用 Owner Skill 管理。先保持最小权限，再按实际包依赖增加 capability、runtime tool 和 connector 声明。

## 2. 定义 App 行为

`agent-app.json` 是跨 Desktop、Android 和 Server 的版本化应用契约。它定义：

- App 与 package 身份、版本和支持平台；
- Runtime 兼容范围；
- 启用的 Skill packages；
- 所需 capabilities、runtime tools 和 connectors；
- 外部副作用、网络、后台执行、Memory 和 Skill 管理策略；
- 品牌信息、可打包语言、主题、字体目录及 system/developer instruction 资源。

System prompt 可以定义产品人格和领域行为，但不能授予权限。发送邮件、修改日历、持久化敏感 Memory 等操作仍由 Runtime、Host 和 Connector 的确定性策略约束。

修改后执行：

```bash
pixi run scaffold-agent-app -- --validate output/my-agent
```

校验会拒绝未来 schema、未知字段、路径逃逸、符号链接、缺失 package、平台不兼容、未声明依赖和嵌入 Manifest 的 secret。

### 2.1 发现可信 Host 能力

App Manifest 完成加载并通过当前 Runtime inventory 校验后，`ResolvedAgentApp::host_discovery()` 会返回一个带版本、可序列化的快照，供 Host 决定功能入口。快照包含可信 App 身份与公开品牌信息、有效平台和 Runtime 版本、Manifest 内容哈希、声明的 `features`、已经校验的 package/capability/runtime tool/Connector 需求，以及 App policies。

Host 使用该快照判断 Memory、账号、审批或 Skill 管理等可选界面是否可达。在 discovery 成功前，Host 必须 fail closed，只暴露最小安全界面。未知 feature identifier 会保留在快照中以支持向前兼容，但 Host 必须忽略自己不理解的 identifier。

Discovery 不是权限授予。`features` 数组可以描述产品行为和界面呈现，但访问与外部副作用仍以 capabilities、policies、Actor grants 和 Runtime 状态为准。Host 不得根据 Prompt 文本、package 目录名、品牌信息或未经验证的 Renderer 配置推断权限。

Discovery wire contract 使用独立 schema version，使 Host 可以拒绝不兼容的未来快照，同时不削弱 Runtime compatibility 校验。Manifest hash 用于确认界面决策与当前 App instructions 来自同一个已解析 package。

### 2.2 选择主题与字体

Desktop Host 读取 `agent-app.json` 的可选 `appearance` 配置。`themes.builtins` 决定最终 App 中可见的内置主题，`defaultTheme` 决定首次启动时使用的主题。新脚手架预置与当前 VS Code 1.128 相同的 19 个颜色主题，并默认使用 `vscode.dark-2026`。

只保留深色与浅色默认主题时，可以写成：

```json
{
  "appearance": {
    "defaultTheme": "vscode.dark-2026",
    "themes": {
      "builtins": [
        "vscode.dark-2026",
        "vscode.light-2026"
      ],
      "custom": []
    }
  }
}
```

自定义主题放在 App 根目录的 `themes/`。文件使用 VS Code color theme 的 JSON 或 JSONC 格式，可以通过 `include` 继承同目录中的另一个主题。随后在 `themes.custom` 中声明稳定 ID、可选显示名和相对路径：

```json
{
  "id": "com.example.brand-dark",
  "label": "Brand Dark",
  "path": "themes/brand-dark-color-theme.jsonc"
}
```

Desktop 构建会把 VS Code workbench colors 映射为聊天、设置、表单、边框和状态颜色。语法 token colors 可以继续保留在主题文件中，但不会改变聊天正文的语法高亮。

字体放在 App 根目录的 `fonts/`，不需要写入 Manifest。文件名决定用途：`ui.woff2` 用于界面正文，`display.woff2` 用于标题，`mono.woff2` 用于代码。也可以添加字重和斜体后缀，例如 `ui-600.woff2` 或 `ui-400-italic.woff2`。Desktop 支持 WOFF2、WOFF、TTF 和 OTF，并优先使用 WOFF2；Android 通过平台 `Typeface` 加载 TTF/OTF，遇到 WOFF/WOFF2 时会安全回退到系统字体。

本地开发和正式构建都应提供相同的 App 根目录：

```bash
AGENTWEAVE_APP_ROOT=output/my-agent pixi run dev
AGENTWEAVE_APP_ROOT=output/my-agent pixi run npm --prefix apps/desktop run build
```

主题与字体会进入 App 内容哈希。修改任何相关文件后，都应重新生成并验证发布产物。

### 2.3 管理界面语言

`localization` 声明 App 可提供的界面语言、默认语言和对应的 UTF-8 JSON 词典。词典使用稳定的扁平 key，便于审阅、合并和交给翻译工具处理：

```json
{
  "localization": {
    "defaultLocale": "en",
    "locales": [
      {
        "id": "en",
        "label": "English",
        "resource": "locales/en.json"
      },
      {
        "id": "zh-CN",
        "label": "简体中文",
        "resource": "locales/zh-CN.json"
      }
    ]
  }
}
```

每个词典必须包含相同的 key，并保留相同的 `{placeholder}`。Host 自带英文和简体中文基础文案，App 词典可以覆盖 `app.name`、`app.tagline` 等 key；未覆盖的 Host 文案会回退到对应语言，再回退到英文。运行时只向用户显示最终发布包声明的语言，并持久化用户选择。

`pixi run scaffold-agent-app -- --validate <app>` 会同时检查 locale ID、资源路径、JSON 编码、key 对齐和 placeholder 对齐。新增语言时，先复制默认词典，逐项翻译，再执行校验；不要在组件中新增硬编码的用户可见文案。

## 3. 添加自定义 Skill

App 私有 Skill 放在 `packages/<skill-name>/`。每个 package 至少包含：

```text
packages/my-workflow/
  agentweave.json
  SKILL.md
  agents/openai.yaml
```

Instruction Skill 可以按需增加 `references/`、`scripts/` 和 `assets/`。资源读取绑定当前 turn 捕获的 package revision；路径逃逸、符号链接和越界大小会被拒绝。脚本执行必须走受控 helper/sandbox，不得通过 Skill 指令绕过 Host 权限。

创建或更新 Skill 时遵循 `skill-creator` 的渐进披露原则：触发条件写在 frontmatter `description`，`SKILL.md` 保持精炼，详细材料放入按需读取的 references。使用 runtime 的 package 校验器检查 App 私有 Skills：

```bash
pixi run cargo run -p agent-server --bin check-skills -- \
  --root output/my-agent/packages
```

随后在 `agent-app.json` 的 `requires.packages` 中启用该 package，并完整声明它要求的 capabilities、runtime tools 和 connectors。

## 4. 选择 Foundation Skills

机器可读目录位于 `catalog/foundation-skills.json`。所有 Foundation Skills 都是可选、可禁用、可替换的 package。

- Stable foundation：Memory，以及既有 Filesystem 基础能力。
- Preview foundation：Mail、Calendar、Tasks、Web Research、Documents、Contacts、Notifications、Notes、Messaging、Scheduler。
- Developer-only：Skill Creator 等作者工具，不会自动进入消费者 App。

Mail 负责通用邮件工作流，具体账号访问由 Fake、IMAP/SMTP 或后续 vendor adapter 提供。Memory 负责 Agent 可审计上下文；Notes 是用户明确拥有的内容，两者不能混用。Task 保存工作状态，Scheduler 负责触发，Notification 负责投递结果。

## 5. 本地运行

Server：

```bash
AGENTWEAVE_APP_ROOT=output/my-agent pixi run server
```

Desktop 开发模式：

```bash
AGENTWEAVE_APP_ROOT=output/my-agent pixi run dev
```

Android 默认打包 `examples/secretary-agent`，同时写入冻结的 App lock 和 Skill bundle lock。要更换 Android 参考 App，应修改构建时 App 输入，而不是在 Runtime 中增加领域分支。

## 6. 使用 fake 实现做测试

默认测试不得依赖外部账号。Mail、Memory、Calendar、Tasks、Web Research、Documents、Contacts、Notes 和 Messaging 均提供 deterministic fake 或 local backing，用于覆盖分页、冲突、审批、幂等、隔离和错误分支。

Secretary 参考应用位于 `examples/secretary-agent`。它用本地 Fake Mail 和 SQLite Memory 验证“记住偏好、读取邮件、创建草稿、审批并只发送一次”的组合路径。

## 7. 生成冻结发布产物

开发模式可以读取可变源码目录；发布模式应使用冻结产物：

```bash
pixi run package-agent-app -- \
  --input output/my-agent \
  --output output/my-agent-release \
  --runtime-version 0.1.0 \
  --locales en,zh-CN \
  --default-locale en
```

`--locales` 从 Manifest 已声明的词典中选择本次发布实际携带的语言。未选择的词典不会复制到 release；若原默认语言被排除，打包器会使用列表中的第一种语言，也可以用 `--default-locale` 明确指定。源码目录不会被改写。

Android 打包沿用相同选择规则。构建下游 App 时设置 `AGENTWEAVE_APP_ROOT`，并可用 `AGENTWEAVE_APP_LOCALES` 与 `AGENTWEAVE_APP_DEFAULT_LOCALE` 指定 APK 中的语言清单：

```bash
AGENTWEAVE_APP_ROOT=output/my-agent \
AGENTWEAVE_APP_LOCALES=en,zh-CN \
AGENTWEAVE_APP_DEFAULT_LOCALE=en \
pixi run android-assemble
```

Release artifact 包含：

```text
output/my-agent-release/
  agent-app.lock.json
  app/
  packages/
```

Lock 固定 App 身份、Runtime 版本、平台、语言清单、每个 package 的版本与 SHA-256、capabilities、runtime tools，以及 host-provided connector/provider 要求。产物不会记录本机源码绝对路径，并拒绝 `.env`、私钥和 credential/secret JSON 文件。

发布或启动前再次验证：

```bash
pixi run package-agent-app -- --verify output/my-agent-release
```

任何 Prompt、Skill 或 lock 篡改都会导致验证失败。

## 8. 最低质量门禁

```bash
pixi run cargo fmt --all --check
pixi run cargo clippy --workspace --all-targets -- -D warnings
pixi run cargo test --workspace
pixi run check-skills
pixi run test-dev-script
pixi run npm --prefix apps/desktop test
pixi run npm --prefix apps/desktop exec tsc -- --noEmit -p apps/desktop/tsconfig.vitest.json
pixi run mobile-mvp-check
pixi run source-lines
```

外部服务的 live tests 必须保持 opt-in。默认门禁只使用本地 fake server 和无凭据测试。

## 9. 常见问题

### Desktop 页面提示依赖缺失

首次拉取或 `package-lock.json` 更新后，重新安装 Desktop 依赖：

```bash
pixi run npm --prefix apps/desktop ci
```

### Server 无法绑定端口

本地 Server 固定监听 `127.0.0.1:49321`，Desktop 开发页面使用 `127.0.0.1:5173`。先停止占用端口的旧开发进程，再重新运行 `pixi run dev`。

### 页面能打开但无法发送消息

启动链路不要求模型，但对话需要可访问的模型端点。在设置页核对 Base URL、端点类型和模型名，并先运行连接测试。Responses、Chat Completions 和 Completion 是不同协议，端点类型必须与服务实际支持的协议一致。

### Manifest 校验失败

从第一条错误开始修复。校验器会拒绝未知字段、未来 schema、路径逃逸、符号链接、缺失 package、平台不兼容、未声明依赖和 secret。不要通过放宽校验来绕过应用契约；应修正 Manifest 或 package 声明。

### Android 构建找不到 SDK 或 NDK

Android 任务默认使用 `.tool/android-sdk`，Rust native 构建默认查找 `.tool/android-sdk/ndk/28.2.13676358`。完整环境要求和分阶段检查命令见 [贡献指南的 Android 环境](./CONTRIBUTING.zh-CN.md#android-环境)。
