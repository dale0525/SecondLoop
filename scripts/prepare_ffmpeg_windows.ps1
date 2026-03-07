$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot.Path

& (Join-Path $PSScriptRoot 'setup_ffmpeg_windows.ps1')
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& (Join-Path $PSScriptRoot 'run_fvm_tool.ps1') -Tool dart -Command run tools/prepare_bundled_ffmpeg.dart --platform=windows
exit $LASTEXITCODE
