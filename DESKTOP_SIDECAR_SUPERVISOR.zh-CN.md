# Desktop Sidecar Supervisor

## 状态与范围

本文定义由 Electron 管理本地 AgentWeave Rust sidecar 的生命周期，包括进程发现、启动、健康就绪、日志、崩溃恢复、退出清理，以及 Renderer 可使用的最小恢复操作。

受管 Electron 启动采用动态、带认证的 loopback 端点。固定 loopback URL 只保留给显式浏览器开发流程，不能视为生产安全边界。

## 信任边界

- Electron Main 是生命周期和传输权威。它决定 executable、参数、工作目录、环境变量、数据目录、启动管道、端点和每次启动独立的凭据。
- Preload 只暴露状态、`ensureRunning()` 和封闭集合内的强类型产品操作。Renderer 不能提供 executable、参数、环境变量、路径、端点、HTTP header、凭据、signal 或进程 ID。
- Rust sidecar 继续负责 Agent App 解析、Runtime policy、凭据、存储、审批和外部副作用。
- 健康就绪要求启动结果与预期 launch UUID、child PID 绑定，并且在该 child generation 仍为当前 generation 时完成带认证请求；它不能替代 Host bootstrap 校验。
- 显式开发和集成可以使用外部管理的 server URL，但 Electron 不拥有该进程，也不能重启或终止它。外部 URL 使用明文 HTTP 时必须是 loopback host；非 loopback 端点必须使用 HTTPS，并提供有效的 `AGENTWEAVE_SERVER_TOKEN`。

## 启动模式

| 模式 | 来源 | 生命周期行为 |
| --- | --- | --- |
| `managed` | 显式 `AGENTWEAVE_SIDECAR_EXECUTABLE`、打包资源或已经存在的开发构建 | Electron 启动、监控、重启并停止 child |
| `external` | 显式 loopback HTTP 或带认证的 HTTPS `AGENTWEAVE_SERVER_URL` | Electron 使用端点，但绝不向进程发送 signal |
| `unavailable` | 无法解析安全 executable 或外部端点 | Runtime 可选界面 fail closed，且没有可用恢复操作 |

显式外部端点的优先级高于进程发现。这样既保留现有开发流程，又避免两个 sidecar 竞争同一端点。
显式 URL 或 executable 无效时会 fail closed，不会静默选择另一种启动模式。

## 生命周期状态

公开状态 schema 独立版本化，只暴露有界的运行事实：

```text
idle -> starting -> ready -> stopping -> stopped
          |          |
          v          v
        failed     crashed -> starting
                         \-> circuit_open
```

- `idle`：已经解析 managed executable，但尚未启动。
- `starting`：正在创建 child，或等待健康就绪。
- `ready`：当前 child 已通过健康检查。
- `stopping`：Electron 已请求有序退出，正在等待 child 结束。
- `stopped`：owned child 在显式停止后退出。
- `failed`：spawn 或启动就绪失败。
- `crashed`：已就绪 child 意外退出，正在评估是否重启。
- `circuit_open`：滚动窗口内的意外退出次数超过限制。
- `external`：配置的端点不归 Electron 所有，Electron 不推断其进程状态。
- `unavailable`：没有可用启动目标。

状态不会包含 executable 路径、命令行、环境变量、数据库路径、端点凭据、stdout、stderr 或原始异常文本。

## 启动协议

1. Electron Main 解析唯一启动模式，不读取 Renderer 输入。
2. 把 sidecar data、cache、database 和 workspace root 绑定到 Electron `userData` 下，忽略继承的 root override；平台支持时使用仅 owner 可访问的权限。
3. 从显式 `AGENTWEAVE_*` 配置和少量操作系统 allowlist 构造有界 child 环境；不继承无关的 Host credential。
4. 创建 launch UUID 和 256-bit transport credential，启动一个非 detached child，并通过继承的 host-to-child 管道传入启动文档。凭据不会进入 argv、环境变量值、URL、Renderer 状态或日志。
5. 读取一份有大小上限的 child-to-host 启动结果，要求 schema version 1、完全匹配的 launch UUID 与 child PID，以及使用动态端口的 `127.0.0.1` HTTP origin。
6. 通过带认证的 Main 进程传输轮询 `/health`，直到成功或超过启动期限。
7. 只有带认证健康检查成功时仍属于当前 generation 的 child 才能进入 `ready`。业务、bootstrap、notification、Owner 和 Approver 请求使用同一条私有传输。
8. child 提前退出、发出进程错误、返回无效握手或错过启动期限时，清除凭据、终止该 generation，并发布有界失败状态。
9. 可信 App discovery 仍通过独立 Host bootstrap 契约解析。仅健康成功不能开放 Renderer 可选路由。

并发 `start()` 或 `ensureRunning()` 共享同一个进行中操作，不能创建重复 child。

## 崩溃恢复与熔断

Supervisor 在滚动时间窗口内记录意外退出，自动重启前执行有界退避。达到崩溃上限后进入 `circuit_open`，停止自动创建新 child。

`ensureRunning()` 是 Renderer 唯一可达的恢复操作。child 已就绪或正在启动时，Electron 会忽略重复请求。从 `failed`、`stopped` 或 `circuit_open` 恢复时，只清除自动崩溃历史并尝试一次新的 managed 启动；它不能修改 executable、端点、参数、环境或路径。

## 退出协议

Electron App 退出必须等待 Supervisor 清理：

1. 把当前 generation 标记为显式停止，避免 exit 触发自动重启。
2. 向 owned child 发送 `SIGTERM`。
3. 在有界时间内等待优雅退出。
4. 超过期限仍未退出时发送 `SIGKILL`。
5. 只有收到 exit 或强制退出期限结束后，清理操作才完成。

Electron 绝不向 external 模式进程发送 signal。重复清理调用共享同一操作，在窗口关闭与 App 退出竞态中保持安全。

## 日志与隐私

Child 输出按行缓冲、限制长度，并在进入 Electron 日志前清理。清理会移除 bearer credential、secret 形态的 JSON 或 key-value 字段、邮箱地址和长 token 形态内容；不完整尾行和超长输出也会被限制。Supervisor 自身不持久化邮件正文或原始 child 输出。

日志清理属于纵深防御。Sidecar 仍必须在源头避免记录 secret 和私密内容。

## 验收行为

- 重复启动只创建一个 child。
- 只有当前 child 健康成功后才进入 ready。
- 每次受管启动和崩溃重启都会使用不同的动态端点与凭据。
- 未认证、跨 generation 和 Renderer 发起的原始请求不能使用受管 sidecar。
- spawn 失败、启动超时和就绪前退出都有确定性失败结果。
- 显式 stop 不会重启 child，必要时升级为强制终止。
- 意外退出执行有界退避重启，并在达到限制时熔断。
- Renderer 恢复操作不能修改启动配置。
- sandboxed preload bundle 必须自包含，不能依赖本地 CommonJS chunk。
- Renderer 和 preload bundle 不包含 sidecar 端点、transport header 或 Owner/Approver 凭据读取逻辑。
- Electron 不会终止或重启 external 模式进程。
- Sidecar 输出进入日志前经过有界处理和清理。
- Electron 关闭后不留下 owned child。
