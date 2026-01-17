$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
Set-Location $repoRootPath

$env:RUST_LOG = 'info'

$flutterBin = Join-Path (Join-Path (Join-Path $repoRootPath '.fvm') 'flutter_sdk') 'bin'
if (Test-Path $flutterBin) {
  $env:PATH = "$flutterBin;$env:PATH"
} else {
  Write-Warning "Flutter bin not found at $flutterBin. Run pixi run setup-flutter first."
}

$cargoBin = Join-Path (Join-Path $env:USERPROFILE '.cargo') 'bin'
if (Test-Path $cargoBin) {
  $env:PATH = "$cargoBin;$env:PATH"
}

& flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
exit $LASTEXITCODE
