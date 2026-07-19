# Managed Gateway Agent

这个参考 App 展示 `app_managed` 发布路径。App 只声明公开的身份、权益、模型与 Cloudflare 部署配置；开发者凭据始终留在可信 Host 或所选 Provider 中。

仓库内的域名和 Cloudflare 账号 ID 都是占位值。请使用 AgentWeave 开发者工具打开此 App，选择已安装的 Provider 插件，替换必填公开字段，完成 Cloudflare 授权，一次性填写部署秘密，然后依次完成计划、应用和带身份验证。

在验证生成 `.agentweave/deployment.lock` 之前，打包会确定性地失败。该文件只记录公开部署事实与哈希，属于开发机本地状态，不会进入发布产物。

普通用户只会看到品牌化登录流程，不能修改模型端点或凭据。如果产品需要用户自带模型配置，请从 `examples/minimal-agent` 开始，并选择 `user_configurable`。
