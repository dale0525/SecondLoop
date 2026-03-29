param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('flutter', 'dart')]
  [string]$Tool,

  [Parameter(Mandatory = $true, Position = 1)]
  [string]$Command,

  [string]$ToolPath = '',

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs = @()
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'use_windows_short_workspace.ps1')

$repoRootPath = Resolve-SecondLoopProjectDir -DefaultRepoRoot (Join-Path $PSScriptRoot '..')

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

& $toolPath $Command @CommandArgs
exit $LASTEXITCODE
