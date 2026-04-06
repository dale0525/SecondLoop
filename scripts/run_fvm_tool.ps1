param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('flutter', 'dart')]
  [string]$Tool,

  [string]$Command = '',
  [string]$ToolPath = '',
  [string]$WorkingDirectory = '',
  [string]$ArgumentsFile = '',
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs = @()
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'use_windows_short_workspace.ps1')

$defaultRepoRootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoRootPath = Resolve-SecondLoopProjectDir -DefaultRepoRoot $defaultRepoRootPath

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

function Resolve-ExecutionWorkingDirectory {
  param(
    [string]$RepoRootPath,
    [string]$WorkingDirectory
  )

  if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    return ''
  }

  if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
    Write-Error "SecondLoop: working directory not found: $WorkingDirectory"
    exit 1
  }

  $resolvedWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
  $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRootPath).Path
  $projectDir = $env:PROJECT_DIR
  if ([string]::IsNullOrWhiteSpace($projectDir) -or
      -not (Test-Path -LiteralPath $projectDir -PathType Container)) {
    return $resolvedWorkingDirectory
  }

  $resolvedProjectDir = (Resolve-Path -LiteralPath $projectDir).Path
  if ([string]::Equals($resolvedWorkingDirectory, $resolvedRepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $resolvedProjectDir
  }

  $repoRootWithSeparator = if ($resolvedRepoRoot.EndsWith('\')) {
    $resolvedRepoRoot
  } else {
    "$resolvedRepoRoot\"
  }

  if (-not $resolvedWorkingDirectory.StartsWith($repoRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $resolvedWorkingDirectory
  }

  $relativeWorkingPath = $resolvedWorkingDirectory.Substring($repoRootWithSeparator.Length)
  $resolvedShortWorkingDirectory = Join-Path $resolvedProjectDir $relativeWorkingPath
  if (Test-Path -LiteralPath $resolvedShortWorkingDirectory -PathType Container) {
    return $resolvedShortWorkingDirectory
  }

  return $resolvedWorkingDirectory
}

function Read-ArgumentFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Error "SecondLoop: argument file not found: $Path"
    exit 1
  }

  $rawBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
  if ($rawBytes.Length -eq 0) {
    return @()
  }

  $decoded = [System.Text.Encoding]::UTF8.GetString($rawBytes)
  return @(
    $decoded.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries)
  )
}

Invoke-InWindowsShortWorkspace -RepoRootPath $repoRootPath -ScriptBlock {
  $repoRootPath = Resolve-SecondLoopProjectDir -DefaultRepoRoot (Join-Path $PSScriptRoot '..')

  $resolvedCommand = @()
  if (-not [string]::IsNullOrWhiteSpace($ArgumentsFile)) {
    $resolvedCommand = Read-ArgumentFile -Path $ArgumentsFile
  } elseif (-not [string]::IsNullOrWhiteSpace($Command)) {
    $resolvedCommand = @($Command) + $CommandArgs
  }

  if ($resolvedCommand.Count -eq 0) {
    Write-Error 'SecondLoop: missing tool command.'
    exit 1
  }

  if ($ToolPath -ne '') {
    if (-not (Test-Path $ToolPath)) {
      Write-Error "SecondLoop: missing $ToolPath. Run 'pixi run setup-flutter' first."
      exit 1
    }

    $resolvedToolPath = Resolve-Path $ToolPath
    $toolPath = $resolvedToolPath.Path
  } else {
    $toolPath = switch ($Tool) {
      'flutter' { Join-Path $repoRootPath '.fvm/flutter_sdk/bin/flutter.bat' }
      'dart' { Join-Path $repoRootPath '.fvm/flutter_sdk/bin/dart.bat' }
    }
  }

  if (-not (Test-Path $toolPath)) {
    Write-Error "SecondLoop: missing $toolPath. Run 'pixi install' and then 'pixi run setup-flutter'."
    exit 1
  }

  $flutterRoot = Join-Path $repoRootPath '.fvm/flutter_sdk'
  if (Test-Path -LiteralPath $flutterRoot -PathType Container) {
    Set-Item -Path Env:FLUTTER_ROOT -Value $flutterRoot
    Add-ToPathIfMissing -Directory (Join-Path $flutterRoot 'bin')
  }

  if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    $executionWorkingDirectory = Resolve-ExecutionWorkingDirectory -RepoRootPath $defaultRepoRootPath -WorkingDirectory $WorkingDirectory
    Set-Location $executionWorkingDirectory
  }

  & $toolPath @resolvedCommand
  exit $LASTEXITCODE
}
