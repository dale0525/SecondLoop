param(
  [switch]$UseFlutterRun
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
    if ($name -eq 'SECONDLOOP_CLOUD_GATEWAY_BASE_URL') {
      throw "SecondLoop: do not set SECONDLOOP_CLOUD_GATEWAY_BASE_URL in .env.local. Use SECONDLOOP_CLOUD_ENV + SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING/PROD instead."
    }

    $value = $parts[1].Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"')) { $value = $value.Trim('"') }

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

function Get-DevMsiVersion {
  $utcNow = (Get-Date).ToUniversalTime()
  $bucket = (($utcNow.DayOfYear - 1) * 144) + [int][Math]::Floor((($utcNow.Hour * 60) + $utcNow.Minute) / 10)
  return "1.$($utcNow.Year % 100).$bucket"
}

Import-DotEnvLocal

if ($UseFlutterRun) {
  & (Join-Path $PSScriptRoot 'setup_nuget.ps1')

  $nugetDir = Join-Path (Join-Path $repoRootPath '.tool') 'nuget'
  $nugetExe = Join-Path $nugetDir 'nuget.exe'
  if (Test-Path $nugetExe) {
    $env:PATH = "$nugetDir;$env:PATH"
  } else {
    Write-Warning "nuget.exe not found at $nugetExe; Flutter may download its own copy."
  }

  Write-Host "Running: flutter pub get"
  & dart pub global run fvm:main flutter pub get
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  Write-Host "Running: prepare_desktop_runtime.dart --platform windows --arch x64"
  & dart pub global run fvm:main dart run tools/prepare_desktop_runtime.dart --platform=windows --arch=x64
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  Write-Host "Running: sync_desktop_runtime_to_appdir.dart --platform windows"
  & dart pub global run fvm:main dart run tools/sync_desktop_runtime_to_appdir.dart --platform=windows
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  Write-Host "Running: flutter run -d windows"
  $firebaseWebApiKey = $env:SECONDLOOP_FIREBASE_WEB_API_KEY
  $cloudGatewayBaseUrl = Resolve-CloudGatewayBaseUrl

  $defines = @()
  if ($firebaseWebApiKey) { $defines += "--dart-define=SECONDLOOP_FIREBASE_WEB_API_KEY=$firebaseWebApiKey" }
  if ($cloudGatewayBaseUrl) { $defines += "--dart-define=SECONDLOOP_CLOUD_GATEWAY_BASE_URL=$cloudGatewayBaseUrl" }

  & dart pub global run fvm:main flutter run -d windows @defines
  exit $LASTEXITCODE
}

$devVersion = Get-DevMsiVersion
$outputName = 'secondloop-dev'
$devProductName = 'SecondLoop Dev'
$devUpgradeCode = 'A8A3E3A2-3C6E-4D9D-BD70-82D59F8CF0B2'

Write-Host "Running MSI debug flow. Packaging version: $devVersion"
$msiPathOutput = & (Join-Path $PSScriptRoot 'package_windows_msi.ps1') `
  -Version $devVersion `
  -OutputPath 'dist' `
  -OutputName $outputName `
  -ProductName $devProductName `
  -UpgradeCode $devUpgradeCode `
  -PassThru
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$msiPath = $msiPathOutput | Select-Object -Last 1
if (-not $msiPath -or -not (Test-Path $msiPath)) {
  throw "MSI package path is invalid: $msiPath"
}

& (Join-Path $PSScriptRoot 'install_windows_msi.ps1') -MsiPath $msiPath -Quiet -LaunchAfterInstall -InstallDirName $devProductName
exit $LASTEXITCODE
