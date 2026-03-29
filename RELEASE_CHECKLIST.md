# Release Checklist

## Before tagging

- Confirm the release tag will be `vX.Y.Z`.
- Confirm required release secrets and variables are present.
- Confirm the Windows release artifact contract remains `SecondLoop-win.msi` and `SecondLoop-win.msi.sha256`.

## Tag release workflow

- Run the tag-driven release workflow from `.github/workflows/release.yml`.
- If the release-notes LLM step fails, rerun the workflow manually. Do not add or expect an automatic fallback notes path.

## Windows release verification

- Confirm `SecondLoop-win.msi` is uploaded to the GitHub Release.
- Confirm `SecondLoop-win.msi.sha256` is uploaded to the GitHub Release.
- Confirm the release notes mention the MSI artifact and checksum file.
- Confirm the generated WinGet manifest bundle references the exact Windows MSI asset.
- Confirm local/dev Velopack packaging still emits channel-suffixed full packages such as `com.secondloop.secondloopdev-1.0.1-devwin-full.nupkg`, while `releases.<channel>.json` keeps the semantic version as `1.0.1`.
- Confirm Windows Velopack packaging runs from a short mapped workspace path instead of a deep `%TEMP%` worktree path.

## Windows auto-update smoke

- Ensure the localhost development certificate used by the smoke feed is trusted for the current user, or explicitly use `-SkipCertificateTrust` when trust is already configured.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows_auto_update_smoke.ps1` on a local Windows machine.
- Confirm the smoke feed responds at `https://localhost:8443/api/releases/latest`.
- Confirm the install root is `%LOCALAPPDATA%\com.secondloop.secondloopdev`.
- Confirm the final installed and running version is `1.0.1+1`.
- If the smoke path fails, inspect `dist/windows-auto-update-smoke/install-v1.log`, `dist/windows-auto-update-smoke/https-server.out.log`, and `dist/windows-auto-update-smoke/https-server.err.log` before sign-off.

## External publication

- Confirm the Homebrew publication job succeeded or has a clear retry path.
- Confirm the WinGet publication job succeeded or has a clear retry path.
- Confirm the WinGet publication summary reports GitHub Release publication, WinGet validation, and WinGet upstream PR publication as separate statuses.
- Confirm the WinGet publication path resolved the current upstream default branch for `microsoft/winget-pkgs` instead of assuming `master`.
- If Microsoft CLA automation is enabled, confirm the job waited briefly for the CLA prompt before deciding whether to auto-comment.
- If the GitHub Release already exists and only the WinGet PR step failed, rerun only the WinGet publication path instead of rebuilding all artifacts.

## Manual spot checks

- Optionally validate the Windows MSI hash locally with `CertUtil -hashfile SecondLoop-win.msi SHA256`.
- Optionally validate the DMG hash locally with `shasum -a 256 -c <dmg-file>.sha256`.
- If Windows installer identity or manifest matching changed materially, run `Tools/SandboxTest.ps1 <path-to-manifest>` on a self-hosted or local Windows machine as a manual validation step before final sign-off.
- Treat Windows Sandbox validation as a manual/self-hosted sign-off activity, not as a required GitHub-hosted runner gate.
