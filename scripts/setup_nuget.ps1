$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path

$nugetDir = Join-Path (Join-Path $repoRootPath '.tool') 'nuget'
$nugetExe = Join-Path $nugetDir 'nuget.exe'

if (Test-Path $nugetExe) {
  Write-Host "nuget ok: $nugetExe"
  return
}

New-Item -ItemType Directory -Force -Path $nugetDir | Out-Null

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
}

$uri = 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe'
Write-Host "Downloading nuget.exe to $nugetExe"

$invokeParams = @{ Uri = $uri; OutFile = $nugetExe }
if ($PSVersionTable.PSVersion.Major -le 5) {
  $invokeParams.UseBasicParsing = $true
}
Invoke-WebRequest @invokeParams

$nugetFile = Get-Item $nugetExe -ErrorAction Stop
if ($nugetFile.Length -le 0) {
  throw "nuget download failed (empty file): $nugetExe"
}

Write-Host "nuget installed: $nugetExe"
