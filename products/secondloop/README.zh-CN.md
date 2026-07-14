# SecondLoop Agent App

这是 SecondLoop 的正式产品定义，不是 Framework 示例。它固定产品身份、品牌、语言、主题、Prompt、私有 routines Skill 和发布能力集合。

本地开发：

```bash
AGENTWEAVE_APP_ROOT=products/secondloop pixi run dev
```

校验与打包：

```bash
pixi run validate-secondloop
pixi run package-macos \
  --input products/secondloop \
  --output dist/macos/secondloop \
  --overwrite
```

产品能力必须来自 Manifest 声明和已合并的 AgentWeave 上游契约。开发者工具、Owner Skills 和未声明的后台能力在正式产品中保持关闭。
