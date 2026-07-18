# 本地 Sidecar 传输协议

AgentWeave 为启动 `agent-server` 子进程的桌面宿主提供了带认证、进程级隔离的本地传输协议。本版本以显式启用方式提供该协议，从而保留现有的浏览器开发流程。

## 安全边界

- 宿主为每次子进程启动创建全新的启动标识和高熵传输凭据。
- 凭据只通过继承管道传入，不能出现在命令行参数、环境变量值、URL、Renderer 状态或日志中。
- Server 绑定 `127.0.0.1` 的动态端口，并通过另一条继承管道只返回协议版本、启动标识、进程标识和 origin。
- 包括健康检查和开发接口在内的每条 HTTP 路由都必须携带 `X-AgentWeave-Transport` 请求头。认证失败统一返回通用的 `401` 响应。
- 认证模式不启用 CORS。桌面 Renderer 必须通过可信的 Main 进程 IPC 访问 sidecar，不能取得 origin 或传输凭据。
- 传输认证与 Owner/Approver 授权是相互独立的层。Owner API 请求可以同时要求 `X-AgentWeave-Transport` 和现有的 `Authorization: Bearer ...` 凭据。

当前继承管道实现支持 Unix 平台。在其他平台设置显式启用所需的描述符变量时，进程会按 fail-closed 原则拒绝启动。

## 启动契约

启动器为子进程分配两个文件描述符，并把描述符的十进制编号写入：

```text
AGENTWEAVE_LAUNCH_CONFIG_FD
AGENTWEAVE_LAUNCH_RESULT_FD
```

第一条管道由宿主写向子进程。宿主写入一份有大小上限的 JSON 文档，然后关闭管道：

```json
{
  "schemaVersion": 1,
  "launchId": "7f21b128-918e-4b03-91f9-14a95c842ee4",
  "transportToken": "a-base64url-credential-with-at-least-256-bits-of-entropy",
  "backupKeyHex": "optional-64-character-lowercase-hex-key",
  "credentialVaultKeyHex": "optional-64-character-lowercase-hex-key",
  "storageProtectionKeyHex": "optional-64-character-lowercase-hex-key"
}
```

输入上限为 4096 字节；未知字段会被拒绝；`launchId` 必须是规范 UUID；传输凭据只能由 base64url 兼容字符组成，长度为 43～128 个字符。每个用途密钥都是可选字段，必须恰好解码为 32 字节，并由 sidecar 作为 secret material 使用。`backupKeyHex` 只启用认证备份与恢复，`credentialVaultKeyHex` 只解锁持久 Host secret store，`storageProtectionKeyHex` 只供已配置的数据库静态加密 Provider 使用。为兼容旧 Host，协议仍接受把同一材料用于备份与存储保护的 `dataProtectionKeyHex`，但它不能与任一用途专用字段同时出现。

第二条管道由子进程写向宿主。sidecar 完成监听端口绑定后，写入一份以换行结束的 JSON 文档，然后关闭管道：

```json
{
  "schemaVersion": 1,
  "launchId": "7f21b128-918e-4b03-91f9-14a95c842ee4",
  "pid": 18442,
  "origin": "http://127.0.0.1:53119"
}
```

启动结果不会包含传输凭据。宿主必须验证每个字段，核对启动标识与进程标识，确认 origin 是使用动态端口的 loopback HTTP 地址，并在认定 sidecar 就绪前完成带认证的健康检查。

## Electron 集成

受管 Electron 启动始终采用本协议。Main 进程独占启动管道、经过校验的 origin、凭据、健康检查和全部 HTTP 请求。普通 Preload 与审批 Preload 只通过绑定 requester 的 IPC 暴露封闭的强类型操作；它们都不接受 Renderer 传入原始 URL、路径、方法、header 或凭据。

Session、Foundation、开发接口、Host bootstrap、模型、通知、Owner 和 Approver 流量都经过 Main。Renderer 可控数据被移除后，Main 才添加 transport header。Owner 与 Approver 调用还会在 Main 中添加各自独立的 Bearer 授权，因此持有任意一层授权都不能替代另一层。

每次崩溃重启都会创建新的 launch UUID、端点和凭据。旧 child generation 不再权威时，上一份凭据 buffer 会被清除。公开 sidecar 状态不包含这些私有传输细节。

Electron Main 只在对应能力实际需要时 provision 用途密钥。没有秘密材料的 App 冷启动不携带任何用途密钥；已有 Credential Vault 会为后台 Connector 工作解锁，而 Backup key 只在用户明确导出或恢复时加载。用途密钥不会进入子进程环境变量或启动结果。备份的限定用途和恢复边界见[本地数据保护与备份](./DATA_PROTECTION.zh-CN.md)。

## 开发兼容模式

当两个描述符变量都不存在时，`agent-server` 保留显式开发行为：在 `127.0.0.1:49321` 上提供不带传输认证的服务。只设置一个变量、描述符无效或启动文档无效时，进程会中止启动。

固定、无认证的端口只用于开发兼容，不是生产桌面传输。受管 Electron 启动必须采用带认证的协议。可运行以下命令完成双实例验收：

```bash
pixi run sidecar-transport-check
```

浏览器开发只能通过 Vite 开发代理访问固定端口。显式 Electron external 模式使用 `AGENTWEAVE_SERVER_URL`；非 loopback URL 必须使用 HTTPS，并提供 base64url 兼容的 `AGENTWEAVE_SERVER_TOKEN`。External 模式不会让 Electron 获得该 server 进程的所有权。
