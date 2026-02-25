param(
  [string]$Version = '1.4.309.0',
  [string]$InstallDir = '',
  [switch]$ForceDownload,
  [switch]$ForceReinstall
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path

function Test-VulkanSdkLayout {
  param([string]$Root)

  $headerPath = Join-Path $Root 'Include\vulkan\vulkan_core.h'
  $vulkanLibPath = Join-Path $Root 'Lib\vulkan-1.lib'
  $glslcPath = Join-Path $Root 'Bin\glslc.exe'

  return (
    (Test-Path -LiteralPath $headerPath -PathType Leaf) -and
    (Test-Path -LiteralPath $vulkanLibPath -PathType Leaf) -and
    (Test-Path -LiteralPath $glslcPath -PathType Leaf)
  )
}

function Test-VulkanKhrCooperativeMatrixSupport {
  param([string]$Root)

  $coreHeaderPath = Join-Path $Root 'Include\vulkan\vulkan_core.h'
  if (-not (Test-Path -LiteralPath $coreHeaderPath -PathType Leaf)) {
    return $false
  }

  foreach ($symbol in @(
      'VkPhysicalDeviceCooperativeMatrixFeaturesKHR',
      'VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_COOPERATIVE_MATRIX_FEATURES_KHR'
    )) {
    if (-not (Select-String -Path $coreHeaderPath -Pattern $symbol -Quiet)) {
      return $false
    }
  }

  return $true
}

function Assert-7ZipAvailable {
  if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
    throw '7z is required to extract Vulkan SDK installer payload. Run from pixi environment.'
  }
}

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
  $InstallDir = Join-Path (Join-Path (Join-Path $repoRootPath '.tool') 'vulkan-sdk') $Version
}

$cacheDir = Join-Path (Join-Path (Join-Path $repoRootPath '.tool') 'cache') 'vulkan-sdk'
$installerFileName = "VulkanSDK-$Version-Installer.exe"
$installerPath = Join-Path $cacheDir $installerFileName
$downloadUrl = $env:SECONDLOOP_WINDOWS_VULKAN_SDK_URL
if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
  $downloadUrl = "https://sdk.lunarg.com/sdk/download/$Version/windows/$installerFileName?Human=true"
}

if ((-not $ForceReinstall) -and (Test-VulkanSdkLayout -Root $InstallDir) -and (Test-VulkanKhrCooperativeMatrixSupport -Root $InstallDir)) {
  Write-Host "setup-windows-vulkan-sdk: already prepared at $InstallDir"
  Set-Item -Path Env:SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT -Value $InstallDir
  Write-Output $InstallDir
  exit 0
}

Assert-7ZipAvailable

New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
if ($ForceDownload -or -not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
  Write-Host "setup-windows-vulkan-sdk: downloading Vulkan SDK $Version"
  Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
}

if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
  throw "setup-windows-vulkan-sdk: installer download failed: $installerPath"
}

$installerSize = (Get-Item -LiteralPath $installerPath).Length
if ($installerSize -le 0) {
  throw "setup-windows-vulkan-sdk: installer file is empty: $installerPath"
}

$extractDir = Join-Path $cacheDir ("extract-$Version-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

try {
  Write-Host "setup-windows-vulkan-sdk: extracting installer payload with 7z"
  & 7z x $installerPath "-o$extractDir" -y | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "setup-windows-vulkan-sdk: 7z extraction failed with exit code $LASTEXITCODE"
  }

  if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

  Get-ChildItem -LiteralPath $extractDir -Force | ForEach-Object {
    Move-Item -LiteralPath $_.FullName -Destination $InstallDir -Force
  }
} finally {
  if (Test-Path -LiteralPath $extractDir) {
    Remove-Item -LiteralPath $extractDir -Recurse -Force
  }
}

if (-not (Test-VulkanSdkLayout -Root $InstallDir)) {
  throw "setup-windows-vulkan-sdk: extracted SDK layout is incomplete under $InstallDir"
}

if (-not (Test-VulkanKhrCooperativeMatrixSupport -Root $InstallDir)) {
  throw "setup-windows-vulkan-sdk: extracted SDK missing KHR cooperative matrix headers under $InstallDir"
}

Write-Host "setup-windows-vulkan-sdk: ready at $InstallDir"
Set-Item -Path Env:SECONDLOOP_WINDOWS_VULKAN_SDK_ROOT -Value $InstallDir
Write-Output $InstallDir
