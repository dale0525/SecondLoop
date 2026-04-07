function Resolve-SecondLoopProjectDir {
  param([string]$DefaultRepoRoot)

  $candidate = ''
  if (-not [string]::IsNullOrWhiteSpace($env:PROJECT_DIR)) {
    $candidate = $env:PROJECT_DIR.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($candidate) -and
      $candidate.Length -gt 2 -and
      -not $candidate.EndsWith(':') -and
      (Test-Path -LiteralPath $candidate)) {
    return (Resolve-Path -LiteralPath $candidate).Path
  }

  return (Resolve-Path -LiteralPath $DefaultRepoRoot).Path
}

function Get-ExistingSubstMappings {
  $mappings = @{}
  $substOutput = @(cmd /c subst 2>$null)
  foreach ($line in $substOutput) {
    if ([string]::IsNullOrWhiteSpace($line) -or -not $line.Contains('=>')) {
      continue
    }

    $parts = $line -split '=>', 2
    if ($parts.Count -ne 2) {
      continue
    }

    $drivePart = $parts[0].Trim()
    $targetPath = $parts[1].Trim()
    if ($drivePart.Length -lt 2 -or [string]::IsNullOrWhiteSpace($targetPath)) {
      continue
    }

    $drive = $drivePart.Substring(0, 2).ToUpperInvariant()
    $mappings[$drive] = $targetPath
  }

  return $mappings
}

function Get-AvailableShortWorkspaceDrive {
  param(
    [string]$PreferredDrive = 'W',
    [string]$TargetPath
  )

  $normalizedTarget = (Resolve-Path -LiteralPath $TargetPath).Path
  $substMappings = Get-ExistingSubstMappings

  foreach ($entry in $substMappings.GetEnumerator()) {
    try {
      $resolvedExistingTarget = (Resolve-Path -LiteralPath $entry.Value).Path
      if ([string]::Equals($resolvedExistingTarget, $normalizedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
        return @{
          Drive = $entry.Key
          NeedsMapping = $false
        }
      }
    } catch {
      continue
    }
  }

  $usedDrives = @{}
  foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
    $usedDrives["$($drive.Name.ToUpperInvariant()):"] = $true
  }
  foreach ($entry in $substMappings.GetEnumerator()) {
    $usedDrives[$entry.Key] = $true
  }

  $preferredNormalized = "$($PreferredDrive.TrimEnd(':').ToUpperInvariant()):"
  $candidateDrives = @(
    $preferredNormalized,
    'W:',
    'X:',
    'Y:',
    'Z:',
    'V:',
    'U:',
    'T:',
    'S:',
    'R:',
    'Q:',
    'P:',
    'O:',
    'N:',
    'M:',
    'L:',
    'K:',
    'J:'
  ) | Select-Object -Unique

  foreach ($candidateDrive in $candidateDrives) {
    if ($usedDrives.ContainsKey($candidateDrive)) {
      continue
    }

    return @{
      Drive = $candidateDrive
      NeedsMapping = $true
    }
  }

  throw "Unable to find an unused drive letter for a short workspace path for $normalizedTarget"
}

function Get-ShortWorkspaceRefRoot {
  $baseRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
  if ([string]::IsNullOrWhiteSpace($baseRoot)) {
    $baseRoot = [System.IO.Path]::GetTempPath()
  }

  $refRoot = Join-Path $baseRoot 'SecondLoop\\secondloop_short_workspace_refs'
  New-Item -ItemType Directory -Force -Path $refRoot | Out-Null
  return $refRoot
}

function Get-ShortWorkspaceRefKey {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [Parameter(Mandatory = $true)]
    [string]$Drive
  )

  $normalizedTarget = (Resolve-Path -LiteralPath $TargetPath).Path.ToLowerInvariant()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedTarget)
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = -join ($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
  }
  finally {
    $sha256.Dispose()
  }

  $normalizedDrive = $Drive.TrimEnd(':').ToUpperInvariant()
  return "$normalizedDrive-$hash"
}

function New-ShortWorkspaceLease {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [Parameter(Mandatory = $true)]
    [string]$Drive,

    [bool]$OwnsMapping = $false
  )

  $refRoot = Get-ShortWorkspaceRefRoot
  $refKey = Get-ShortWorkspaceRefKey -TargetPath $TargetPath -Drive $Drive
  $refDir = Join-Path $refRoot $refKey
  $leasesDir = Join-Path $refDir 'leases'
  $leasePath = Join-Path $leasesDir "$PID"
  $ownerPath = Join-Path $refDir 'owner'

  New-Item -ItemType Directory -Force -Path $leasesDir | Out-Null
  Set-Content -LiteralPath $leasePath -Value $PID -NoNewline

  if ($OwnsMapping) {
    Set-Content -LiteralPath $ownerPath -Value $PID -NoNewline
  }

  return @{
    RefDir = $refDir
    LeasePath = $leasePath
    OwnerPath = $ownerPath
    LeasesDir = $leasesDir
  }
}

function Remove-ShortWorkspaceLease {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Lease,

    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [Parameter(Mandatory = $true)]
    [string]$Drive
  )

  Remove-Item -LiteralPath $Lease.LeasePath -Force -ErrorAction SilentlyContinue

  $remainingLeases = @()
  if (Test-Path -LiteralPath $Lease.LeasesDir -PathType Container) {
    $remainingLeases = @(Get-ChildItem -LiteralPath $Lease.LeasesDir -Force -ErrorAction SilentlyContinue)
  }

  if ((Test-Path -LiteralPath $Lease.OwnerPath -PathType Leaf) -and $remainingLeases.Count -eq 0) {
    $substMappings = Get-ExistingSubstMappings
    $normalizedDrive = "$($Drive.TrimEnd(':').ToUpperInvariant()):"
    $normalizedTarget = (Resolve-Path -LiteralPath $TargetPath).Path
    $currentTarget = $substMappings[$normalizedDrive]
    if ($currentTarget) {
      try {
        $resolvedCurrentTarget = (Resolve-Path -LiteralPath $currentTarget).Path
        if ([string]::Equals($resolvedCurrentTarget, $normalizedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
          cmd /c subst $normalizedDrive /d > $null 2>&1
        }
      }
      catch {
      }
    }

    Remove-Item -LiteralPath $Lease.RefDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-InWindowsShortWorkspace {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRootPath,

    [Parameter(Mandatory = $true)]
    [scriptblock]$ScriptBlock,

    [string]$DriveLetter = ''
  )

  if ([string]::IsNullOrWhiteSpace($DriveLetter)) {
    $DriveLetter = $env:SECONDLOOP_SHORT_WORKSPACE_DRIVE
  }
  if ([string]::IsNullOrWhiteSpace($DriveLetter)) {
    $DriveLetter = 'W'
  }

  $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRootPath).Path
  $workspaceParent = Split-Path -Path $resolvedRepoRoot -Parent
  $workspaceLeaf = Split-Path -Path $resolvedRepoRoot -Leaf
  $substDrive = "$($DriveLetter.TrimEnd(':').ToUpperInvariant()):"
  $shortProjectDir = $resolvedRepoRoot
  $originalProjectDir = $env:PROJECT_DIR
  $shortWorkspaceLease = $null
  $pushedLocation = $false

  try {
    if ($resolvedRepoRoot -like "$substDrive\*") {
      $shortProjectDir = $resolvedRepoRoot
    }
    else {
      $mappingAttempts = 0
      while ($true) {
        $driveSelection = Get-AvailableShortWorkspaceDrive -PreferredDrive $DriveLetter -TargetPath $workspaceParent
        $substDrive = $driveSelection.Drive
        $shortDriveRoot = "$substDrive\"
        $shortProjectDir = "$shortDriveRoot$workspaceLeaf"

        if (-not $driveSelection.NeedsMapping) {
          break
        }

        cmd /c subst $substDrive "$workspaceParent" | Out-Null
        if ($LASTEXITCODE -eq 0) {
          $shortWorkspaceLease = New-ShortWorkspaceLease -TargetPath $workspaceParent -Drive $substDrive -OwnsMapping $true
          break
        }

        $mappingAttempts += 1
        if ($mappingAttempts -ge 8) {
          throw "Failed to map a short workspace drive to $workspaceParent after $mappingAttempts attempts"
        }

        Start-Sleep -Milliseconds 50
      }
    }

    if (-not (Test-Path -LiteralPath $shortProjectDir -PathType Container)) {
      throw "Short workspace path not found: $shortProjectDir"
    }

    if ($null -eq $shortWorkspaceLease) {
      $shortWorkspaceLease = New-ShortWorkspaceLease -TargetPath $workspaceParent -Drive $substDrive
    }

    Set-Item -Path Env:PROJECT_DIR -Value $shortProjectDir
    Push-Location $shortProjectDir
    $pushedLocation = $true
    & $ScriptBlock
  }
  finally {
    if ($pushedLocation) {
      Pop-Location
    }

    if ($null -eq $originalProjectDir -or [string]::IsNullOrWhiteSpace($originalProjectDir)) {
      Remove-Item Env:PROJECT_DIR -ErrorAction SilentlyContinue
    }
    else {
      Set-Item -Path Env:PROJECT_DIR -Value $originalProjectDir
    }

    if ($null -ne $shortWorkspaceLease) {
      Remove-ShortWorkspaceLease -Lease $shortWorkspaceLease -TargetPath $workspaceParent -Drive $substDrive
    }
  }
}
