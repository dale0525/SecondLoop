$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
Set-Location $repoRootPath

$portableRoot = Join-Path (Join-Path $repoRootPath '.tool') 'wix3'
$portableCurrent = Join-Path $portableRoot 'current'

function Resolve-ToolPath([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $cmd) {
    return ''
  }
  return $cmd.Source
}

function Add-PortableWixToPath {
  $candidates = @(
    $portableCurrent,
    (Join-Path $portableCurrent 'bin')
  )

  $pathEntries = @()
  if ($env:PATH) {
    $pathEntries = $env:PATH -split ';'
  }

  foreach ($candidate in $candidates) {
    if (-not (Test-Path $candidate)) {
      continue
    }

    $exists = $pathEntries | Where-Object { $_ -and $_.TrimEnd('\') -ieq $candidate.TrimEnd('\') } | Select-Object -First 1
    if (-not $exists) {
      $env:PATH = "$candidate;$env:PATH"
      $pathEntries = $env:PATH -split ';'
    }
  }
}

function Test-WixReady {
  $heat = Resolve-ToolPath 'heat.exe'
  $candle = Resolve-ToolPath 'candle.exe'
  $light = Resolve-ToolPath 'light.exe'
  return [bool]($heat -and $candle -and $light)
}

function Test-PortableWixReady {
  $candidateRoots = @(
    $portableCurrent,
    (Join-Path $portableCurrent 'bin')
  )

  foreach ($root in $candidateRoots) {
    if (-not (Test-Path $root)) {
      continue
    }

    $heat = Join-Path $root 'heat.exe'
    $candle = Join-Path $root 'candle.exe'
    $light = Join-Path $root 'light.exe'
    if ((Test-Path $heat) -and (Test-Path $candle) -and (Test-Path $light)) {
      return $true
    }
  }

  return $false
}

function Get-Sha256Hex([string]$FilePath) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $stream = [System.IO.File]::OpenRead($FilePath)
    try {
      $hashBytes = $sha.ComputeHash($stream)
      return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    } finally {
      $stream.Dispose()
    }
  } finally {
    $sha.Dispose()
  }
}

function Expand-ZipFile([string]$ZipPath, [string]$DestinationPath) {
  if (Test-Path $DestinationPath) {
    Remove-Item -Path $DestinationPath -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null

  $expandArchive = Get-Command Expand-Archive -ErrorAction SilentlyContinue
  if ($expandArchive) {
    Expand-Archive -Path $ZipPath -DestinationPath $DestinationPath -Force
    return
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestinationPath)
}

function Install-WixPortable {
  $version = '3.14.1'
  $url = 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip'
  $expectedSha256 = '6ac824e1642d6f7277d0ed7ea09411a508f6116ba6fae0aa5f2c7daa2ff43d31'

  $cacheDir = Join-Path (Join-Path $repoRootPath '.tool') 'cache\wix'
  $installRoot = Join-Path (Join-Path $repoRootPath '.tool') 'wix3'
  $versionDir = Join-Path $installRoot $version
  $currentDir = Join-Path $installRoot 'current'
  $zipPath = Join-Path $cacheDir "wix314-binaries-$version.zip"

  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  New-Item -ItemType Directory -Force -Path $installRoot | Out-Null

  if (-not (Test-Path $zipPath)) {
    Write-Host "Downloading WiX Toolset v3 zip: $url"
    $invokeParams = @{ Uri = $url; OutFile = $zipPath }
    if ($PSVersionTable.PSVersion.Major -le 5) {
      $invokeParams.UseBasicParsing = $true
    }
    Invoke-WebRequest @invokeParams
  }

  $actualSha256 = Get-Sha256Hex $zipPath
  if ($actualSha256 -ne $expectedSha256) {
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    throw "WiX zip hash mismatch. Expected $expectedSha256, got $actualSha256."
  }

  Write-Host "Extracting WiX Toolset v3 to $versionDir"
  Expand-ZipFile -ZipPath $zipPath -DestinationPath $versionDir

  if (Test-Path $currentDir) {
    Remove-Item -Path $currentDir -Recurse -Force
  }

  New-Item -ItemType SymbolicLink -Path $currentDir -Target $versionDir -ErrorAction SilentlyContinue | Out-Null
  if (-not (Test-Path $currentDir)) {
    Copy-Item -Path $versionDir -Destination $currentDir -Recurse -Force
  }

  $env:WixToolPath = $currentDir
  Add-PortableWixToPath
}

if (-not (Test-PortableWixReady)) {
  Install-WixPortable
} else {
  $env:WixToolPath = $portableCurrent
}

Add-PortableWixToPath
if (-not (Test-WixReady)) {
  throw 'WiX Toolset v3 install failed. Portable install completed but heat/candle/light are still unavailable.'
}

Write-Host "WiX Toolset v3 is ready at $portableCurrent."
