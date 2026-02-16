param(
  [switch]$DryRun,
  [switch]$SkipPixiEnvs,
  [switch]$SkipFvmSdkLink,
  [switch]$SkipEnvLocalLink,
  [switch]$SkipAndroidKeyLink
)

$ErrorActionPreference = 'Stop'

function Format-Command {
  param([string[]]$Args)

  $quoted = $Args | ForEach-Object {
    if ($_ -match '[\s"]') {
      '"' + ($_.Replace('"', '\"')) + '"'
    } else {
      $_
    }
  }

  return ($quoted -join ' ')
}

function Invoke-Action {
  param(
    [string]$Description,
    [scriptblock]$Action
  )

  if ($DryRun) {
    Write-Host "[dry-run] $Description"
    return
  }

  & $Action
}

function Ensure-Directory {
  param([string]$Path)

  Invoke-Action -Description (Format-Command @('mkdir', '-p', $Path)) -Action {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Remove-Path {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  Invoke-Action -Description (Format-Command @('rm', '-rf', $Path)) -Action {
    $quotedPath = '"' + $Path.Replace('"', '""') + '"'

    if (Test-ReparsePoint -Path $Path) {
      if (Test-Path -LiteralPath $Path -PathType Container) {
        cmd /c "rmdir $quotedPath" | Out-Null
      } else {
        cmd /c "del /f /q $quotedPath" | Out-Null
      }
      if (Test-Path -LiteralPath $Path) {
        throw "Failed to remove reparse point: $Path"
      }
      return
    }

    if (Test-Path -LiteralPath $Path -PathType Container) {
      cmd /c "rmdir /s /q $quotedPath" | Out-Null
      if (Test-Path -LiteralPath $Path) {
        throw "Failed to remove directory: $Path"
      }
      return
    }

    Remove-Item -LiteralPath $Path -Force
  }
}

function Test-ReparsePoint {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $false
  }

  $item = Get-Item -LiteralPath $Path -Force
  return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-DirectoryHasContents {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    return $false
  }

  return [bool](Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-FileSha256Hex {
  param([string]$Path)

  $getFileHashCmd = Get-Command Get-FileHash -ErrorAction SilentlyContinue
  if ($getFileHashCmd) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
  }

  $sha256 = $null
  $stream = $null

  try {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $hashBytes = $sha256.ComputeHash($stream)
    return ([System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant())
  }
  finally {
    if ($stream -ne $null) {
      $stream.Dispose()
    }
    if ($sha256 -ne $null) {
      $sha256.Dispose()
    }
  }
}

function Invoke-Robocopy {
  param(
    [string]$Source,
    [string]$Destination
  )

  $description = Format-Command @('robocopy', $Source, $Destination, '/E')
  Invoke-Action -Description $description -Action {
    robocopy $Source $Destination /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
      throw "robocopy failed with exit code $LASTEXITCODE"
    }
  }
}

function New-DirectoryJunction {
  param(
    [string]$LinkPath,
    [string]$TargetPath
  )

  $description = Format-Command @('cmd', '/c', 'mklink', '/J', $LinkPath, $TargetPath)
  Invoke-Action -Description $description -Action {
    cmd /c "mklink /J `"$LinkPath`" `"$TargetPath`"" | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to create junction: $LinkPath -> $TargetPath"
    }
  }
}

function New-FileLinkOrCopy {
  param(
    [string]$LinkPath,
    [string]$TargetPath,
    [string]$Label
  )

  $hardLinkDescription = Format-Command @('cmd', '/c', 'mklink', '/H', $LinkPath, $TargetPath)
  Invoke-Action -Description $hardLinkDescription -Action {
    cmd /c "mklink /H `"$LinkPath`" `"$TargetPath`"" | Out-Null
    if ($LASTEXITCODE -eq 0) {
      return
    }

    cmd /c "mklink `"$LinkPath`" `"$TargetPath`"" | Out-Null
    if ($LASTEXITCODE -eq 0) {
      return
    }

    Copy-Item -LiteralPath $TargetPath -Destination $LinkPath -Force
    Write-Warning "$Label link fallback: copied file because hard/symbolic link creation failed."
  }
}

function Resolve-PathOrNull {
  param([string]$Path)

  try {
    return (Resolve-Path -LiteralPath $Path).Path
  } catch {
    return $null
  }
}

function Paths-Match {
  param(
    [string]$Left,
    [string]$Right
  )

  $leftResolved = Resolve-PathOrNull -Path $Left
  $rightResolved = Resolve-PathOrNull -Path $Right

  if (-not $leftResolved -or -not $rightResolved) {
    return $false
  }

  return ([string]::Equals($leftResolved, $rightResolved, [System.StringComparison]::OrdinalIgnoreCase))
}

function Link-DirectoryToShared {
  param(
    [string]$LocalPath,
    [string]$SharedPath,
    [string]$Label
  )

  Ensure-Directory -Path $SharedPath
  Ensure-Directory -Path (Split-Path -Parent $LocalPath)

  if (Test-Path -LiteralPath $LocalPath) {
    $item = Get-Item -LiteralPath $LocalPath -Force
    if (-not $item.PSIsContainer) {
      throw "Expected directory for $Label, got non-directory: $LocalPath"
    }

    if (-not (Test-ReparsePoint -Path $LocalPath) -and (Test-DirectoryHasContents -Path $LocalPath)) {
      Write-Host "Migrating existing data for $Label"
      Invoke-Robocopy -Source $LocalPath -Destination $SharedPath
    }

    if (Paths-Match -Left $LocalPath -Right $SharedPath) {
      Write-Host "Already linked: $Label -> $SharedPath"
      return
    }

    Remove-Path -Path $LocalPath
  }

  Write-Host "Linking $Label -> $SharedPath"
  New-DirectoryJunction -LinkPath $LocalPath -TargetPath $SharedPath
}

function Link-DirectoryFromPrimary {
  param(
    [string]$PrimaryRoot,
    [string]$RelativePath,
    [string]$Label
  )

  $primaryPath = Join-Path $PrimaryRoot $RelativePath
  $localPath = Join-Path $repoRoot $RelativePath

  if (-not (Test-Path -LiteralPath $primaryPath -PathType Container)) {
    Write-Host "Skipping $Label link: primary worktree has no $RelativePath ($primaryPath)"
    return
  }

  Ensure-Directory -Path (Split-Path -Parent $localPath)

  if (Test-Path -LiteralPath $localPath) {
    $localItem = Get-Item -LiteralPath $localPath -Force
    if (-not $localItem.PSIsContainer) {
      Write-Host "Keeping existing $Label (not directory): $localPath"
      return
    }

    if (-not (Test-ReparsePoint -Path $localPath)) {
      Write-Host "Keeping existing $Label (not symlink/junction): $localPath"
      return
    }

    if (Paths-Match -Left $localPath -Right $primaryPath) {
      Write-Host "Already linked: $Label -> $primaryPath"
      return
    }

    Write-Host "Updating link for $Label"
    Remove-Path -Path $localPath
  }

  Write-Host "Linking $Label -> $primaryPath"
  New-DirectoryJunction -LinkPath $localPath -TargetPath $primaryPath
}

function Link-FileFromPrimary {
  param(
    [string]$PrimaryRoot,
    [string]$RelativePath,
    [string]$Label
  )

  $primaryPath = Join-Path $PrimaryRoot $RelativePath
  $localPath = Join-Path $repoRoot $RelativePath

  if (-not (Test-Path -LiteralPath $primaryPath -PathType Leaf)) {
    Write-Host "Skipping $Label link: primary worktree has no $RelativePath ($primaryPath)"
    return
  }

  Ensure-Directory -Path (Split-Path -Parent $localPath)

  if (Test-Path -LiteralPath $localPath) {
    if (Paths-Match -Left $localPath -Right $primaryPath) {
      Write-Host "Already linked: $Label -> $primaryPath"
      return
    }

    if (-not (Test-ReparsePoint -Path $localPath)) {
      Write-Host "Keeping existing $Label (not symlink): $localPath"
      return
    }

    Write-Host "Updating link for $Label"
    Remove-Path -Path $localPath
  }

  Write-Host "Linking $Label -> $primaryPath"
  New-FileLinkOrCopy -LinkPath $localPath -TargetPath $primaryPath -Label $Label
}

function Resolve-PrimaryWorktreeRoot {
  $candidate = Resolve-PathOrNull -Path (Join-Path $commonDir '..')
  if (-not $candidate) {
    return $null
  }

  if ([string]::Equals($candidate, $repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $null
  }

  return $candidate
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw 'Missing dependency: git'
}

$repoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) {
  throw 'This script must run inside a git worktree checkout.'
}

$commonDirRaw = (& git -C $repoRoot rev-parse --git-common-dir).Trim()
if ([System.IO.Path]::IsPathRooted($commonDirRaw)) {
  $commonDir = (Resolve-Path -LiteralPath $commonDirRaw).Path
} else {
  $commonDir = (Resolve-Path -LiteralPath (Join-Path $repoRoot $commonDirRaw)).Path
}

$sharedRoot = Join-Path $commonDir 'secondloop-shared'
$sharedTool = Join-Path $sharedRoot '.tool'

$lockFile = Join-Path $repoRoot 'pixi.lock'
if (Test-Path -LiteralPath $lockFile) {
  $lockHash = Get-FileSha256Hex -Path $lockFile
  if ($lockHash.Length -gt 16) {
    $lockHash = $lockHash.Substring(0, 16)
  }
} else {
  $lockHash = 'no-lock'
}

$sharedPixiEnvs = Join-Path $sharedRoot (Join-Path '.pixi-envs' $lockHash)

Write-Host "Repo root: $repoRoot"
Write-Host "Git common dir: $commonDir"
Write-Host "Shared root: $sharedRoot"

Link-DirectoryToShared -LocalPath (Join-Path $repoRoot '.tool') -SharedPath $sharedTool -Label '.tool'

foreach ($obsoletePath in @('.tools', 'tool')) {
  $fullPath = Join-Path $repoRoot $obsoletePath
  if (Test-Path -LiteralPath $fullPath) {
    Write-Host "Removing obsolete $obsoletePath path"
    Remove-Path -Path $fullPath
  }
}

if (-not $SkipPixiEnvs) {
  Link-DirectoryToShared -LocalPath (Join-Path $repoRoot '.pixi/envs') -SharedPath $sharedPixiEnvs -Label '.pixi/envs'
} else {
  Write-Host 'Skipping .pixi/envs linking (--skip-pixi-envs).'
}

$primaryRoot = Resolve-PrimaryWorktreeRoot

if (-not $SkipFvmSdkLink) {
  if ($primaryRoot) {
    Link-DirectoryFromPrimary -PrimaryRoot $primaryRoot -RelativePath '.fvm/flutter_sdk' -Label '.fvm/flutter_sdk'
  } else {
    Write-Host 'Skipping .fvm/flutter_sdk link: current checkout is primary worktree.'
  }
} else {
  Write-Host 'Skipping .fvm/flutter_sdk linking (--skip-fvm-sdk-link).'
}

if (-not $SkipEnvLocalLink) {
  if ($primaryRoot) {
    Link-FileFromPrimary -PrimaryRoot $primaryRoot -RelativePath '.env.local' -Label '.env.local'
  } else {
    Write-Host 'Skipping .env.local link: current checkout is primary worktree.'
  }
} else {
  Write-Host 'Skipping .env.local linking (--skip-env-local-link).'
}

if (-not $SkipAndroidKeyLink) {
  if ($primaryRoot) {
    Link-FileFromPrimary -PrimaryRoot $primaryRoot -RelativePath 'android/key.properties' -Label 'android/key.properties'
    Link-FileFromPrimary -PrimaryRoot $primaryRoot -RelativePath 'android/app/upload-keystore.jks' -Label 'android/app/upload-keystore.jks'
  } else {
    Write-Host 'Skipping Android key linking: current checkout is primary worktree.'
  }
} else {
  Write-Host 'Skipping Android key linking (--skip-android-key-link).'
}

Write-Host 'Done. Shared worktree cache is ready.'
