# SecondLoop Agent App

这是 SecondLoop 的正式产品定义，不是 Framework 示例。它固定产品身份、品牌、语言、主题、Prompt、私有 routines Skill 和发布能力集合；框架源码、开发工具和标准聊天流全部直接来自 AgentWeave。

本地开发：

```bash
pixi run app-dev
```

Electron 启动后，在 Developer Tools 中保存并测试模型连接，也可以创建、编辑、校验和热重载当前 App 的 Skills。API key 只进入本机安全存储，不写入这份产品定义。

校验与打包：

```bash
pixi run app-package
```

产品能力必须来自 Manifest 声明和已合并的 AgentWeave 上游契约。OAuth 授权和提醒确认通过标准对话中的安全结构化卡片完成，不增加 SecondLoop 专属页面。开发者工具、Owner Skills 和未声明的后台能力在正式产品中保持关闭。
