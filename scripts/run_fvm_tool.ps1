param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('flutter', 'dart')]
  [string]$Tool,

  [Parameter(Mandatory = $true, Position = 1)]
  [string]$Command,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs = @()
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path

$toolPath = switch ($Tool) {
  'flutter' { Join-Path $repoRootPath '.fvm/flutter_sdk/bin/flutter.bat' }
  'dart' { Join-Path $repoRootPath '.fvm/flutter_sdk/bin/dart.bat' }
}

if (-not (Test-Path $toolPath)) {
  Write-Error "SecondLoop: missing $toolPath. Run 'pixi run setup-flutter' first."
  exit 1
}

& $toolPath $Command @CommandArgs
exit $LASTEXITCODE
