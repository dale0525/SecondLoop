param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$ScriptPath,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ScriptArgs = @()
)

$ErrorActionPreference = 'Stop'

function Resolve-GitBash {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRootPath
  )

  $projectCandidates = @(
    (Join-Path $RepoRootPath '.pixi/envs/default/Library/bin/bash.exe'),
    (Join-Path $RepoRootPath '.pixi/envs/default/usr/bin/bash.exe'),
    (Join-Path $RepoRootPath '.pixi/envs/default/bin/bash.exe'),
    (Join-Path $RepoRootPath '.tool/git/bin/bash.exe'),
    (Join-Path $RepoRootPath '.tool/git/usr/bin/bash.exe')
  )
  foreach ($candidate in $projectCandidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  $bashFromPath = Get-Command bash.exe -ErrorAction SilentlyContinue
  if ($bashFromPath -and $bashFromPath.Source -notmatch 'System32|WindowsApps') {
    return $bashFromPath.Source
  }

  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git) {
    $gitCmdDir = Split-Path -Parent $git.Source
    $gitRoot = Split-Path -Parent $gitCmdDir
    $candidate = Join-Path $gitRoot 'bin/bash.exe'
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  $candidates = @(
    'C:/Program Files/Git/bin/bash.exe',
    'C:/Program Files/Git/usr/bin/bash.exe',
    'C:/Program Files (x86)/Git/bin/bash.exe',
    'C:/Program Files (x86)/Git/usr/bin/bash.exe'
  )
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "SecondLoop: Bash runtime not found. Install project-managed bash via pixi/.tool or Git for Windows."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
$resolvedScriptPath = Resolve-Path (Join-Path $repoRootPath $ScriptPath)
$bashExe = Resolve-GitBash -RepoRootPath $repoRootPath

& $bashExe $resolvedScriptPath.Path @ScriptArgs
exit $LASTEXITCODE
