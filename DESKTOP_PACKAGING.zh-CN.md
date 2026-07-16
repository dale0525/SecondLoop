# macOS Desktop 打包

AgentWeave 可以为任何已通过校验且声明兼容 Desktop 的 Agent App 构建自包含的 macOS Electron 应用。产物包含可信 Renderer 与 Main bundle、架构匹配的 Rust `agent-server` sidecar、带锁的 Agent App release、第一方 Skills，以及仓库许可证文件。

## 构建产物

请通过 Pixi 使用项目内的 Node.js、Rust 和打包工具：

```bash
pixi run package-macos \
  --input examples/minimal-agent \
  --output dist/macos/minimal \
  --overwrite
```

也可以直接构建仓库中的两个示例：

```bash
pixi run package-macos-minimal
pixi run package-macos-secretary
```

该命令会构建 release sidecar，按照所选 App Definition 编译 Desktop 资源，创建并校验 Agent App lock，使用带完整性信息的 ASAR 打包 Electron，最后检查资源布局。默认产物架构与当前 Mac 一致。只有在 sidecar 包含相同架构时，才可以指定 `--arch arm64` 或 `--arch x64`。

`--print-plan` 可以在不构建的情况下检查 bundle identifier、产品名称、版本、架构、输入和输出位置。

## 资源契约

生成的应用采用以下布局：

```text
Product.app/Contents/
  MacOS/Product
  Resources/
    app.asar
    sidecar/agent-server
    agent-app/
      agent-app.lock.json
      app/
      packages/
    skills/
    licenses/
```

Electron Main 根据 `process.resourcesPath` 解析生产资源，并强制把托管 sidecar 绑定到 `Resources/agent-app/app` 和 `Resources/skills`。Host 环境变量不能把正式产物重定向到其他 App Definition 或内置 Skill 根目录。用户数据、缓存、workspace 和 SQLite 数据库继续位于 Electron 为当前应用分配的用户数据目录中。

App 私有 package 保留在带锁的 App 树中。顶层 `skills/` 只包含被选择的第一方 package，避免同一个 App package 同时作为内置层和 App 私有层加载。

## 签名与发布

开发产物会使用 ad-hoc 签名，便于本地验证。通过 `--sign-identity "Developer ID Application: ..."` 可以在打包时使用分发身份。

正式分发由 `.github/workflows/macos-desktop-release.yml` 的手工工作流负责。该工作流只能在受保护的 `macos-release` environment 中运行，并要求以下 GitHub Actions secrets：

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_SIGN_IDENTITY`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

工作流把 Developer ID 证书和公证 profile 导入临时 keychain。证书、公证密码和 keychain 不会进入 App、Agent App lock、日志、fixture 或上传产物；无论任务成功还是失败，临时 keychain 都会被删除。

签名后的 App 会先执行真实打包 Sidecar smoke，再提交 Apple 公证并 staple。随后工作流生成包含 `/Applications` 快捷方式的压缩 DMG、带 staple ticket 的 App ZIP，以及带 HTTPS 下载地址、文件大小和 SHA-256 的版本化更新元数据。DMG 会单独提交公证并通过 Gatekeeper 检查。

每次发布会分别在原生 Apple Silicon 与 Intel runner 上生成 `arm64` 和 `x64` 构件，再由单独的发布 job 汇总。工作流默认创建 Draft GitHub Release。只有手工触发时明确选择 `publish_release`，才会在两套产物和元数据全部上传后发布 Release。已经存在的 tag 或 Release 会 fail closed，防止静默覆盖已发布构件。

本地可以用已经完成 Developer ID 签名的 App 运行同一发布脚本。正常模式必须提供存放在 keychain 中的公证 profile：

```bash
pixi run release-macos \
  --app dist/macos/secretary/Secretary\ Agent-darwin-arm64/Secretary\ Agent.app \
  --output dist/macos/release \
  --download-base-url https://example.com/releases/v1.0.0 \
  --notary-profile agentweave-local
```

`--skip-notarization` 只用于本地检查 DMG 与元数据结构。它仍要求 App 具有有效 Developer ID Application 签名，且生成的元数据会明确把产物标记为未公证；该模式不能用于正式发布。

归档 `.app` 时应使用 `ditto` 或其他理解 macOS bundle 的工具，以保留执行权限、资源信息和签名。

## 验证要求

默认打包测试不下载 Electron，也不要求签名凭据。测试会检查身份、架构归一化、sidecar 执行权限、App lock 完整性、第一方与 App 私有 Skill 的分层，以及许可证是否完整。macOS workflow 会进一步为 minimal 和 secretary 两个示例构建真实产物。

正式发布前，还应在干净的 Mac 上启动产物，确认 Electron 无需终端即可拉起内置 sidecar、重启后能够恢复会话，并且退出应用后不残留 sidecar 进程。
