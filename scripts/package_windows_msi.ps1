param(
  [string]$Version = '',
  [string]$OutputPath = 'dist',
  [string]$OutputName = '',
  [string]$ProductName = 'SecondLoop',
  [string]$Manufacturer = 'SecondLoop Contributors',
  [string]$UpgradeCode = '8B5A0942-79D3-4B5A-A4E5-3FB906DA63A1',
  [switch]$SkipBuild,
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
Set-Location $repoRootPath

function Import-DotEnvLocal {
  $envFile = Join-Path $repoRootPath '.env.local'
  if (-not (Test-Path $envFile)) {
    return
  }

  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }

    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) { return }

    $name = $parts[0].Trim()
    if ($name.StartsWith('export ')) { $name = $name.Substring(7).Trim() }

    $value = $parts[1].Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"')) {
      $value = $value.Trim('"')
    }

    if ($name) { Set-Item -Path "Env:$name" -Value $value }
  }
}

function Resolve-CloudGatewayBaseUrl {
  if (-not $env:SECONDLOOP_CLOUD_ENV) {
    return ''
  }

  switch ($env:SECONDLOOP_CLOUD_ENV.ToLowerInvariant()) {
    'staging' { return $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING }
    'stage' { return $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING }
    'prod' { return $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD }
    'production' { return $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD }
    default { return '' }
  }
}

function Build-DartDefines {
  $defines = @()

  if ($env:SECONDLOOP_FIREBASE_WEB_API_KEY) {
    $defines += "--dart-define=SECONDLOOP_FIREBASE_WEB_API_KEY=$($env:SECONDLOOP_FIREBASE_WEB_API_KEY)"
  }

  $cloudGatewayBaseUrl = Resolve-CloudGatewayBaseUrl
  if ($cloudGatewayBaseUrl) {
    $defines += "--dart-define=SECONDLOOP_CLOUD_GATEWAY_BASE_URL=$cloudGatewayBaseUrl"
  }

  if ($env:SECONDLOOP_MANAGED_VAULT_BASE_URL_PROD -and
      $env:SECONDLOOP_CLOUD_ENV -and
      ($env:SECONDLOOP_CLOUD_ENV.ToLowerInvariant() -eq 'prod' -or $env:SECONDLOOP_CLOUD_ENV.ToLowerInvariant() -eq 'production')) {
    $defines += "--dart-define=SECONDLOOP_MANAGED_VAULT_BASE_URL=$($env:SECONDLOOP_MANAGED_VAULT_BASE_URL_PROD)"
  }

  return $defines
}

function Resolve-DefaultMsiVersion {
  $pubspecPath = Join-Path $repoRootPath 'pubspec.yaml'
  if (-not (Test-Path $pubspecPath)) {
    return '1.0.0'
  }

  $versionLine = Get-Content $pubspecPath | Where-Object { $_ -match '^\s*version\s*:\s*' } | Select-Object -First 1
  if (-not $versionLine) {
    return '1.0.0'
  }

  if ($versionLine -match '^\s*version\s*:\s*([0-9]+)\.([0-9]+)\.([0-9]+)(?:\+[0-9A-Za-z\.-]+)?\s*$') {
    return "$($Matches[1]).$($Matches[2]).$($Matches[3])"
  }

  return '1.0.0'
}

Import-DotEnvLocal
& (Join-Path $PSScriptRoot 'setup_nuget.ps1')

$nugetDir = Join-Path (Join-Path $repoRootPath '.tool') 'nuget'
$nugetExe = Join-Path $nugetDir 'nuget.exe'
if (Test-Path $nugetExe) {
  $env:PATH = "$nugetDir;$env:PATH"
}

Write-Host 'Running: flutter pub get'
& dart pub global run fvm:main flutter pub get
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host 'Running: prepare_desktop_runtime.dart --platform windows --arch x64'
& dart pub global run fvm:main dart run tools/prepare_desktop_runtime.dart --platform=windows --arch=x64
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host 'Running: sync_desktop_runtime_to_appdir.dart --platform windows'
& dart pub global run fvm:main dart run tools/sync_desktop_runtime_to_appdir.dart --platform=windows
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

if (-not $SkipBuild) {
  $buildArgs = @('build', 'windows', '--release')
  $buildArgs += Build-DartDefines
  Write-Host ('Running: flutter ' + ($buildArgs -join ' '))
  & dart pub global run fvm:main flutter @buildArgs
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

$releaseDir = Join-Path $repoRootPath 'build/windows/x64/runner/Release'
if (-not (Test-Path $releaseDir)) {
  throw "Windows release output not found: $releaseDir"
}

if (-not $Version) {
  $Version = Resolve-DefaultMsiVersion
}

if (-not $OutputName) {
  $OutputName = 'secondloop-windows-x64'
}

New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$createArgs = @{
  SourceDir = $releaseDir
  Version = $Version
  OutputPath = $OutputPath
  OutputName = $OutputName
  ProductName = $ProductName
  Manufacturer = $Manufacturer
  UpgradeCode = $UpgradeCode
}

if ($PassThru) {
  $createArgs.PassThru = $true
}

$msiPath = & (Join-Path $PSScriptRoot 'create_windows_msi.ps1') @createArgs
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$expectedMsiPath = Join-Path $OutputPath ($OutputName + '.msi')
if (-not (Test-Path $expectedMsiPath)) {
  throw "MSI package not found: $expectedMsiPath"
}

if ($PassThru) {
  $normalized = $msiPath | Select-Object -Last 1
  if (-not $normalized) {
    $normalized = $expectedMsiPath
  }
  Write-Output $normalized
} else {
  Write-Host "MSI package ready: $expectedMsiPath"
}
