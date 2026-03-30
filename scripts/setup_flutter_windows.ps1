param()

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

Invoke-InWindowsShortWorkspace -RepoRootPath $repoRootPath -ScriptBlock {
  $repoRootPath = Resolve-SecondLoopProjectDir -DefaultRepoRoot (Join-Path $PSScriptRoot '..')
  Set-Location $repoRootPath

  $flutterPath = Join-Path $repoRootPath '.fvm/flutter_sdk/bin/flutter.bat'
  $flutterRoot = Split-Path -Path (Split-Path -Path $flutterPath -Parent) -Parent

  if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    throw 'SecondLoop: missing dart in PATH. Your pixi environment is not ready. Run `pixi install` and retry `pixi run setup-flutter`.'
  }

  Write-Host 'Running: git config --global core.longpaths true'
  git config --global core.longpaths true
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  if (-not (Test-Path $flutterPath)) {
    Write-Host 'Running: dart pub global activate --no-executables fvm 2.4.1'
    dart pub global activate --no-executables fvm 2.4.1
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }

    Write-Host 'Running: dart pub global run fvm:main install 3.22.3'
    dart pub global run fvm:main install 3.22.3
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }

    Write-Host 'Running: dart pub global run fvm:main use 3.22.3 --force'
    dart pub global run fvm:main use 3.22.3 --force
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }

    if (-not (Test-Path $flutterPath)) {
      Write-Error "SecondLoop: missing $flutterPath after FVM setup."
      exit 1
    }
  } else {
    Write-Host "Using existing local FVM SDK: $flutterPath"
  }

  Set-Item -Path Env:FLUTTER_ROOT -Value $flutterRoot
  Add-ToPathIfMissing -Directory (Join-Path $flutterRoot 'bin')
  Write-Host "Using FLUTTER_ROOT=$flutterRoot"

  Write-Host 'Running: flutter pub get'
  & $flutterPath pub get
  exit $LASTEXITCODE
}
