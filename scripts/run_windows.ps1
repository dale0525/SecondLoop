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

function Get-CargokitTargetTempDir {
  if (-not [string]::IsNullOrWhiteSpace($env:CARGOKIT_TARGET_TEMP_DIR)) {
    return $env:CARGOKIT_TARGET_TEMP_DIR
  }

  $driveRoot = [System.IO.Path]::GetPathRoot($repoRootPath)
  if (-not [string]::IsNullOrWhiteSpace($driveRoot)) {
    return (Join-Path $driveRoot 'ck')
  }

  return (Join-Path (Join-Path $repoRootPath '.tool') 'ck')
}

function Get-LatestRustSourceWriteTimeUtc {
  $candidates = @()
  $rustRoot = Join-Path $repoRootPath 'rust'
  $rustSrcDir = Join-Path $rustRoot 'src'

  if (Test-Path -LiteralPath $rustSrcDir -PathType Container) {
    $candidates += Get-ChildItem -LiteralPath $rustSrcDir -Recurse -File -Filter '*.rs' -ErrorAction SilentlyContinue
  }

  foreach ($relative in @('Cargo.toml', 'Cargo.lock', 'build.rs')) {
    $path = Join-Path $rustRoot $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $candidates += Get-Item -LiteralPath $path
    }
  }

  $frbConfigPath = Join-Path $repoRootPath 'flutter_rust_bridge.yaml'
  if (Test-Path -LiteralPath $frbConfigPath -PathType Leaf) {
    $candidates += Get-Item -LiteralPath $frbConfigPath
  }

  if ($candidates.Count -eq 0) {
    return [DateTime]::MinValue
  }

  return ($candidates | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
}

function Remove-PathIfExists {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $Path) {
    throw "Failed to remove stale artifact: $Path"
  }
}

function Remove-StaleWindowsRustArtifacts {
  param(
    [ValidateSet('debug', 'release')]
    [string]$Profile
  )

  $latestRustSourceWriteTimeUtc = Get-LatestRustSourceWriteTimeUtc
  if ($latestRustSourceWriteTimeUtc -eq [DateTime]::MinValue) {
    return
  }

  $targetTempDir = Get-CargokitTargetTempDir
  $rustTargetProfileDir = Join-Path (Join-Path $targetTempDir 'x86_64-pc-windows-msvc') $Profile
  $rustDllPath = Join-Path $rustTargetProfileDir 'secondloop_rust.dll'
  if (-not (Test-Path -LiteralPath $rustDllPath -PathType Leaf)) {
    return
  }

  $rustDllWriteTimeUtc = (Get-Item -LiteralPath $rustDllPath).LastWriteTimeUtc
  if ($latestRustSourceWriteTimeUtc -le $rustDllWriteTimeUtc) {
    return
  }

  $buildProfile = if ($Profile -eq 'debug') { 'Debug' } else { 'Release' }
  Write-Host "Stale Rust artifacts detected for profile '$Profile'; removing before flutter run."
  Write-Host " - latest rust source timestamp (UTC): $latestRustSourceWriteTimeUtc"
  Write-Host " - stale artifact timestamp (UTC): $rustDllWriteTimeUtc"

  foreach ($path in @(
      (Join-Path $rustTargetProfileDir 'secondloop_rust.dll'),
      (Join-Path $rustTargetProfileDir 'secondloop_rust.dll.lib'),
      (Join-Path $rustTargetProfileDir 'secondloop_rust.pdb'),
      (Join-Path (Join-Path (Join-Path (Join-Path $repoRootPath 'build') 'windows/x64/plugins/secondloop_rust') $buildProfile) 'secondloop_rust.dll'),
      (Join-Path (Join-Path (Join-Path (Join-Path $repoRootPath 'build') 'windows/x64/plugins/secondloop_rust') $buildProfile) 'secondloop_rust.dll.lib'),
      (Join-Path (Join-Path (Join-Path (Join-Path $repoRootPath 'build') 'windows/x64/plugins/secondloop_rust') $buildProfile) 'secondloop_rust.pdb'),
      (Join-Path (Join-Path (Join-Path (Join-Path $repoRootPath 'build') 'windows/x64/runner') $buildProfile) 'secondloop_rust.dll')
    )) {
    Remove-PathIfExists -Path $path
  }
}

Import-DotEnvLocal
& (Join-Path $PSScriptRoot 'setup_windows_libclang.ps1')

$appId = $env:SECONDLOOP_APP_ID
if ([string]::IsNullOrWhiteSpace($appId)) {
  $appId = 'com.secondloop.secondloopdev'
}
$env:SECONDLOOP_APP_ID = $appId

$appName = $env:SECONDLOOP_APP_NAME
if ([string]::IsNullOrWhiteSpace($appName)) {
  if ($appId -eq 'com.secondloop.secondloopdev') {
    $appName = 'SecondLoop Dev'
  } else {
    $appName = 'SecondLoop'
  }
}
$env:SECONDLOOP_APP_NAME = $appName

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
  & (Join-Path $PSScriptRoot 'run_fvm_tool.ps1') -Tool flutter -Command pub get
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  Write-Host "Running: prepare_desktop_runtime.dart --platform windows --arch x64"
  & (Join-Path $PSScriptRoot 'run_fvm_tool.ps1') -Tool dart -Command run tools/prepare_desktop_runtime.dart --platform=windows --arch=x64
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  Write-Host "Running: sync_desktop_runtime_to_appdir.dart --platform windows"
  & (Join-Path $PSScriptRoot 'run_fvm_tool.ps1') -Tool dart -Command run tools/sync_desktop_runtime_to_appdir.dart --platform=windows
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  Remove-StaleWindowsRustArtifacts -Profile 'debug'

  $frbNativeLibDir = Join-Path $repoRootPath 'build/windows/x64/runner/Debug'
  Set-Item -Path Env:FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR -Value $frbNativeLibDir
  Write-Host "Using FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR=$frbNativeLibDir"

  Write-Host "Running: flutter run -d windows"
  $firebaseWebApiKey = $env:SECONDLOOP_FIREBASE_WEB_API_KEY
  $cloudGatewayBaseUrl = Resolve-CloudGatewayBaseUrl

  $defines = @()
  if ($firebaseWebApiKey) { $defines += "--dart-define=SECONDLOOP_FIREBASE_WEB_API_KEY=$firebaseWebApiKey" }
  if ($cloudGatewayBaseUrl) { $defines += "--dart-define=SECONDLOOP_CLOUD_GATEWAY_BASE_URL=$cloudGatewayBaseUrl" }
  if ($appId) { $defines += "--dart-define=SECONDLOOP_APP_ID=$appId" }
  if ($appName) { $defines += "--dart-define=SECONDLOOP_APP_NAME=$appName" }

  & (Join-Path $PSScriptRoot 'run_fvm_tool.ps1') -Tool flutter -Command run -d windows @defines
  exit $LASTEXITCODE
}

$devVersion = Get-DevMsiVersion
$outputName = 'secondloop-dev'
$devProductName = 'SecondLoop Dev'
$devUpgradeCode = 'A8A3E3A2-3C6E-4D9D-BD70-82D59F8CF0B2'

Remove-StaleWindowsRustArtifacts -Profile 'release'

Write-Host "Running MSI debug flow. Packaging version: $devVersion"
$msiPathOutput = & (Join-Path $PSScriptRoot 'package_windows_msi.ps1') `
  -Version $devVersion `
  -OutputPath 'dist' `
  -OutputName $outputName `
  -ProductName $devProductName `
  -UpgradeCode $devUpgradeCode `
  -DisableCloseApplication `
  -PassThru
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$msiPath = $msiPathOutput | Select-Object -Last 1
if (-not $msiPath -or -not (Test-Path $msiPath)) {
  throw "MSI package path is invalid: $msiPath"
}

& (Join-Path $PSScriptRoot 'stop_windows_installed_app.ps1') -InstallDirName $devProductName -TerminateIfNeeded
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& (Join-Path $PSScriptRoot 'install_windows_msi.ps1') -MsiPath $msiPath -Quiet -LaunchAfterInstall -InstallDirName $devProductName
exit $LASTEXITCODE
