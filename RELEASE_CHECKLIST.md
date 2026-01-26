# Release Checklist (Prod builds via GitHub Actions)

目标：打 `vX.Y.Z` tag 后，GitHub Actions 自动构建并发布 **prod** 安装包，用于对外注册/申请资源；同时确保不泄露机密资源、且不会误带 staging 参数。

## 0) 一次性准备（GitHub 仓库设置）

### 必需 Secrets

GitHub Repo → Settings → Secrets and variables → Actions → Secrets：

- `SECONDLOOP_FIREBASE_WEB_API_KEY`
- `SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD`（必须 `https://`，且不能包含 `staging` / `stage`）

### Android release 签名（强烈建议：直装 → 未来上架无缝升级的前提）

如果你希望未来 Google Play 版本能 **覆盖升级** 现在的直装用户（不卸载、不丢数据），那么从第一天开始就必须：
- `applicationId` 永久不改
- release keystore 永久不换

需要新增 Secrets：
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

## 1) 每次发版前（本地/CI 前置检查）

- `main` 分支 CI 绿灯
- 本地最小验证：`pixi run ci`
- `.env.local` 未提交（应被 gitignore）
- prod secrets 已配置，且不包含 staging URL

版本号策略（已内置在 workflow）：
- `versionCode`：使用 GitHub Actions `GITHUB_RUN_NUMBER`（单调递增）
- `versionName`：tag 形如 `vX.Y.Z` 时自动使用 `X.Y.Z`

## 2) 发版（打 tag 触发）

推荐用 pixi task（会做安全校验：main 分支、clean tree、与 origin/main 同步）：

```bash
pixi run release v0.1.0
```

或手动：

```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

Actions 将构建并发布：
- Android：`apk` + `aab`
- macOS：`dmg`
- Windows：`zip`

### Windows SmartScreen（已知行为）

未签名的 Windows 构建产物（尤其是 `.exe` / 解压后的可执行文件）在首次分发时很可能触发 SmartScreen 的“未知发布者/可能有风险”提示。

后续计划（建议）：
- 申请代码签名证书（优先考虑 EV Code Signing，可更快建立信誉）
- 在 CI 中对 Windows 产物签名（并在发布说明里明确校验 SHA256）

## 3) 回滚

- 回滚到上一个已知可用的 tag（或新建 tag 指向旧 commit）
- GitHub Release 产物按 tag 可追溯
