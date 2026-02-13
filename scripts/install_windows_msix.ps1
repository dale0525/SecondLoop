param(
  [Parameter(Mandatory = $true)]
  [string]$MsixPath,

  [string]$CertificatePath = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $MsixPath)) {
  throw "MSIX package not found: $MsixPath"
}

if (-not $CertificatePath) {
  $CertificatePath = [System.IO.Path]::ChangeExtension($MsixPath, '.cer')
}

if (Test-Path $CertificatePath) {
  Import-Certificate -FilePath $CertificatePath -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' | Out-Null
  Write-Host "Imported certificate into CurrentUser\\TrustedPeople: $CertificatePath"
} else {
  Write-Warning "Certificate file not found, skip import: $CertificatePath"
}

Add-AppxPackage -Path $MsixPath
Write-Host "Installed package: $MsixPath"
