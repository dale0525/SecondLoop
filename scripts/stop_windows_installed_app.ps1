param(
  [Parameter(Mandatory = $true)]
  [string]$InstallDirName,

  [string]$ExecutableName = 'secondloop.exe',
  [int]$CloseTimeoutSeconds = 10,
  [switch]$TerminateIfNeeded
)

$ErrorActionPreference = 'Stop'

function Get-InstalledExecutablePath {
  param(
    [string]$DirectoryName,
    [string]$FileName
  )

  if (-not $env:LOCALAPPDATA) {
    return ''
  }

  return Join-Path $env:LOCALAPPDATA ("Programs\$DirectoryName\$FileName")
}

function Normalize-PathValue {
  param([string]$PathValue)

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return ''
  }

  return [System.IO.Path]::GetFullPath($PathValue).TrimEnd([char[]]@([char]92, [char]47)).ToLowerInvariant()
}

$expectedExecutablePath = Get-InstalledExecutablePath -DirectoryName $InstallDirName -FileName $ExecutableName
if ([string]::IsNullOrWhiteSpace($expectedExecutablePath)) {
  Write-Warning 'LOCALAPPDATA is unavailable; cannot resolve installed executable path.'
  exit 0
}

$normalizedExpectedExecutablePath = Normalize-PathValue $expectedExecutablePath
if (-not (Test-Path $expectedExecutablePath)) {
  Write-Host "Installed executable not found, nothing to stop: $expectedExecutablePath"
  exit 0
}

$runningInstances = @(
  Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($ExecutableName)) -ErrorAction SilentlyContinue |
    Where-Object {
      $processPath = ''
      try {
        $processPath = $_.Path
      } catch {
        $processPath = ''
      }

      if ([string]::IsNullOrWhiteSpace($processPath)) {
        return $false
      }

      (Normalize-PathValue $processPath) -eq $normalizedExpectedExecutablePath
    }
)

if ($runningInstances.Count -eq 0) {
  Write-Host "No running instance matched installed path: $expectedExecutablePath"
  exit 0
}

$closeTimeoutSeconds = [Math]::Max(0, $CloseTimeoutSeconds)

foreach ($instance in $runningInstances) {
  Write-Host "Stopping app instance at $expectedExecutablePath (PID=$($instance.Id))"

  if ($instance.MainWindowHandle -ne 0) {
    $null = $instance.CloseMainWindow()
    Wait-Process -Id $instance.Id -Timeout $closeTimeoutSeconds -ErrorAction SilentlyContinue
  }

  $isStillRunning = Get-Process -Id $instance.Id -ErrorAction SilentlyContinue
  if ($isStillRunning -and $TerminateIfNeeded) {
    Stop-Process -Id $instance.Id -Force -ErrorAction Stop
    Wait-Process -Id $instance.Id -Timeout $closeTimeoutSeconds -ErrorAction SilentlyContinue
  }
}

exit 0
