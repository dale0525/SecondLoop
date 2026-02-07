$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot.Path

& (Join-Path $PSScriptRoot 'setup_ffmpeg_windows.ps1')
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& dart pub global run fvm:main dart run tools/prepare_bundled_ffmpeg.dart --platform=windows
exit $LASTEXITCODE
