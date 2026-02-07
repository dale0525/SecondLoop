$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
$targetDir = Join-Path (Join-Path (Join-Path $repoRootPath '.tools') 'ffmpeg') 'windows'
$targetBin = Join-Path $targetDir 'ffmpeg.exe'
$downloadUrl = $env:SECONDLOOP_FFMPEG_WINDOWS_URL
if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
  $downloadUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
}

if (Test-Path $targetBin) {
  try {
    & $targetBin -version | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Write-Host "setup-ffmpeg-windows: using existing $targetBin"
      exit 0
    }
  } catch {
  }
}

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("secondloop-ffmpeg-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$zipPath = Join-Path $tempDir 'ffmpeg.zip'
$extractDir = Join-Path $tempDir 'extract'

try {
  Write-Host "setup-ffmpeg-windows: downloading static ffmpeg"
  $invokeParams = @{ Uri = $downloadUrl; OutFile = $zipPath }
  if ($PSVersionTable.PSVersion.Major -le 5) {
    $invokeParams.UseBasicParsing = $true
  }
  Invoke-WebRequest @invokeParams

  Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

  $candidate = Get-ChildItem -Path $extractDir -Recurse -File -Filter 'ffmpeg.exe' |
    Where-Object { $_.FullName -match '[\\/]bin[\\/]' } |
    Select-Object -First 1

  if ($null -eq $candidate) {
    $candidate = Get-ChildItem -Path $extractDir -Recurse -File -Filter 'ffmpeg.exe' |
      Select-Object -First 1
  }

  if ($null -eq $candidate) {
    throw "setup-ffmpeg-windows: ffmpeg.exe not found in downloaded archive"
  }

  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
  Copy-Item -Path $candidate.FullName -Destination $targetBin -Force

  & $targetBin -version | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "setup-ffmpeg-windows: downloaded ffmpeg failed verification"
  }

  Write-Host "setup-ffmpeg-windows: ready at $targetBin"
} finally {
  Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
