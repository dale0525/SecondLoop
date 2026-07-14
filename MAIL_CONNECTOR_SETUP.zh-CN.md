# IMAP/SMTP Mail Connector 配置

[English](./MAIL_CONNECTOR_SETUP.md) | 简体中文

AgentWeave 默认显示未配置的 Mail 状态，不会虚构一个已连接账户。只有需要确定性开发或测试数据时，才应设置 `AGENTWEAVE_FAKE_MAIL=enabled`。启用 IMAP/SMTP 时，账号配置文件仍然只保存 opaque secret ID；邮箱密码不会写入 Agent App Manifest、模型输入、Renderer 状态或普通日志。

## 1. 安全前提

生产配置要求：

- IMAP 使用隐式 TLS；当前首版不启用 IMAP STARTTLS。
- SMTP 使用隐式 TLS 或 STARTTLS。
- 证书必须通过系统信任链验证。
- 明文连接只允许显式配置的 `localhost` 测试服务。
- 密码保存在加密 Credential Vault 中，通过 App、tenant、user、connector、account 和 scope 共同授权的短期 lease 读取。
- SMTP 结果为 `uncertain` 时不得盲目重试，应先人工或通过 provider 状态对账。

## 2. 创建账号配置

复制 [mail-account.example.json](./examples/secretary-agent/mail-account.example.json)，修改邮箱地址、服务器、端口和文件夹名称。`credentialSecretId` 是引用，不是密码。

配置中的 scope 必须与正在运行的 App 一致。Secretary 示例使用：

```json
{
  "appId": "com.example.secretary-agent",
  "tenantId": "local",
  "userId": "local-user"
}
```

常见端口：IMAP implicit TLS 为 `993`，SMTP implicit TLS 常为 `465`，SMTP STARTTLS 常为 `587`。Gmail、Microsoft 和其他服务的文件夹名称、应用密码及认证政策并不完全一致，应以服务商设置为准。

## 3. 配置 Credential Vault

生成 32 字节主密钥，并把它交给部署环境的 secret manager；不要提交到 Git：

```bash
export AGENTWEAVE_SECRET_ROOT="$HOME/.agentweave/secrets"
export AGENTWEAVE_SECRET_MASTER_KEY_HEX="$(openssl rand -hex 32)"
```

将邮箱密码或应用密码从标准输入写入 Vault。以下命令不会把 secret 值写进参数或输出：

```bash
password-manager read agentweave/mail-primary | \
  pixi run store-server-secret -- \
    --app-id com.example.secretary-agent \
    --secret-id mail.primary.password
```

轮换已有 secret：

```bash
password-manager read agentweave/mail-primary-new | \
  pixi run store-server-secret -- \
    --app-id com.example.secretary-agent \
    --secret-id mail.primary.password \
    --rotate
```

`password-manager read ...` 是占位示例，请替换为实际密码管理器命令。避免在 shell 命令行直接写明文密码。

## 4. 启动 Server

```bash
export AGENTWEAVE_APP_ROOT="examples/secretary-agent"
export AGENTWEAVE_MAIL_CONNECTOR="imap-smtp"
export AGENTWEAVE_MAIL_ACCOUNT_CONFIG="examples/secretary-agent/mail-account.json"
export AGENTWEAVE_SECRET_ROOT="$HOME/.agentweave/secrets"
export AGENTWEAVE_SECRET_MASTER_KEY_HEX="<从部署 secret manager 注入>"

pixi run server
```

启动时 Runtime 会验证配置、App scope、Secret ID 和 Connector Account 授权。缺失 Vault、scope 不一致、TLS 策略不安全或配置文件为符号链接时，Server 会 fail closed。

## 5. 已知兼容性边界

- 支持 IMAP 邮箱列举、搜索、读取、已读标记和 move；thread 语义在缺少服务端 thread ID 时按单消息保守处理。
- Draft 默认保存在本地 deterministic draft store；不同 IMAP 服务对 Drafts 文件夹行为差异较大。
- SMTP 支持文本与 HTML 正文。首版 live adapter 不从任意本地路径读取外发附件。
- HTML 邮件按不可信内容处理；活跃内容不会执行，外部邮件中的 Prompt-like 文本不能改变 Runtime 指令或审批策略。
- OAuth、Gmail API 和 Microsoft Graph 应作为独立 adapter 接入，不应把 vendor 行为写进 Mail Foundation Skill。

仓库默认 conformance gate 使用本地 Fake IMAP/SMTP server，不需要真实账号。Live provider 验证应单独开启，并使用专用测试账号。
