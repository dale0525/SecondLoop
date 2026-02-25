$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
$ciVulkanSdkVersion = '1.4.309.0'

function Add-ToPathIfMissing {
  param([string]$Directory)

  if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
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

function Resolve-ExistingDirectories {
  param([string[]]$Candidates)

  $unique = @{}
  foreach ($candidate in $Candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }

    try {
      $resolved = [System.IO.Path]::GetFullPath($candidate)
    } catch {
      continue
    }

    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
      continue
    }

    if ($unique.ContainsKey($resolved)) {
      continue
    }

    $unique[$resolved] = $true
    $resolved
  }
}

function Get-CandidateDirectories {
  $directories = @()

  if ($env:LIBCLANG_PATH) {
    if (Test-Path -LiteralPath $env:LIBCLANG_PATH -PathType Container) {
      $directories += $env:LIBCLANG_PATH
    } elseif (Test-Path -LiteralPath $env:LIBCLANG_PATH -PathType Leaf) {
      $directories += (Split-Path -Path $env:LIBCLANG_PATH -Parent)
    }
  }

  if ($env:CONDA_PREFIX) {
    $directories += (Join-Path (Join-Path $env:CONDA_PREFIX 'Library') 'bin')
    $directories += (Join-Path $env:CONDA_PREFIX 'bin')
  }

  $defaultPixiEnv = Join-Path (Join-Path $repoRootPath '.pixi/envs') 'default'
  $directories += (Join-Path (Join-Path $defaultPixiEnv 'Library') 'bin')
  $directories += (Join-Path $defaultPixiEnv 'bin')

  Resolve-ExistingDirectories -Candidates $directories
}

function Get-CandidateSdkRoots {
  $roots = @()

  if ($env:SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT) {
    $roots += $env:SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT
  }

  if ($env:VULKAN_SDK) {
    $roots += $env:VULKAN_SDK
  }

  $roots += (Join-Path (Join-Path (Join-Path $repoRootPath '.tool') 'vulkan-sdk') $ciVulkanSdkVersion)
  $roots += (Join-Path 'C:\VulkanSDK' $ciVulkanSdkVersion)
  $roots += (Join-Path 'C:\Program Files\VulkanSDK' $ciVulkanSdkVersion)

  $systemVulkanRoot = 'C:\VulkanSDK'
  if (Test-Path -LiteralPath $systemVulkanRoot -PathType Container) {
    $roots += (
      Get-ChildItem -LiteralPath $systemVulkanRoot -Directory -ErrorAction SilentlyContinue |
      Sort-Object -Property Name -Descending |
      ForEach-Object { $_.FullName }
    )
  }

  if ($env:CONDA_PREFIX) {
    $roots += (Join-Path $env:CONDA_PREFIX 'Library')
    $roots += $env:CONDA_PREFIX
  }

  $defaultPixiEnv = Join-Path (Join-Path $repoRootPath '.pixi/envs') 'default'
  $roots += (Join-Path $defaultPixiEnv 'Library')
  $roots += $defaultPixiEnv

  Resolve-ExistingDirectories -Candidates $roots
}

function Resolve-LibclangCandidate {
  param([string]$Directory)

  foreach ($name in @('libclang.dll', 'clang.dll')) {
    $path = Join-Path $Directory $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      return @{
        needs_shim = $false
        file_path = $path
        directory = $Directory
      }
    }
  }

  $versioned = Get-ChildItem -LiteralPath $Directory -Filter 'libclang-*.dll' -File -ErrorAction SilentlyContinue |
    Sort-Object -Property Name |
    Select-Object -First 1

  if ($null -ne $versioned) {
    return @{
      needs_shim = $true
      file_path = $versioned.FullName
      directory = $Directory
    }
  }

  return $null
}

function Test-VulkanSdkRootLayout {
  param([string]$Root)

  $includeCandidates = @(
    (Join-Path (Join-Path $Root 'Include') 'vulkan\\vulkan.h'),
    (Join-Path (Join-Path $Root 'include') 'vulkan\\vulkan.h')
  )
  $libCandidates = @(
    (Join-Path (Join-Path $Root 'Lib') 'vulkan-1.lib'),
    (Join-Path (Join-Path $Root 'lib') 'vulkan-1.lib')
  )
  $glslcCandidates = @(
    (Join-Path (Join-Path $Root 'Bin') 'glslc.exe'),
    (Join-Path (Join-Path $Root 'bin') 'glslc.exe'),
    (Join-Path (Join-Path (Join-Path $Root 'Library') 'bin') 'glslc.exe')
  )

  $hasInclude = $includeCandidates | Where-Object {
    Test-Path -LiteralPath $_ -PathType Leaf
  } | Select-Object -First 1
  $hasLib = $libCandidates | Where-Object {
    Test-Path -LiteralPath $_ -PathType Leaf
  } | Select-Object -First 1
  $hasGlslc = $glslcCandidates | Where-Object {
    Test-Path -LiteralPath $_ -PathType Leaf
  } | Select-Object -First 1

  return ($null -ne $hasInclude -and $null -ne $hasLib -and $null -ne $hasGlslc)
}

function Get-VulkanCoreHeaderPath {
  param([string]$Root)

  $headerCandidates = @(
    (Join-Path (Join-Path $Root 'Include') 'vulkan\\vulkan_core.h'),
    (Join-Path (Join-Path $Root 'include') 'vulkan\\vulkan_core.h')
  )

  return $headerCandidates | Where-Object {
    Test-Path -LiteralPath $_ -PathType Leaf
  } | Select-Object -First 1
}

function Test-VulkanKhrCooperativeMatrixSupport {
  param([string]$Root)

  $coreHeaderPath = Get-VulkanCoreHeaderPath -Root $Root
  if (-not $coreHeaderPath) {
    return $false
  }

  $requiredSymbols = @(
    'VkPhysicalDeviceCooperativeMatrixFeaturesKHR',
    'VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_COOPERATIVE_MATRIX_FEATURES_KHR'
  )

  foreach ($symbol in $requiredSymbols) {
    if (-not (Select-String -Path $coreHeaderPath -Pattern $symbol -Quiet)) {
      return $false
    }
  }

  return $true
}

function Ensure-CmakeGenerator {
  if ([string]::IsNullOrWhiteSpace($env:CMAKE_GENERATOR)) {
    Set-Item -Path Env:CMAKE_GENERATOR -Value 'Ninja'
  }

  if ([string]::Equals($env:CMAKE_GENERATOR, 'Ninja', [System.StringComparison]::OrdinalIgnoreCase)) {
    foreach ($varName in @('CMAKE_GENERATOR_INSTANCE', 'CMAKE_GENERATOR_TOOLSET', 'CMAKE_GENERATOR_PLATFORM')) {
      if (Test-Path -Path "Env:$varName") {
        Remove-Item -Path "Env:$varName" -ErrorAction SilentlyContinue
      }
    }
  }

  Write-Host "Using CMAKE_GENERATOR=$($env:CMAKE_GENERATOR)"
}

function Ensure-ProjectVulkanSdk {
  $bootstrapScript = Join-Path $PSScriptRoot 'setup_windows_vulkan_sdk.ps1'
  if (-not (Test-Path -LiteralPath $bootstrapScript -PathType Leaf)) {
    return $null
  }

  Write-Host "Preparing project Vulkan SDK via $bootstrapScript"
  $bootstrapOutput = & $bootstrapScript -Version $ciVulkanSdkVersion
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to prepare project Vulkan SDK with $bootstrapScript (exit code $LASTEXITCODE)"
  }

  $sdkRoot = $bootstrapOutput | Select-Object -Last 1
  if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
    return $null
  }

  try {
    $resolved = [System.IO.Path]::GetFullPath($sdkRoot)
  } catch {
    return $null
  }

  if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
    return $null
  }

  Set-Item -Path Env:SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT -Value $resolved
  return $resolved
}

function Ensure-LibclangDirectory {
  foreach ($candidateDirectory in Get-CandidateDirectories) {
    $candidate = Resolve-LibclangCandidate -Directory $candidateDirectory
    if ($null -eq $candidate) {
      continue
    }

    if (-not $candidate.needs_shim) {
      return $candidate.directory
    }

    $shimDirectory = Join-Path (Join-Path $repoRootPath '.tool') 'libclang'
    New-Item -ItemType Directory -Force -Path $shimDirectory | Out-Null

    $shimPath = Join-Path $shimDirectory 'libclang.dll'
    Copy-Item -LiteralPath $candidate.file_path -Destination $shimPath -Force

    return $shimDirectory
  }

  return $null
}

function Resolve-VulkanSdkRoot {
  $unsupportedSdkRoots = @()

  foreach ($candidateRoot in Get-CandidateSdkRoots) {
    if (-not (Test-VulkanSdkRootLayout -Root $candidateRoot)) {
      continue
    }

    if (Test-VulkanKhrCooperativeMatrixSupport -Root $candidateRoot) {
      return $candidateRoot
    }

    $unsupportedSdkRoots += $candidateRoot
  }

  $provisionedSdkRoot = Ensure-ProjectVulkanSdk
  if ($provisionedSdkRoot -and
      (Test-VulkanSdkRootLayout -Root $provisionedSdkRoot) -and
      (Test-VulkanKhrCooperativeMatrixSupport -Root $provisionedSdkRoot)) {
    return $provisionedSdkRoot
  }

  if ($unsupportedSdkRoots.Count -gt 0) {
    $unsupportedDetails = $unsupportedSdkRoots | ForEach-Object { " - $_" }
    $unsupportedLines = [string]::Join([Environment]::NewLine, $unsupportedDetails)
    throw "Found Vulkan SDK roots without KHR cooperative matrix headers required by whisper-rs Vulkan build:`n$unsupportedLines`nInstall Vulkan SDK $ciVulkanSdkVersion (CI baseline) and set SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT or VULKAN_SDK."
  }

  return $null
}

function Convert-ToNormalizedPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ''
  }

  $unquoted = $Path.Trim().Trim('"')
  $pathCandidate = $unquoted -replace '/', '\'

  try {
    $resolved = [System.IO.Path]::GetFullPath($pathCandidate)
  } catch {
    $resolved = $pathCandidate
  }

  return $resolved.TrimEnd('\').ToLowerInvariant()
}

function Get-WhisperRsSysCacheRoots {
  $roots = @(
    (Join-Path $repoRootPath 'rust/target'),
    (Join-Path $repoRootPath 'build')
  )

  if (-not [string]::IsNullOrWhiteSpace($env:CARGOKIT_TARGET_TEMP_DIR)) {
    $roots += $env:CARGOKIT_TARGET_TEMP_DIR
  }

  Resolve-ExistingDirectories -Candidates $roots
}

function Get-CMakeCacheValue {
  param(
    [string[]]$CacheLines,
    [string]$Key
  )

  $prefix = "${Key}:"
  foreach ($line in $CacheLines) {
    if (-not $line.StartsWith($prefix)) {
      continue
    }

    $parts = $line.Split('=', 2)
    if ($parts.Count -ne 2) {
      return ''
    }

    return $parts[1].Trim()
  }

  return ''
}

function Test-IsPathWithinRoot {
  param(
    [string]$PathValue,
    [string]$RootValue
  )

  if ([string]::IsNullOrWhiteSpace($PathValue) -or [string]::IsNullOrWhiteSpace($RootValue)) {
    return $false
  }

  if ([string]::Equals($PathValue, $RootValue, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  return $PathValue.StartsWith("$RootValue\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-StaleWhisperRsSysVulkanCaches {
  param([string]$VulkanSdkRoot)

  $expectedRoot = Convert-ToNormalizedPath -Path $VulkanSdkRoot
  if ([string]::IsNullOrWhiteSpace($expectedRoot)) {
    return
  }

  $removedCount = 0
  foreach ($searchRoot in Get-WhisperRsSysCacheRoots) {
    $cacheDirectories = Get-ChildItem -LiteralPath $searchRoot -Directory -Recurse -Filter 'whisper-rs-sys-*' -ErrorAction SilentlyContinue
    foreach ($cacheDirectory in $cacheDirectories) {
      $cachePath = Join-Path $cacheDirectory.FullName 'out/build/CMakeCache.txt'
      if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        continue
      }

      $cacheLines = Get-Content -LiteralPath $cachePath -ErrorAction SilentlyContinue
      if (-not $cacheLines) {
        continue
      }

      $cachedInclude = Get-CMakeCacheValue -CacheLines $cacheLines -Key 'Vulkan_INCLUDE_DIR'
      $cachedLibrary = Get-CMakeCacheValue -CacheLines $cacheLines -Key 'Vulkan_LIBRARY'
      if ([string]::IsNullOrWhiteSpace($cachedInclude) -or [string]::IsNullOrWhiteSpace($cachedLibrary)) {
        continue
      }

      $normalizedInclude = Convert-ToNormalizedPath -Path $cachedInclude
      $normalizedLibrary = Convert-ToNormalizedPath -Path $cachedLibrary
      $includeMatches = Test-IsPathWithinRoot -PathValue $normalizedInclude -RootValue $expectedRoot
      $libraryMatches = Test-IsPathWithinRoot -PathValue $normalizedLibrary -RootValue $expectedRoot

      if ($includeMatches -and $libraryMatches) {
        continue
      }

      Write-Host "Removing stale whisper-rs-sys cache: $($cacheDirectory.FullName)"
      Write-Host " - cached Vulkan_INCLUDE_DIR=$cachedInclude"
      Write-Host " - cached Vulkan_LIBRARY=$cachedLibrary"
      Remove-Item -LiteralPath $cacheDirectory.FullName -Recurse -Force -ErrorAction SilentlyContinue
      $removedCount += 1
    }
  }

  if ($removedCount -gt 0) {
    Write-Host "Removed $removedCount stale whisper-rs-sys cache directories for Vulkan SDK switch"
  }
}

function Ensure-ShortCargokitTempDirectories {
  $targetTempDir = $env:CARGOKIT_TARGET_TEMP_DIR
  if ([string]::IsNullOrWhiteSpace($targetTempDir)) {
    $driveRoot = [System.IO.Path]::GetPathRoot($repoRootPath)
    if ([string]::IsNullOrWhiteSpace($driveRoot)) {
      $targetTempDir = Join-Path (Join-Path $repoRootPath '.tool') 'ck'
    } else {
      $targetTempDir = Join-Path $driveRoot 'ck'
    }
    Set-Item -Path Env:CARGOKIT_TARGET_TEMP_DIR -Value $targetTempDir
  }

  $toolTempDir = $env:CARGOKIT_TOOL_TEMP_DIR
  if ([string]::IsNullOrWhiteSpace($toolTempDir)) {
    $toolTempDir = Join-Path $targetTempDir 'tool'
    Set-Item -Path Env:CARGOKIT_TOOL_TEMP_DIR -Value $toolTempDir
  }

  New-Item -ItemType Directory -Force -Path $targetTempDir | Out-Null
  New-Item -ItemType Directory -Force -Path $toolTempDir | Out-Null

  Write-Host "Using CARGOKIT_TARGET_TEMP_DIR=$targetTempDir"
  Write-Host "Using CARGOKIT_TOOL_TEMP_DIR=$toolTempDir"
}

$libclangDirectory = Ensure-LibclangDirectory
if (-not $libclangDirectory) {
  throw 'Unable to locate libclang for bindgen. Run `pixi install` and retry.'
}

Add-ToPathIfMissing -Directory $libclangDirectory
Set-Item -Path Env:LIBCLANG_PATH -Value $libclangDirectory
Write-Host "Using LIBCLANG_PATH=$libclangDirectory"

$vulkanSdkRoot = Resolve-VulkanSdkRoot
if (-not $vulkanSdkRoot) {
  throw "Unable to locate Vulkan SDK with required headers/tools for whisper-rs Vulkan build. Install Vulkan SDK $ciVulkanSdkVersion (CI baseline) and set SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT or VULKAN_SDK."
}

Set-Item -Path Env:VULKAN_SDK -Value $vulkanSdkRoot
Set-Item -Path Env:SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT -Value $vulkanSdkRoot
Add-ToPathIfMissing -Directory (Join-Path $vulkanSdkRoot 'Bin')
Add-ToPathIfMissing -Directory (Join-Path $vulkanSdkRoot 'bin')
Add-ToPathIfMissing -Directory (Join-Path (Join-Path $vulkanSdkRoot 'Library') 'bin')
Write-Host "Using VULKAN_SDK=$vulkanSdkRoot"

Ensure-ShortCargokitTempDirectories
Remove-StaleWhisperRsSysVulkanCaches -VulkanSdkRoot $vulkanSdkRoot
Ensure-CmakeGenerator
