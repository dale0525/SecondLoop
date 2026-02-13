$ErrorActionPreference = 'Stop'

param(
  [string]$Publisher = 'CN=SecondLoop Dev',
  [string]$Password = '',
  [string]$OutputDir = 'dist/signing',
  [string]$BaseName = 'secondloop-msix-signing',
  [int]$ValidYears = 3
)

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
  throw 'This script must run on Windows.'
}

if ($ValidYears -lt 1) {
  throw 'ValidYears must be >= 1.'
}

function New-RandomPassword([int]$Length = 32) {
  $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*()_-+=~'.ToCharArray()
  $bytes = New-Object byte[] $Length
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $chars = for ($i = 0; $i -lt $Length; $i++) {
    $alphabet[$bytes[$i] % $alphabet.Length]
  }
  return -join $chars
}

if (-not $Password) {
  $Password = New-RandomPassword
}

$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$pfxPath = Join-Path $OutputDir ($BaseName + '.pfx')
$cerPath = Join-Path $OutputDir ($BaseName + '.cer')
$base64Path = Join-Path $OutputDir ($BaseName + '.base64.txt')

$cert = New-SelfSignedCertificate `
  -Type Custom `
  -Subject $Publisher `
  -CertStoreLocation 'Cert:\CurrentUser\My' `
  -KeyAlgorithm RSA `
  -KeyLength 2048 `
  -HashAlgorithm SHA256 `
  -KeyUsage DigitalSignature `
  -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3') `
  -NotAfter (Get-Date).AddYears($ValidYears)

Export-PfxCertificate `
  -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
  -FilePath $pfxPath `
  -Password $securePassword | Out-Null

Export-Certificate `
  -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
  -FilePath $cerPath | Out-Null

$base64 = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($pfxPath))
Set-Content -Path $base64Path -Value $base64 -NoNewline

Write-Host ''
Write-Host 'Windows MSIX signing certificate generated.'
Write-Host "PFX: $pfxPath"
Write-Host "CER: $cerPath"
Write-Host "BASE64: $base64Path"
Write-Host ''
Write-Host 'Use these values:'
Write-Host "SECONDLOOP_WINDOWS_MSIX_CERT_PASSWORD=$Password"
Write-Host "SECONDLOOP_WINDOWS_MSIX_PUBLISHER=$Publisher"
Write-Host "SECONDLOOP_WINDOWS_MSIX_CERT_PATH=$pfxPath"
Write-Host ''
Write-Host 'GitHub Actions secrets:'
Write-Host "SECONDLOOP_WINDOWS_MSIX_CERT_BASE64 <= content of $base64Path"
Write-Host "SECONDLOOP_WINDOWS_MSIX_CERT_PASSWORD <= above password"
Write-Host "SECONDLOOP_WINDOWS_MSIX_PUBLISHER <= above publisher"
