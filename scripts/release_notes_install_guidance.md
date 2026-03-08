## macOS Installation Note (Unsigned DMG)
- This macOS build is distributed without Apple Developer signing or notarization.
- If macOS blocks first launch, Control-click the app, choose Open, then click Open again.

## macOS 安装提示（未签名 DMG）
- 当前 macOS 安装包未使用 Apple Developer 签名或公证。
- 若首次启动被系统拦截，请按住 Control 点击应用，选择 打开，然后再次确认 打开。

## Checksum Verification
- SHA256 checksum files are published as `*.dmg.sha256` assets.
- Verify on macOS with `shasum -a 256 -c <dmg-file>.sha256`.
- Verify on Windows with `CertUtil -hashfile SecondLoop-win.msi SHA256` and compare with `SecondLoop-win.msi.sha256`.

## Package Manager Install (Beta)
- Homebrew: `brew tap dale0525/SecondLoopHomebrew && brew install --cask secondloop`
- WinGet: `winget install --id SecondLoop.SecondLoop --exact`

## Windows Installer
- Windows direct download: `SecondLoop-win.msi`.
- Windows checksum file: `SecondLoop-win.msi.sha256`.
- Future Windows updates are manual or managed by your deployment tooling.

## Windows 安装包选择建议
- Windows 直接下载请使用 `SecondLoop-win.msi`。
- 可使用 `SecondLoop-win.msi.sha256` 校验安装包完整性。
- 后续 Windows 更新通常通过手动安装或企业分发策略完成。
