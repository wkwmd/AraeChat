param (
    [string]$Gate
)

if ($Gate -eq "G-04") {
    $deps = cargo tree -p belowc_bin --prefix none
    $externalCount = 0
    foreach ($line in $deps) {
        if ($line -match "^belowc_bin " -or $line -match "^belowc " -or $line -match "^core ") {
            continue
        }
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $externalCount++
    }
    
    $out = "Target: belowc_bin`n"
    $out += "External Crates Count: $externalCount`n"
    $out += "Dependencies:`n"
    $out += ($deps | Out-String)
    
    Set-Content -Path "ci/logs/g04_deps.txt" -Value $out
    
    if ($externalCount -eq 0) {
        Write-Host "PASS"
        exit 0
    } else {
        Write-Host "FAIL"
        exit 1
    }
} elseif ($Gate -eq "G-05") {
    Write-Host "Building release for G-05..."
    $buildOut = cargo build --release -p belowc_bin 2>&1
    
    $exePath = "target\release\belowc_bin.exe"
    if (-not (Test-Path $exePath)) {
        Write-Host "FAIL: Exe not found at $exePath"
        exit 1
    }

    $patterns = @("alloc::", "__rust_alloc", "__rust_dealloc", "__rust_realloc", "__rust_alloc_error_handler")
    $hits = 0
    $hitList = @()

    Write-Host "Scanning $exePath..."
    # Read as bytes to avoid encoding issues with binary data, then convert to ASCII string for regex search
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $exePath).Path)
    $chars = [System.Text.Encoding]::ASCII.GetChars($bytes)
    $text = new-object System.String($chars, 0, $chars.Length)
    
    foreach ($pattern in $patterns) {
        if ($text -match [regex]::Escape($pattern)) {
            $hits++
            $hitList += $pattern
        }
    }

    $out = "Target: $exePath`n"
    $out += "Scanner: PowerShell ReadAllBytes String Matching`n"
    $out += "Patterns: $($patterns -join ', ')`n"
    $out += "Hits: $hits`n"
    if ($hits -gt 0) {
        $out += "Hit Patterns: $($hitList -join ', ')`n"
    }
    
    Set-Content -Path "ci/logs/g05_no_alloc.txt" -Value $out
    
    if ($hits -eq 0) {
        Write-Host "PASS"
        exit 0
    } else {
        Write-Host "FAIL"
        exit 1
    }
}
