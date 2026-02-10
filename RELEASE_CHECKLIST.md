# Release Checklist (Prod builds via GitHub Actions)

目标：运行 `pixi run release` 后，系统自动判定下一个 `vX.Y.Z` tag，触发 GitHub Actions 构建并发布 **prod** 安装包；同时自动生成多语言更新日志资产（供 GitHub Release 页面 + App 内展示）。

## 0) 一次性准备（GitHub 仓库设置）

### 必需 Secrets / Variables

GitHub Repo → Settings → Secrets and variables → Actions：

Secrets：
- `SECONDLOOP_FIREBASE_WEB_API_KEY`
- `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD`（必须 `https://`，且不能包含 `staging` / `stage`）
- `SECONDLOOP_MANAGED_VAULT_BASE_URL_PROD`
- `RELEASE_LLM_API_KEY`（用于判定版本 bump 与生成多语言 release notes）
- `RELEASE_LLM_MODEL`（必需）
- `RELEASE_LLM_BASE_URL`（可选，默认 `https://api.openai.com/v1`）

Variables：
- `RELEASE_NOTES_LOCALES`（可选，默认 `zh-CN,en-US`）

### Android release 签名（强烈建议）

如果你希望未来 Google Play 版本能 **覆盖升级** 现在的直装用户（不卸载、不丢数据），那么从第一天开始就必须：
- `applicationId` 永久不改
- release keystore 永久不换

新增 Secrets：
- `ANDROID_KEYSTORE_BASE64`（`upload-keystore.jks` 的 base64，建议无换行）
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

本地生成（示例）：

```bash
mkdir -p ~/secondloop-signing && cd ~/secondloop-signing
pixi run -- keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 9125 \
  -alias upload
```

导出指纹（用于 Firebase / OAuth / 支付渠道登记）：

```bash
pixi run -- keytool -list -v -keystore ~/secondloop-signing/upload-keystore.jks -alias upload
```

生成 base64（macOS）：

```bash
base64 -i ~/secondloop-signing/upload-keystore.jks | tr -d '\n'
```

> 不要把 `upload-keystore.jks` / `android/key.properties` 提交到仓库（已在 `android/.gitignore` 中忽略）。

## 1) 每次发版前（本地前置检查）

- `main` 分支 CI 绿灯
- 本地最小验证：`pixi run ci`
- `.env.local` 未提交（应被 gitignore）
- 已配置 prod secrets，且 URL 不包含 staging
- 本地环境已配置 `RELEASE_LLM_API_KEY`、`RELEASE_LLM_MODEL`（可直接写在 `.env.local`）

版本号策略（自动）：
- 仅允许三段 tag：`vX.Y.Z`
- 禁止四段 tag：`vX.Y.Z.A`
- LLM 仅判定 `major/minor/patch/none`；脚本根据最新 tag 计算下一版本号

## 2) 发版（自动判版 + 自动打 tag）

推荐用 Pixi task（会做安全校验：main 分支、clean tree、与 origin/main 同步）：

```bash
pixi run release
```

`pixi run release` 会自动执行：
- release preflight（运行时资产完整性、锁版本校验）
- 收集 release facts（PR/commit 事实）
- 调用 LLM 判定 bump（`major/minor/patch`）
- 计算并打 `vX.Y.Z` tag，push 到远端触发工作流

> 失败策略是 **Fail Fast**：
> - LLM 调用失败
> - bump 规则冲突
> - 更新日志资产校验失败
> 都会直接阻断发布。

Actions 将构建并发布：
- Android：`apk` + `aab`
- macOS：`dmg`
- Windows：`zip`
- Linux：`tar.gz`（包含 `bundle/`）
- Release notes 资产：
  - `release-notes-vX.Y.Z-manifest.json`
  - `release-notes-vX.Y.Z-zh-CN.json`
  - `release-notes-vX.Y.Z-en-US.json`

桌面构建（macOS/Windows/Linux）会在打包前自动准备并随包携带 `ffmpeg` 二进制。

### Windows SmartScreen（已知行为）

未签名的 Windows 构建产物（尤其是 `.exe` / 解压后的可执行文件）在首次分发时很可能触发 SmartScreen 的“未知发布者/可能有风险”提示。

后续计划（建议）：
- 申请代码签名证书（优先考虑 EV Code Signing，可更快建立信誉）
- 在 CI 中对 Windows 产物签名（并在发布说明里明确校验 SHA256）

## 3) 回滚

- 回滚到上一个已知可用的三段 tag（`vX.Y.Z`）
- GitHub Release 产物按 tag 可追溯
