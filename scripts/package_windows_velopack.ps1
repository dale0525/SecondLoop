param(
  [string]$Version = '',
  [string]$OutputPath = 'dist',
  [string]$PackId = 'com.secondloop.secondloop',
  [string]$Channel = 'win',
  [string]$VpkVersion = '0.0.1298',
  [switch]$SkipBuild
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

  if ($env:SECONDLOOP_RELEASE_REPO) {
    $defines += "--dart-define=SECONDLOOP_RELEASE_REPO=$($env:SECONDLOOP_RELEASE_REPO)"
  }

  if (Test-Path Env:SECONDLOOP_RELEASE_API_ORIGIN) {
    $defines += "--dart-define=SECONDLOOP_RELEASE_API_ORIGIN=$($env:SECONDLOOP_RELEASE_API_ORIGIN)"
  }

  return $defines
}

function Resolve-PackageVersion {
  if ($Version) {
    return $Version
  }

  $pubspecPath = Join-Path $repoRootPath 'pubspec.yaml'
  if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml not found at $pubspecPath"
  }

  $versionLine = Get-Content $pubspecPath | Where-Object { $_ -match '^\s*version\s*:\s*' } | Select-Object -First 1
  if (-not $versionLine) {
    throw 'Could not read app version from pubspec.yaml'
  }

  if ($versionLine -match '^\s*version\s*:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9A-Za-z\.-]+)?\s*$') {
    return $Matches[1]
  }

  throw "Invalid pubspec version format: $versionLine"
}

function Resolve-MainExeName([string]$SourceDir) {
  $preferred = Join-Path $SourceDir 'secondloop.exe'
  if (Test-Path $preferred) {
    return 'secondloop.exe'
  }

  $candidate = Get-ChildItem -Path $SourceDir -Filter '*.exe' -File |
    Where-Object { $_.Name -ne 'Update.exe' } |
    Select-Object -First 1

  if ($null -eq $candidate) {
    throw "No main executable found in $SourceDir"
  }

  return $candidate.Name
}

function Ensure-VpkTool([string]$RequiredVersion) {
  $toolRoot = Join-Path (Join-Path $repoRootPath '.tool') 'velopack'
  New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null

  if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'dotnet SDK is required to install and run vpk.'
  }

  $args = @(
    'tool', 'update',
    'vpk',
    '--tool-path', $toolRoot,
    '--version', $RequiredVersion
  )

  $dotnetOutput = & dotnet @args 2>&1
  $dotnetExitCode = $LASTEXITCODE

  foreach ($line in $dotnetOutput) {
    Write-Host $line
  }

  if ($dotnetExitCode -ne 0) {
    throw "Failed to install vpk $RequiredVersion"
  }

  $vpkPath = Join-Path $toolRoot 'vpk.exe'
  if (-not (Test-Path $vpkPath)) {
    throw "vpk.exe not found after install: $vpkPath"
  }

  return $vpkPath
}

Import-DotEnvLocal

if (-not $SkipBuild) {
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

$resolvedVersion = Resolve-PackageVersion
$mainExe = Resolve-MainExeName -SourceDir $releaseDir
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$vpkPath = Ensure-VpkTool -RequiredVersion $VpkVersion

$packArgs = @(
  'pack',
  '--packId', $PackId,
  '--packVersion', $resolvedVersion,
  '--packDir', $releaseDir,
  '--mainExe', $mainExe,
  '--outputDir', $OutputPath,
  '--channel', $Channel
)

Write-Host ('Running: ' + $vpkPath + ' ' + ($packArgs -join ' '))
& $vpkPath @packArgs
if ($LASTEXITCODE -ne 0) {
  throw "vpk pack failed with exit code $LASTEXITCODE"
}

$setupExists = Get-ChildItem -Path $OutputPath -Filter '*Setup*.exe' -File | Select-Object -First 1
$releasesExists = Get-ChildItem -Path $OutputPath -Filter '*RELEASES*' -File | Select-Object -First 1
$packageExists = Get-ChildItem -Path $OutputPath -Filter '*.nupkg' -File | Select-Object -First 1
if ($null -eq $setupExists -or $null -eq $releasesExists -or $null -eq $packageExists) {
  throw "Velopack output missing setup exe, RELEASES, or nupkg in $OutputPath"
}

Write-Host "Velopack package ready in: $OutputPath"
