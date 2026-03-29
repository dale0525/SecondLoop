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

function Invoke-InWindowsShortWorkspace {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRootPath,

    [Parameter(Mandatory = $true)]
    [scriptblock]$ScriptBlock,

    [string]$DriveLetter = 'W'
  )

  $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRootPath).Path
  $workspaceParent = Split-Path -Path $resolvedRepoRoot -Parent
  $workspaceLeaf = Split-Path -Path $resolvedRepoRoot -Leaf
  $substDrive = "$($DriveLetter.TrimEnd(':')):"
  $shortDriveRoot = "$substDrive\"
  $shortProjectDir = "$shortDriveRoot$workspaceLeaf"
  $originalProjectDir = $env:PROJECT_DIR
  $mappedDrive = $false
  $pushedLocation = $false

  try {
    if ($resolvedRepoRoot -notlike "$substDrive\*") {
      cmd /c subst $substDrive /d > $null 2>&1
      cmd /c subst $substDrive "$workspaceParent" | Out-Null
      if ($LASTEXITCODE -ne 0) {
        throw "Failed to map short workspace drive $substDrive to $workspaceParent"
      }
      $mappedDrive = $true
    }

    if (-not (Test-Path -LiteralPath $shortProjectDir -PathType Container)) {
      throw "Short workspace path not found: $shortProjectDir"
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

    if ($mappedDrive) {
      cmd /c subst $substDrive /d > $null 2>&1
    }
  }
}
