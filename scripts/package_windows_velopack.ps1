param(
  [string]$Version = '',
  [string]$OutputPath = 'dist',
  [string]$PackId = 'com.secondloop.secondloop',
  [string]$Channel = 'win',
  [string]$VpkVersion = '0.0.1298',
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'use_windows_short_workspace.ps1')

$script:repoRootPath = Resolve-SecondLoopProjectDir -DefaultRepoRoot (Join-Path $PSScriptRoot '..')

function Add-ToPathIfMissing {
  param([string]$Directory)

  if ([string]::IsNullOrWhiteSpace($Directory) -or
      -not (Test-Path -LiteralPath $Directory -PathType Container)) {
    return
  }

  $pathEntries = @($env:PATH -split ';')
  $alreadyInPath = $pathEntries | Where-Object {
    [string]::Equals($_, $Directory, [System.StringComparison]::OrdinalIgnoreCase)
  }
  if (-not $alreadyInPath) {
    $env:PATH = "$Directory;$env:PATH"
  }
}

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

  if ($env:SECONDLOOP_APP_ID) {
    $defines += "--dart-define=SECONDLOOP_APP_ID=$($env:SECONDLOOP_APP_ID)"
  }

  if (Test-Path Env:SECONDLOOP_RELEASE_API_ORIGIN) {
    $defines += "--dart-define=SECONDLOOP_RELEASE_API_ORIGIN=$($env:SECONDLOOP_RELEASE_API_ORIGIN)"
  }

  if (Test-Path Env:SECONDLOOP_UPDATE_PUBLIC_KEY) {
    $defines += "--dart-define=SECONDLOOP_UPDATE_PUBLIC_KEY=$($env:SECONDLOOP_UPDATE_PUBLIC_KEY)"
  }

  return $defines
}

function Resolve-PackageVersion {
  if ($Version) {
    return $Version
  }

  if ($env:GITHUB_REF -and $env:GITHUB_REF_NAME -and ($env:GITHUB_REF -like "refs/tags/v*")) {
    $tagCandidate = $env:GITHUB_REF_NAME.Trim()
    if ($tagCandidate.StartsWith('v')) {
      $tagCandidate = $tagCandidate.Substring(1)
    }

    if ($tagCandidate -match '^[0-9]+\.[0-9]+\.[0-9]+$') {
      return $tagCandidate
    }

    throw "Invalid release tag version: $($env:GITHUB_REF_NAME)"
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

  $dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
  if (-not $dotnetCommand) {
    throw 'dotnet CLI is required to install and run vpk. Install dotnet-sdk in pixi and run `pixi install`.'
  }

  $dotnetSdks = @(& dotnet --list-sdks 2>$null | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_)
  })
  if ($dotnetSdks.Count -eq 0) {
    throw 'dotnet SDK is required to install and run vpk, but no SDK is installed. Install dotnet-sdk in pixi and run `pixi install`.'
  }

  $dotnetRuntimes = @(& dotnet --list-runtimes 2>$null | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_)
  })
  $hasAspNetRuntime = $false
  foreach ($runtimeLine in $dotnetRuntimes) {
    if ($runtimeLine -like 'Microsoft.AspNetCore.App *') {
      $hasAspNetRuntime = $true
      break
    }
  }
  if (-not $hasAspNetRuntime) {
    throw 'Microsoft.AspNetCore.App runtime is required to run vpk. Install dotnet-aspnetcore in pixi and run `pixi install`.'
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

function Ensure-DotnetRoot {
  $pixiDotnetRoot = Join-Path $repoRootPath '.pixi/envs/default/dotnet'
  $pixiDotnetExe = Join-Path $pixiDotnetRoot 'dotnet.exe'

  if (Test-Path -LiteralPath $pixiDotnetExe -PathType Leaf) {
    Set-Item -Path Env:DOTNET_ROOT -Value $pixiDotnetRoot
  } else {
    $dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnetCommand) {
      throw 'dotnet CLI is required to install and run vpk. Install dotnet-sdk in pixi and run `pixi install`.'
    }

    if ([string]::IsNullOrWhiteSpace($env:DOTNET_ROOT)) {
      $dotnetRoot = Split-Path -Path $dotnetCommand.Source -Parent
      Set-Item -Path Env:DOTNET_ROOT -Value $dotnetRoot
    }
  }

  $dotnetTools = Join-Path $env:DOTNET_ROOT 'tools'
  Set-Item -Path Env:DOTNET_TOOLS -Value $dotnetTools
  Set-Item -Path Env:DOTNET_CLI_TELEMETRY_OPTOUT -Value 'true'
  Set-Item -Path Env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE -Value 'true'
  Set-Item -Path Env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH -Value 'false'
  Set-Item -Path Env:DOTNET_MULTILEVEL_LOOKUP -Value '0'
  Set-Item -Path Env:DOTNET_NOLOGO -Value '1'

  Add-ToPathIfMissing -Directory $env:DOTNET_ROOT
  Add-ToPathIfMissing -Directory $env:DOTNET_TOOLS
}

function Resolve-RustToolchainBinDirectory {
  $candidates = @(
    (Join-Path $repoRootPath '.pixi/envs/default/Library/bin'),
    (Join-Path $repoRootPath '.pixi/envs/default/bin'),
    (Join-Path (Join-Path (Join-Path $repoRootPath '.tool') 'cargo') 'bin')
  )

  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $candidates += (Join-Path (Join-Path $env:USERPROFILE '.cargo') 'bin')
  }

  foreach ($candidate in $candidates) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
      continue
    }

    $cargoPath = Join-Path $candidate 'cargo.exe'
    $rustupPath = Join-Path $candidate 'rustup.exe'
    if ((Test-Path -LiteralPath $cargoPath -PathType Leaf) -or
        (Test-Path -LiteralPath $rustupPath -PathType Leaf)) {
      return $candidate
    }
  }

  return $null
}

function Ensure-RustToolchainPath {
  $rustBinDirectory = Resolve-RustToolchainBinDirectory
  if ([string]::IsNullOrWhiteSpace($rustBinDirectory)) {
    throw 'Rust toolchain is required for Windows desktop builds. Install it in the project environment with `pixi install`.'
  }

  Add-ToPathIfMissing -Directory $rustBinDirectory
}

function Ensure-WindowsBuildEnvironment {
  $flutterRoot = Join-Path $repoRootPath '.fvm/flutter_sdk'
  if (-not (Test-Path -LiteralPath $flutterRoot -PathType Container)) {
    throw "SecondLoop: missing $flutterRoot. Run `pixi install` and then `pixi run setup-flutter`."
  }

  Set-Item -Path Env:FLUTTER_ROOT -Value $flutterRoot
  Add-ToPathIfMissing -Directory (Join-Path $flutterRoot 'bin')
  Ensure-DotnetRoot
  Ensure-RustToolchainPath

  foreach ($variableName in @(
    'PROJECT_DIR',
    'DOTNET_ROOT',
    'FLUTTER_ROOT',
    'LIBCLANG_PATH',
    'VULKAN_SDK',
    'CARGOKIT_TARGET_TEMP_DIR',
    'CARGOKIT_TOOL_TEMP_DIR'
  )) {
    $entry = Get-Item -Path "Env:$variableName" -ErrorAction SilentlyContinue
    if ($null -ne $entry -and -not [string]::IsNullOrWhiteSpace($entry.Value)) {
      Write-Host "Using $variableName=$($entry.Value)"
    }
  }
}

Invoke-InWindowsShortWorkspace -RepoRootPath $script:repoRootPath -ScriptBlock {
  $script:repoRootPath = Resolve-SecondLoopProjectDir -DefaultRepoRoot (Join-Path $PSScriptRoot '..')
  $repoRootPath = $script:repoRootPath
  Set-Location $repoRootPath
  Import-DotEnvLocal
  if ($PackId) {
    Set-Item -Path Env:SECONDLOOP_APP_ID -Value $PackId
  }
  Ensure-WindowsBuildEnvironment

  $runFvmToolScript = Join-Path $PSScriptRoot 'run_fvm_tool.ps1'
  $resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
  } else {
    Join-Path $repoRootPath $OutputPath
  }

  if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'setup_windows_libclang.ps1')
    Ensure-WindowsBuildEnvironment

    Write-Host 'Running: flutter pub get'
    & $runFvmToolScript flutter pub get
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }

    Write-Host 'Running: prepare_desktop_runtime.dart --platform windows --arch x64'
    & $runFvmToolScript dart run tools/prepare_desktop_runtime.dart --platform=windows --arch=x64
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }

    Write-Host 'Running: sync_desktop_runtime_to_appdir.dart --platform windows'
    & $runFvmToolScript dart run tools/sync_desktop_runtime_to_appdir.dart --platform=windows
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }

    $buildArgs = @('build', 'windows', '--release')
    $buildArgs += Build-DartDefines
    Write-Host ('Running: flutter ' + ($buildArgs -join ' '))
    & $runFvmToolScript flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  }

  $releaseDir = Join-Path $repoRootPath 'build/windows/x64/runner/Release'
  if (-not (Test-Path $releaseDir)) {
    throw "Windows release output not found: $releaseDir"
  }

  $Channel = $Channel.Trim()
  if ([string]::IsNullOrWhiteSpace($Channel)) {
    throw 'Velopack channel must not be empty.'
  }

  $packIconPath = Join-Path $repoRootPath 'windows/runner/resources/app_icon.ico'
  if (-not (Test-Path $packIconPath)) {
    throw "Windows app icon not found: $packIconPath"
  }

  $resolvedVersion = Resolve-PackageVersion
  $mainExe = Resolve-MainExeName -SourceDir $releaseDir
  New-Item -ItemType Directory -Force -Path $resolvedOutputPath | Out-Null

  $vpkPath = Ensure-VpkTool -RequiredVersion $VpkVersion

  $packArgs = @(
    'pack',
    '--packId', $PackId,
    '--packTitle', 'SecondLoop',
    '--icon', $packIconPath,
    '--packVersion', $resolvedVersion,
    '--packDir', $releaseDir,
    '--mainExe', $mainExe,
    '--outputDir', $resolvedOutputPath,
    '--channel', $Channel
  )

  Write-Host ('Running: ' + $vpkPath + ' ' + ($packArgs -join ' '))
  & $vpkPath @packArgs
  if ($LASTEXITCODE -ne 0) {
    throw "vpk pack failed with exit code $LASTEXITCODE"
  }

  $setupExists = Get-ChildItem -Path $resolvedOutputPath -Filter '*Setup*.exe' -File | Select-Object -First 1
  $expectedPackageName = "$PackId-$resolvedVersion-$Channel-full.nupkg"
  $expectedPackagePath = Join-Path $resolvedOutputPath $expectedPackageName
  $releasesMetadataPath = Join-Path $resolvedOutputPath "releases.$Channel.json"
  $assetsMetadataPath = Join-Path $resolvedOutputPath "assets.$Channel.json"

  if ($null -eq $setupExists) {
    throw "Velopack output missing setup exe in $resolvedOutputPath"
  }
  if (-not (Test-Path $releasesMetadataPath)) {
    throw "Velopack output missing releases metadata: $releasesMetadataPath"
  }
  if (-not (Test-Path $assetsMetadataPath)) {
    throw "Velopack output missing assets metadata: $assetsMetadataPath"
  }
  if (-not (Test-Path -LiteralPath $expectedPackagePath -PathType Leaf)) {
    throw "Velopack output missing expected nupkg: $expectedPackagePath"
  }

  Write-Host "Velopack package ready in: $resolvedOutputPath"
}
