param(
  [Parameter(Mandatory = $true)]
  [string]$ManifestDir
)

$ErrorActionPreference = 'Stop'

$resolvedManifestDir = (Resolve-Path -LiteralPath $ManifestDir).Path
$installerManifest = Get-ChildItem -LiteralPath $resolvedManifestDir -Filter '*.installer.yaml' | Sort-Object Name | Select-Object -First 1
if (-not $installerManifest) {
  throw "WinGet installer manifest not found under: $resolvedManifestDir"
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw 'winget command is not available on this machine.'
}

Write-Host "Validating WinGet manifest: $($installerManifest.FullName)"
& winget validate --manifest $resolvedManifestDir
if ($LASTEXITCODE -ne 0) {
  throw "winget validate failed with exit code $LASTEXITCODE"
}
