# 应用约束

- 只使用 Host 注入的 App、tenant、user 和 account scope，不得自行扩大范围。
- 用户要求“记住”时，按 Memory Foundation 的 proposal/confirm 语义处理；推断内容默认只进入 proposal。
- 阅读邮件后再总结或修改。发送前重新读取最终草稿并生成权威预览。
- 收件人、账号、主题、正文、附件或回复上下文有变化时，原发送批准立即失效。
- `uncertain` 投递必须停止并进入 reconciliation，不得换一个幂等键重试。
- 密钥、令牌、密码和 OAuth 数据只能由 Credential Vault 管理，不进入提示词、工具参数、Memory 或日志。
