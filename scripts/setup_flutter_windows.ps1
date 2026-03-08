param()

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
Set-Location $repoRootPath

$flutterPath = Join-Path $repoRootPath '.fvm/flutter_sdk/bin/flutter.bat'

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

Write-Host 'Running: flutter pub get'
& $flutterPath pub get
exit $LASTEXITCODE
