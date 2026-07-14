# 本地数据保护与备份

[English](./DATA_PROTECTION.md)

AgentWeave 提供一项可选的 Host 能力，用于加密本地备份和可安全重启的数据库恢复。App 需要在 Manifest 中声明 `data-protection` 能力，Host 还必须通过可信启动通道提供一个 32 字节的数据保护密钥。

## 保护边界

该能力使用 AES-256-GCM 加密导出的 SQLite 备份。经过认证的信封会绑定 App ID、创建时间和明文哈希，因此备份不能被静默篡改，也不能被恢复到另一个 App。

该能力不会加密正在使用的 SQLite 数据库。状态接口会明确返回 `atRestEncryption: not_provided`，不会把加密备份描述成全盘加密或数据库静态加密。对静态数据有更高要求的 App，需要接入经过审计的加密 SQLite Provider，或依赖操作系统卷加密。

备份只包含 AgentWeave SQLite 数据库，不包含工作区文件、已打包的 App 资源、Electron 保存的模型 API Key、Connector secret 文件，也不会自动包含附件所引用的任意外部文件。

## Desktop 密钥处理

Electron Main 会生成一个随机 32 字节密钥，并且只在 App 数据目录中保存经操作系统加密后的形式。原始密钥通过继承的启动管道传给受管 Rust sidecar，不会进入子进程环境变量、Renderer、Preload 返回值、日志、Prompt 或备份元数据。

Desktop 导出会把经操作系统加密后的密钥包装与 Rust 加密备份信封放在一起。只要同一个操作系统用户的 Keychain 仍能解密包装密钥，即使重新安装 App，也可以恢复备份。它不是跨用户或跨设备恢复方案；如果平台 Keychain 和当前 App 数据同时丢失，这类备份将无法解密。

自定义 Server Host 可以通过 `AppState::with_data_protection` 注入自己妥善保护的密钥。未由可信受管 Host 提供密钥时，默认开发 Server 不启用这项能力。

## 备份流程

1. Runtime 使用 `VACUUM INTO` 创建一致的 SQLite 快照。
2. 快照大小限制为 256 MiB，并且不会暴露给 Renderer。
3. Runtime 使用 `agentweave-backup-v1` 信封加密快照。
4. Electron Main 让用户选择目标位置，并以私有文件权限写入 Desktop 备份包。
5. Renderer 只会收到字节数、创建时间和备份包哈希，不会收到路径或原始字节。

经过认证的接口包括：

- `GET /foundation/data-protection/status`
- `GET /foundation/data-protection/backup`
- `POST /foundation/data-protection/restore`

二进制备份和恢复接口只供可信 Host 使用。它们不是模型工具，也不会加入通用 Renderer sidecar 请求面。

## 恢复流程

Electron Main 读取用户选择的备份，但不会把路径或字节返回 Renderer。它使用操作系统加密能力解开备份密钥，再通过已认证的本地传输发送加密信封和一次性恢复密钥。

sidecar 会认证并解密信封，核对 App ID，执行大小限制、SQLite `quick_check` 和预期迁移表检查，然后写入私有的 `restore-pending` 数据库。处理请求期间不会修改正在使用的数据库。

恢复文件准备完成后，Electron Main 会停止并重新启动受管 sidecar。启动阶段会再次验证待恢复数据库，把当前数据库及其 WAL/SHM 文件移动到回滚文件族，再原子提升待恢复数据库。如果提升失败，启动流程会先尝试放回旧数据库。

同一时间只允许存在一个待恢复任务。后续成功恢复会替换更早的回滚副本。恢复必须由用户显式发起，模型输出和外部文档内容不得触发恢复。

## 失败契约

- 未声明能力或没有密钥：禁用备份与恢复。
- 元数据无效、密钥格式错误、认证失败或 SQLite 内容不兼容：`400`。
- 备份属于另一个 App，或已经存在待恢复任务：`409`。
- 备份超过限制：`413`。
- 未预期的存储或文件系统错误：返回已脱敏的 `500`，响应中不包含路径、密钥或数据库内容。

Host 不应把活动数据库、回滚数据库、加密备份包或包装密钥写入日志、截图、测试夹具或错误报告。
