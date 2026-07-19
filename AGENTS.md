# 项目定位

AgentWeave 是一个 **Agent App Framework**，不是面向某个固定领域的最终 Agent 产品。

本项目的目标是提供可复用的 Agent 应用基础设施，使其他开发者能够以尽量少的框架改动，通过替换或扩展以下内容构建自己的 Agent App：

- 自定义 system prompt、developer instructions 与 Agent 人格。
- 插入 instruction skill、runtime skill、host tool 或 connector。
- 配置模型、权限、审批、存储和运行策略。
- 按产品需要定制桌面端、移动端的品牌与交互界面。

一个基于 AgentWeave 构建的个人秘书、研究助手、内容工具或行业 Agent，应当主要由应用配置、prompt、skills、connectors 和产品界面定义，而不是通过复制并重写核心 runtime 实现。

## 架构边界

- 核心仓库保持领域无关。进入核心的能力应能被多类 Agent App 复用，例如会话上下文、持久执行、Skill/Plugin 生命周期、Connector Host、凭据管理、权限审批、事件协议、跨平台宿主和开发者工具。
- 邮件整理、日程规划、会议准备、旅行安排等领域行为应优先实现为可选 Skill、Connector、Plugin 或示例应用，不应硬编码到核心 runtime。
- 核心可以提供参考 Skill、参考 Connector 和端到端示例，但必须保持可替换、可禁用，并与框架协议解耦。
- 项目可以并应当发布面向多数 Agent App 都有价值的第一方 Foundation Skills。邮件管理和 Memory 管理属于基础能力，应由当前项目维护稳定的 Skill 接口、配套 Host Tools/Connectors、测试和安全策略，但仍须以独立 package 形式提供，允许下游应用替换、禁用或不打包。
- Foundation Skill 负责面向 Agent 的任务语义和工作流；登录、OAuth、凭据存储、网络访问、持久化、权限、审批和幂等必须由 Connector、Host Tool 或 runtime 基础设施实现，不得仅依赖 `SKILL.md` 中的行为约束。
- 新增基础设施时，优先设计稳定的扩展契约、SDK、测试夹具和脚手架，避免只满足某一个示例 Agent 的特殊路径。
- 下游应用应能覆盖 system prompt、启用的能力集合、默认策略和 UI，而无需 fork 或修改 Agent turn loop、Skill 生命周期和安全边界。
- 不得把 Prompt 约束当成权限或安全边界。外部副作用、凭据访问、持久写入和高风险操作必须由 runtime/host 的确定性机制约束。
- 评估第三方能力时，区分“可复用的框架协议或状态模型”“可选领域包”“特定产品实现”，避免把完整产品架构直接并入核心。

## Connector 数据语义与账号边界

- 权威列表读取不得静默过滤无法表示的记录，也不得把不兼容语义扁平化为近似值。共享模型无法忠实表达上游语义时，应明确 fail-closed，直到共享契约具备对应的一等表示。
- 缺失或空白的展示性字段，只有在不改变业务语义时才能在 Provider Adapter 边界规范化为 `null` 或稳定占位值。所有此类规范化必须有 Provider 级回归测试，并证明单条可表示记录不会导致整批权威读取失败。
- Connector 账号绑定必须按 capability 隔离。Mail、Calendar、Contacts 等账号 ID 不得相互 fallback、猜测或隐式复用；未绑定对应 capability 时应返回 missing/unavailable，而不是拿其他 Connector 的账号发起请求。

## 上游优先的变更流程

- 开始实现前，必须先判断变更的权威归属。凡是能被多个 Agent App 复用，或涉及 runtime、Agent turn loop、Skill/Plugin 生命周期、Connector Host、Host Tool、凭据、权限审批、持久执行、后台任务、事件协议、跨平台宿主、测试夹具、打包和发布契约的变更，原则上都属于 AgentWeave 上游基建。
- 属于上游基建的变更，也必须先经过 SecondLoop Pull Request 预审。候选实现应从最新的 `origin/main` 创建独立分支，放入现有相关 SecondLoop PR 或标记为 `upstream-candidate` 的专用预审 PR，供 SecondLoop CI 和 Greptile 审核；该候选 PR 在上游权威提交合并前不得进入 SecondLoop `main`。
- 只有当 SecondLoop 预审 PR 的最新 head 已完成 Greptile 审核、Greptile check 成功且 unresolved review thread 为 0 后，才能从最新的 `upstream/main` 创建 AgentWeave 独立分支并提交上游 Pull Request。AgentWeave PR 的领域无关补丁必须与已通过 Greptile 的候选补丁保持语义一致，并记录对应的 SecondLoop PR、head SHA 和验证结果。
- Greptile 通过后，如果 AgentWeave 候选补丁发生任何实质变化，必须先把变化同步回 SecondLoop 预审 PR，等待新 head 再次通过 Greptile 且 unresolved review thread 归零，才能更新或合并 AgentWeave PR。不得用提交后的补丁变化绕过 SecondLoop 预审门禁。
- 上游 Pull Request 被采纳并合并后，才将对应权威提交同步到 SecondLoop，并以权威上游提交替换或重建预审 PR 中的临时候选提交，再实现或调整下游产品集成。等待上游合并期间如确需联调，只能使用明确标记的临时 integration 分支；临时实现不得直接进入产品 `main`。
- 同时包含通用基建和产品行为的任务必须拆分：先提交领域无关的上游契约与实现，再在上游合并后提交 SecondLoop 下游集成。上游 Pull Request 不得混入 SecondLoop 品牌、专属 Prompt、产品文案或只服务单一路由的交互。
- SecondLoop 下游负责产品身份、品牌、Prompt、启用的能力集合、默认策略、私人秘书 routines、Today 等专属工作流、产品 onboarding 和产品界面。只有这些无法合理抽象为多 App 共用契约的部分，才直接在当前产品层实现。
- 典型的上游候选包括：邮件审批桥接和持久 Action 契约、sidecar 生命周期与后台通知、Connector/OAuth Host 契约、跨 Host 安全边界、可复用 E2E fixture、打包签名与升级基础设施。典型的下游变更包括：SecondLoop 的 Today 信息编排、品牌化连接引导、私人秘书文案、产品路由和视觉设计。
- 若归属存在疑问，先记录该能力对其他 Agent App 的适用性、稳定契约、安全边界和测试方式。能够形成领域无关扩展点时优先走上游；不得以交付速度为由在下游永久 fork 核心能力。

## Pull Request 审查、合并与收尾

- 本仓库同时连接 SecondLoop `origin` 和 AgentWeave `upstream`。所有 `gh`、GraphQL、review、Actions 和 merge 操作必须显式指定仓库、PR 编号，并在写操作前核对目标 head SHA；不得依赖当前分支或默认 remote 自动推断仓库。
- 一旦当前任务创建或更新了 Pull Request，Codex 必须把该 PR 视为仍在进行的工作，并持续监控其最新 head，直到所有适用 CI、外部审查（包括 Greptile）、review decision 和线程状态都得到明确的终态结论。PR 已创建或已推送、检查仍在 queued/in progress、外部审查尚未出现、暂时没有新反馈、或连续多次读取到相同状态，都不构成任务完成或阻塞，不得据此发送最终答复并中途停止。
- 必须主动确认所有必需门禁都已被正确触发。若必需检查或外部审查在合理观察后仍未出现，应检查仓库事件、PR 状态和服务触发条件；若服务只审查 Ready PR，则在本地验证完成并再次核对目标仓库、PR 编号和 head SHA 后主动将 Draft 转为 Ready，或执行仓库规定的等价触发动作，不得无限等待一个尚未触发的门禁。转为 Ready 只表示进入审查阶段，不等于获得合并授权。
- 等待门禁期间必须使用当前环境提供的 wait、watch 或 recurring monitor 机制；没有专用机制时，使用有界轮询并持续续接等待，避免忙轮询。只汇报有意义的状态变化，并按协作要求保持进度更新；单次等待返回但门禁仍未结束时，必须继续下一次等待，除非用户明确要求暂停或取消。
- 任一检查失败、出现 actionable feedback 或存在 unresolved review thread 时，必须先读取对应最新 head 的日志、审查正文和线程上下文，再在既定任务范围内修复、验证、提交并推送；新 head 会使旧门禁结论失效，必须重新监控全部适用门禁。不得只报告失败、把可执行的修复留给用户、或在修复推送后停止等待。
- 门禁全部通过后，必须立即继续执行本文件规定且处于既定任务范围内的下一阶段，例如转为 Ready、创建上游 PR、合并、同步权威提交、删除分支和完成最终审计；不得仅汇报“门禁已通过”后停止。只有用户明确要求暂停或取消、下一步需要合并之外的新权限或会扩大既定任务范围、目标仓库或 head 不明确、需要绕过保护规则、或外部系统已进入无法在当前权限内恢复的终态失败时，才允许停下并说明具体阻塞；等待时间较长本身不是停止理由。
- 所有检查必须对应 PR 的最新 head SHA。任何新提交、rebase、merge 或 force-push 都会使旧 head 的检查结论失效，必须等待新 head 重新完成所有必要检查。
- 外部审查 check 成功只表示审查任务结束，不表示反馈已处理完。合并前必须重新读取线程级 review 状态，确认 unresolved review thread 为 0，并核对没有新出现的 actionable feedback。
- 合并必须使用预期 head SHA 保护，避免检查完成后分支移动。被跳过的检查只有在其触发条件明确不适用于当前 PR 时才可视为正常，并应在交付说明中记录原因。
- 用户要求创建、更新、提交或处理 Pull Request，即视为已经授权 Codex 在该任务既定范围内于门禁全部满足后自行合并，无需在合并前或门禁通过后再次请求授权。Codex 必须核对最新 head，按预期 head SHA 保护执行合并，并继续同步权威提交、删除分支和完成收尾；不得把“尚未单独获得合并授权”作为停止理由。只有目标仓库或 head 不明确、需要绕过分支保护或其他安全规则、合并会扩大既定任务范围、或当前凭据没有实际合并权限时，才允许停下并说明具体阻塞。
- 合并后必须删除对应远端和本地 head 分支，执行 `git fetch --all --prune`，切回并快进默认分支。最终审计必须确认相关仓库开放 PR 为 0、相关分支不存在、默认分支与远端一致且工作树干净。

# Repository Instructions

- 禁止将 `docs/` 目录中的文档添加到 Git 追踪中。`docs/` 内容只保留在本地，不得对该目录使用 `git add -f` 或其他绕过 `.gitignore` 的方式。

## CI 失败处理

- CI 失败后必须先读取具体 workflow、job、失败步骤和日志，再决定修改代码、补测试或重跑。不得只根据 check 名称猜测根因。
- 若失败与当前 diff 无关、相同代码或相同测试在前序 head 已通过，且日志表明是非确定性基础设施、进程通信或并发错误，可以只重跑失败 job 一次；不得为消除偶发失败修改生产代码。
- 同一失败在重跑后再次出现时，应停止盲目重跑，转为精确复现、隔离和修复，并增加能够稳定覆盖根因的测试。
- 路径过滤导致相关 CI 未触发时，不能把“没有检查”视为通过。必须按变更风险补充目标 package 的测试、Clippy、fmt、类型检查或契约验证，并把结果记录在 PR 中。

## 磁盘空间管理

- 执行 workspace 级 Rust 测试、Clippy、桌面打包或其他大型构建前，先检查项目所在卷的可用空间和 `target` 等构建目录的体积。本项目完整 dev/test 构建产物可能超过 25 GiB；空间不足时优先运行目标 package 测试或使用远端 CI，不得在明知空间不足时启动全量本地构建。
- 在不影响当前开发、测试和调试工作的前提下节省硬盘空间；开发可用性和用户数据安全始终优先于释放空间。
- 避免在项目中长期保留重复下载、无用副本、临时导出、大体积日志及已失效的构建产物。任务完成并验证结果后，及时移除本次任务产生且不再需要的临时文件。
- 当磁盘空间紧张，或当前项目占用明显增长时，先检查并定位项目相关的大文件和目录，再按实际收益决定是否清理。不得在未确认用途和影响的情况下执行大范围删除。
- 清理范围仅限当前项目直接产生、可安全重新生成且当前开发流程不再使用的内容，例如过期的构建输出、测试或覆盖率缓存、工具缓存、临时日志和中间文件。优先使用项目或工具自带的清理命令。
- 清理前必须检查 Git 状态及相关进程，确认目标不包含源码、配置、文档、用户数据、未提交或未跟踪但有价值的文件、正在使用的开发环境、依赖、构建结果或活跃 worktree。不得使用 `git clean -fdx` 等可能无差别删除文件的命令，除非用户明确授权。
- 不得为了清理当前项目而删除系统级缓存、用户级共享缓存、其他项目的数据或无法确认归属的目录。若清理会导致重新下载大量依赖、长时间重建、开发中断或存在数据丢失风险，必须先征得用户同意。
- 清理完成后，验证项目仍可正常开发，并向用户说明清理对象、释放空间和任何需要重新生成的内容。
