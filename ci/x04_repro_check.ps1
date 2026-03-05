# ci/x04_repro_check.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$LockFile = Join-Path $RepoRoot "ci\belowc_identity_windows.lock"

Write-Host "X-04: Cleaning and Rebuilding for Reproducible Identity Check..."
& cargo clean -p belowc_bin
& cargo build --release -p belowc_bin

$Exe = Join-Path $RepoRoot "target\release\belowc_bin.exe"
if (-not (Test-Path -LiteralPath $Exe)) {
  Write-Error "Error: $Exe not built."
  exit 1
}

$Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Exe).Hash.ToLowerInvariant()
Write-Host "Built Hash: $Hash"

if (-not (Test-Path -LiteralPath $LockFile)) {
  Write-Host "Lock file $LockFile not found. Creating it..."
  [System.IO.File]::WriteAllText($LockFile, $Hash, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "You must commit $LockFile."
  exit 1
}

$LockedHash = ([System.IO.File]::ReadAllText($LockFile)).Trim().ToLowerInvariant()
if ($Hash -eq $LockedHash) {
  Write-Host "X-04 Repro Build MATCH! ($Hash)"
  exit 0
} else {
  Write-Host "X-04 Repro Build MISMATCH!"
  Write-Host "Expected: $LockedHash"
  Write-Host "Got     : $Hash"
  exit 1
}
