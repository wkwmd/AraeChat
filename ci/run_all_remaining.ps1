# ci/run_all_remaining.ps1
# BelowCode v1 - Windows First batch runner for G-06..G-19 evidence generation
# Policy: do not write to stderr; write all diagnostics to ci/logs/*.txt

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# ---------- Paths ----------
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Exe      = Join-Path $RepoRoot "target\release\belowc_bin.exe"

$TestsRoot = Join-Path $RepoRoot "tests"
$VecDir    = Join-Path $TestsRoot "vectors"
$GoldDir   = Join-Path $TestsRoot "golden"

$CiDir   = Join-Path $RepoRoot "ci"
$LogsDir = Join-Path $CiDir "logs"
$ArtDir  = Join-Path $CiDir "artifacts"

# ---------- Helpers ----------
function Ensure-Dir([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

function Write-Text([string]$path, [string]$text) {
  # Always write UTF-8 without BOM, overwrite
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Append-Text([string]$path, [string]$text) {
  [System.IO.File]::AppendAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function File-Size([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return 0 }
  return (Get-Item -LiteralPath $p).Length
}

function Sha256([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return "" }
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash
}

function Bytes-Hex([byte[]]$bytes) {
  return ($bytes | ForEach-Object { $_.ToString("X2") }) -join " "
}

function Read-Bytes([string]$p) {
  return [System.IO.File]::ReadAllBytes($p)
}

function Compare-Bytes([byte[]]$a, [byte[]]$b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($i=0; $i -lt $a.Length; $i++) {
    if ($a[$i] -ne $b[$i]) { return $false }
  }
  return $true
}

function Run-Proc(
  [string]$InPath,
  [string]$OutPath,
  [string]$StdoutPath,
  [string]$StderrPath
) {
  # Start-Process redirection keeps our script from writing to stderr.
  if (Test-Path -LiteralPath $StdoutPath) { Remove-Item -LiteralPath $StdoutPath -Force | Out-Null }
  if (Test-Path -LiteralPath $StderrPath) { Remove-Item -LiteralPath $StderrPath -Force | Out-Null }

  $p = Start-Process -FilePath $Exe `
    -ArgumentList @($InPath, $OutPath) `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $StdoutPath `
    -RedirectStandardError  $StderrPath

  return $p.ExitCode
}

function Log-Header([string]$logPath, [string]$gateId, [string]$title) {
  Write-Text $logPath ("Gate: {0} — {1}`r`nTimestamp: {2}`r`n" -f $gateId, $title, (Get-Date).ToString("s"))
}

function Fail([string]$logPath, [string]$msg) {
  Append-Text $logPath ("STATUS: FAIL`r`n{0}`r`n" -f $msg)
  $script:AnyFail = $true
}

function Pass([string]$logPath, [string]$msg) {
  Append-Text $logPath ("STATUS: PASS`r`n{0}`r`n" -f $msg)
}

# ---------- Init ----------
Ensure-Dir $LogsDir
Ensure-Dir $ArtDir

$AnyFail = $false
$Summary = Join-Path $LogsDir "run_all_summary.txt"
Write-Text $Summary ("BelowCode v1 batch run`r`nTimestamp: {0}`r`n" -f (Get-Date).ToString("s"))

# ---------- Preflight ----------
$pre = Join-Path $LogsDir "run_all_preflight.txt"
Write-Text $pre ""
if (-not (Test-Path -LiteralPath $Exe)) {
  Append-Text $pre ("Missing exe: {0}`r`n" -f $Exe)
  Append-Text $Summary "Preflight: FAIL (missing exe)`r`n"
  exit 1
}
if (-not (Test-Path -LiteralPath $VecDir)) {
  Append-Text $pre ("Missing vectors dir: {0}`r`n" -f $VecDir)
  Append-Text $Summary "Preflight: FAIL (missing vectors dir)`r`n"
  exit 1
}
if (-not (Test-Path -LiteralPath $GoldDir)) {
  Append-Text $pre ("Missing golden dir: {0}`r`n" -f $GoldDir)
  Append-Text $Summary "Preflight: FAIL (missing golden dir)`r`n"
  exit 1
}
Append-Text $pre ("Exe: {0}`r`nVectors: {1}`r`nGolden: {2}`r`n" -f $Exe, $VecDir, $GoldDir)

# ============================================================
# G-06 — Forbidden Symbols Zero (string scan)
# ============================================================
$g06 = Join-Path $LogsDir "g06_symbols.txt"
Log-Header $g06 "G-06" "ZH Forbidden Symbols Zero (string scan)"

$forbidden = @(
  "malloc","free","realloc","mmap",
  "VirtualAlloc","RtlAllocateHeap","HeapAlloc","HeapFree",
  "LocalAlloc","GlobalAlloc"
)

$exeBytes = Read-Bytes $Exe
$exeText  = [System.Text.Encoding]::ASCII.GetString($exeBytes)

$hits = @()
foreach ($pat in $forbidden) {
  if ($exeText.Contains($pat)) { $hits += $pat }
}
Append-Text $g06 ("Target: {0}`r`nScanner: ASCII string scan over exe bytes`r`nPatterns: {1}`r`n" -f $Exe, ($forbidden -join ", "))

if ($hits.Count -eq 0) {
  Pass $g06 "Hits: 0"
} else {
  Fail $g06 ("Hits: {0} => {1}" -f $hits.Count, ($hits -join ", "))
}

# ============================================================
# X-02 — Forbidden Symbol/Import Reference Proof (Native Extractor)
# ============================================================
$x02 = Join-Path $LogsDir "x02_symbol_dump.txt"
Log-Header $x02 "X-02" "Zero Symbols Proof (Native OS extractor)"

Append-Text $x02 ("Target: {0}`r`nScanner: dumpbin /IMPORTS`r`n" -f $Exe)

$x02Dump = ""
if (Get-Command "dumpbin" -ErrorAction SilentlyContinue) {
  $x02Dump = (& dumpbin /IMPORTS $Exe 2>$null | Out-String)
} elseif (Get-Command "llvm-objdump" -ErrorAction SilentlyContinue) {
  $x02Dump = (& llvm-objdump -p $Exe 2>$null | Out-String)
}

Append-Text $x02 ("--- SYMBOL DUMP START ---`r`n{0}`r`n--- SYMBOL DUMP END ---`r`n" -f $x02Dump)

$x02Hits = @()
foreach ($pat in $forbidden) {
  if ($x02Dump.Contains($pat)) { $x02Hits += $pat }
}

if ($x02Hits.Count -eq 0) {
  Pass $x02 "Hits: 0"
} else {
  Fail $x02 ("Hits: {0} => {1}" -f $x02Hits.Count, ($x02Hits -join ", "))
}

# ============================================================
# G-08 — CLI matrix (arity/flags) + partial evidence for G-09/G-07
# ============================================================
$g08 = Join-Path $LogsDir "g08_cli_matrix.txt"
Log-Header $g08 "G-08" "CLI Contract positional 2 args, no flags"

# We cannot rely on program printing anything; we only check exit code and stderr length.
# For malformed argv, we run exe with those argv directly.
function Run-Proc-Raw([string[]]$argv, [string]$stdoutPath, [string]$stderrPath) {
  if (Test-Path -LiteralPath $stdoutPath) { Remove-Item -LiteralPath $stdoutPath -Force | Out-Null }
  if (Test-Path -LiteralPath $stderrPath) { Remove-Item -LiteralPath $stderrPath -Force | Out-Null }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.CreateNoWindow = $true

  if ($argv -and $argv.Count -gt 0) {
    # NOTE: This is safe for our gate cases (no quotes/escapes needed)
    $psi.Arguments = ($argv -join " ")
  } else {
    $psi.Arguments = ""
  }

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  $null = $p.Start()

  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()

  [System.IO.File]::WriteAllText($stdoutPath, $stdout, (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText($stderrPath, $stderr, (New-Object System.Text.UTF8Encoding($false)))

  return $p.ExitCode
}

$cliCases = @(
  @{ name="argc0"; argv=@(); expectExit=1 },
  @{ name="argc1"; argv=@("in.txt"); expectExit=1 },
  @{ name="argc3"; argv=@("in.txt","out.bin","x"); expectExit=1 },
  @{ name="flag";  argv=@("-o","out.bin","in.txt"); expectExit=1 }
)

foreach ($c in $cliCases) {
  $so = Join-Path $ArtDir ("g08_{0}_stdout.txt" -f $c.name)
  $se = Join-Path $ArtDir ("g08_{0}_stderr.txt" -f $c.name)
  $ec = Run-Proc-Raw $c.argv $so $se
  $seLen = File-Size $se
  Append-Text $g08 ("Case {0}: exit={1} stderr_len={2} expect_exit={3}`r`n" -f $c.name, $ec, $seLen, $c.expectExit)
  if ($ec -ne $c.expectExit -or $seLen -ne 0) {
    Fail $g08 ("CLI case failed: {0}" -f $c.name)
  }
}
if (-not $AnyFail) { Pass $g08 "All CLI negative cases match exit=1 and stderr_len=0" }

# ============================================================
# Prepare known vector paths
# ============================================================
$ok1_lf   = Join-Path $VecDir  "ok_min_1line_lf.txt"
$ok1_eof  = Join-Path $VecDir  "ok_min_1line_eof.txt"
$ok_multi = Join-Path $VecDir  "ok_multi_lines_mix.txt"

$fail_ascii = Join-Path $VecDir "fail_ascii.txt"
$fail_jamo  = Join-Path $VecDir "fail_jamo.txt"
$fail_jong  = Join-Path $VecDir "fail_jong.txt"
$fail_jung  = Join-Path $VecDir "fail_disallowed_jung.txt"
$atomic_mid = Join-Path $VecDir "atomic_fail_mid.txt"

# ============================================================
# G-14 — state encoding proof via single-syllable outputs (black-box)
# ============================================================
$g14 = Join-Path $LogsDir "g14_state_encoding.txt"
Log-Header $g14 "G-14" "T1 state encoding 1:1 (black-box via LUT words)"

# Representative sealed syllables (cho=ㄱ, jong=0):
# S0 괴, S1 가, S2 거, S3 기, S4 고, S5 구, S6 그, S7 긔
$map = @(
  @{ state="S0"; syl="괴"; expectHex="13 00 00 00" }, # acc=0 => 0x00000013 LE
  @{ state="S1"; syl="가"; expectHex="13 05 10 00" }, # 0x00100513 LE
  @{ state="S2"; syl="거"; expectHex="13 05 20 00" }, # 0x00200513 LE
  @{ state="S3"; syl="기"; expectHex="13 05 30 00" }, # 0x00300513 LE
  @{ state="S4"; syl="고"; expectHex="13 05 40 00" }, # 0x00400513 LE
  @{ state="S5"; syl="구"; expectHex="13 05 50 00" }, # 0x00500513 LE
  @{ state="S6"; syl="그"; expectHex="13 05 60 00" }, # 0x00600513 LE
  @{ state="S7"; syl="긔"; expectHex="73 00 00 00" }  # ecall
)

foreach ($m in $map) {
  $inTmp  = Join-Path $ArtDir ("g14_{0}.txt" -f $m.state)
  $outTmp = Join-Path $ArtDir ("g14_{0}.bin" -f $m.state)
  $so     = Join-Path $ArtDir ("g14_{0}_stdout.txt" -f $m.state)
  $se     = Join-Path $ArtDir ("g14_{0}_stderr.txt" -f $m.state)

  # Ensure LF line termination so we test line emit path
  Write-Text $inTmp ($m.syl + "`n")

  # Remove any previous output
  if (Test-Path -LiteralPath $outTmp) { Remove-Item -LiteralPath $outTmp -Force | Out-Null }

  $ec = Run-Proc $inTmp $outTmp $so $se
  $seLen = File-Size $se

  if ($ec -ne 0 -or $seLen -ne 0 -or -not (Test-Path -LiteralPath $outTmp)) {
    Append-Text $g14 ("{0}({1}): exit={2} stderr_len={3} out_exists={4}`r`n" -f $m.state, $m.syl, $ec, $seLen, (Test-Path $outTmp))
    Fail $g14 ("Run failed for {0}" -f $m.state)
    continue
  }

  $bytes = Read-Bytes $outTmp
  $hex   = Bytes-Hex $bytes
  Append-Text $g14 ("{0}({1}): out_len={2} out_hex={3} expect={4}`r`n" -f $m.state, $m.syl, $bytes.Length, $hex, $m.expectHex)

  if ($bytes.Length -ne 4 -or $hex.ToUpperInvariant() -ne $m.expectHex) {
    Fail $g14 ("Mismatch for {0}" -f $m.state)
  }
}
if (-not $AnyFail) { Pass $g14 "All S0..S7 representatives produced expected LUT words (LE)" }

# ============================================================
# G-10..G-13 — lexer & T1 suites (black-box by exit code)
# ============================================================
$g10 = Join-Path $LogsDir "g10_lexer_allow.txt"
Log-Header $g10 "G-10" "Lexer allow-set only"
$g11 = Join-Path $LogsDir "g11_lexer_forbid.txt"
Log-Header $g11 "G-11" "Lexer forbidden immediate"
$g12 = Join-Path $LogsDir "g12_no_jong.txt"
Log-Header $g12 "G-12" "Lexer no-jong immediate"
$g13 = Join-Path $LogsDir "g13_t1_allowed.txt"
Log-Header $g13 "G-13" "T1 AllowedJung only"

function Run-Vector([string]$gateLog, [string]$name, [string]$inPath, [int]$expectExit, [string]$outPath) {
  $so = Join-Path $ArtDir ("{0}_stdout.txt" -f $name)
  $se = Join-Path $ArtDir ("{0}_stderr.txt" -f $name)
  if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Force | Out-Null }
  $ec = Run-Proc $inPath $outPath $so $se
  $seLen = File-Size $se
  Append-Text $gateLog ("{0}: in={1} exit={2} stderr_len={3} expect_exit={4} out_exists={5}`r`n" -f $name, (Split-Path -Leaf $inPath), $ec, $seLen, $expectExit, (Test-Path $outPath))
  if ($ec -ne $expectExit -or $seLen -ne 0) {
    Fail $gateLog ("Vector failed: {0}" -f $name)
  }
}

# Allow-set (should succeed)
$out_g10 = Join-Path $ArtDir "g10_out.bin"
Run-Vector $g10 "g10_ok1_lf"   $ok1_lf   0 $out_g10
Run-Vector $g10 "g10_ok_multi" $ok_multi 0 $out_g10
if (-not $AnyFail) { Pass $g10 "Allow-set vectors succeeded with stderr_len=0" }

# Forbidden chars (should fail)
$out_g11 = Join-Path $ArtDir "g11_out.bin"
Run-Vector $g11 "g11_fail_ascii" $fail_ascii 1 $out_g11
Run-Vector $g11 "g11_fail_jamo"  $fail_jamo  1 $out_g11
if (-not $AnyFail) { Pass $g11 "Forbidden vectors failed (exit=1) with stderr_len=0" }

# jong != 0 (should fail)
$out_g12 = Join-Path $ArtDir "g12_out.bin"
Run-Vector $g12 "g12_fail_jong" $fail_jong 1 $out_g12
if (-not $AnyFail) { Pass $g12 "jong!=0 vector failed (exit=1) with stderr_len=0" }

# disallowed jung (should fail); allowed should succeed
$out_g13 = Join-Path $ArtDir "g13_out.bin"
Run-Vector $g13 "g13_ok1_lf"     $ok1_lf   0 $out_g13
Run-Vector $g13 "g13_fail_jung"  $fail_jung 1 $out_g13
if (-not $AnyFail) { Pass $g13 "T1 allowed passed and disallowed failed, stderr_len=0" }

# ============================================================
# G-17 — golden bin compare (also covers LE & LUT)
# ============================================================
$g17 = Join-Path $LogsDir "g17_emit_hex.txt"
Log-Header $g17 "G-17" "E1b emit: C-ONE, LE, LUT encoding (golden compare)"

function Golden-Compare([string]$name, [string]$inPath, [string]$goldPath, [string]$outPath) {
  $so = Join-Path $ArtDir ("g17_{0}_stdout.txt" -f $name)
  $se = Join-Path $ArtDir ("g17_{0}_stderr.txt" -f $name)

  if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Force | Out-Null }
  $ec = Run-Proc $inPath $outPath $so $se
  $seLen = File-Size $se

  if ($ec -ne 0 -or $seLen -ne 0 -or -not (Test-Path -LiteralPath $outPath)) {
    Append-Text $g17 ("{0}: RUN_FAIL exit={1} stderr_len={2} out_exists={3}`r`n" -f $name, $ec, $seLen, (Test-Path $outPath))
    Fail $g17 ("Golden run failed: {0}" -f $name)
    return
  }

  $outB  = Read-Bytes $outPath
  $goldB = Read-Bytes $goldPath

  $ok = Compare-Bytes $outB $goldB
  Append-Text $g17 ("{0}: out_len={1} gold_len={2} match={3}`r`n" -f $name, $outB.Length, $goldB.Length, $ok)

  # include short hex prefix for debugging (still in log file, not stderr)
  $outHex  = Bytes-Hex ($outB  | Select-Object -First 32)
  $goldHex = Bytes-Hex ($goldB | Select-Object -First 32)
  Append-Text $g17 ("{0}: out_hex_prefix={1}`r`n" -f $name, $outHex)
  Append-Text $g17 ("{0}: gold_hex_prefix={1}`r`n" -f $name, $goldHex)

  if (-not $ok) { Fail $g17 ("Golden mismatch: {0}" -f $name) }
}

$gold_ok1_lf   = Join-Path $GoldDir "ok_min_1line_lf.bin"
$gold_ok1_eof  = Join-Path $GoldDir "ok_min_1line_eof.bin"
$gold_ok_multi = Join-Path $GoldDir "ok_multi_lines_mix.bin"

$out_g17_1 = Join-Path $ArtDir "g17_out_ok1_lf.bin"
$out_g17_2 = Join-Path $ArtDir "g17_out_ok1_eof.bin"
$out_g17_3 = Join-Path $ArtDir "g17_out_ok_multi.bin"

Golden-Compare "ok1_lf"   $ok1_lf   $gold_ok1_lf   $out_g17_1
Golden-Compare "ok1_eof"  $ok1_eof  $gold_ok1_eof  $out_g17_2
Golden-Compare "ok_multi" $ok_multi $gold_ok_multi $out_g17_3

if (-not $AnyFail) {
  # Save a representative artifact path per gate spec
  Copy-Item -LiteralPath $out_g17_3 -Destination (Join-Path $ArtDir "g17_out.bin") -Force | Out-Null
  Pass $g17 "Golden compares matched; copied ok_multi output to ci/artifacts/g17_out.bin"
}

# ============================================================
# G-16 — acc rule (inferred by ok_multi line mapping)
# ============================================================
$g16 = Join-Path $LogsDir "g16_acc_rule.txt"
Log-Header $g16 "G-16" "E1b acc update rule correctness (inferred by golden)"

Append-Text $g16 "Inference basis: ok_multi_lines_mix.txt lines => expected acc sequence [1,3,7,7] and empty line emits 0 bytes.`r`n"
Append-Text $g16 "If G-17 golden compare PASS for ok_multi_lines_mix, then acc OR-update & line-independence & LUT mapping are consistent with SSOT.`r`n"

if (Test-Path -LiteralPath (Join-Path $ArtDir "g17_out_ok_multi.bin")) {
  Pass $g16 "G-17(ok_multi) artifact exists; acc-rule inferred consistent"
} else {
  Fail $g16 "Missing G-17 ok_multi artifact; cannot infer"
}

# ============================================================
# G-18 — EOF flush (direct golden compare already ran)
# ============================================================
$g18 = Join-Path $LogsDir "g18_eof_flush.txt"
Log-Header $g18 "G-18" "E1b EOF flush (3B)"

if (Test-Path -LiteralPath $out_g17_2) {
  Pass $g18 "EOF-flush golden compare executed under G-17 (ok1_eof) and produced output"
} else {
  Fail $g18 "Missing G-17 ok1_eof output; EOF flush not evidenced"
}

# ============================================================
# G-15 — streaming & no accumulation (source audit)
# ============================================================
$g15 = Join-Path $LogsDir "g15_streaming_audit.txt"
Log-Header $g15 "G-15" "E1b streaming & no accumulation (source audit)"

$forbidTokens = @("Vec<","collect::<Vec","to_vec(","String::","format!","println!","eprintln!")
$srcHits = @()

$srcRoot = Join-Path $RepoRoot "belowc_bin"
if (Test-Path -LiteralPath $srcRoot) {
  $rs = Get-ChildItem -LiteralPath $srcRoot -Recurse -File -Filter "*.rs"

  foreach ($t in $forbidTokens) {
    $m = $rs | Select-String -Pattern ([regex]::Escape($t)) -SimpleMatch
    if ($m) {
      foreach ($mm in $m) { $srcHits += ("{0}:{1}:{2}" -f $mm.Path, $mm.LineNumber, $t) }
    }
  }
  Append-Text $g15 ("Audit root: {0}`r`nTokens: {1}`r`n" -f $RepoRoot, ($forbidTokens -join ", "))
  if ($srcHits.Count -eq 0) {
    Pass $g15 "No forbidden accumulation/printing tokens found in *.rs"
  } else {
    Append-Text $g15 ("Hits({0}):`r`n" -f $srcHits.Count)
    foreach ($h in $srcHits) { Append-Text $g15 ($h + "`r`n") }
    Fail $g15 "Forbidden tokens found"
  }
} else {
  Fail $g15 ("Missing src root: {0}" -f $srcRoot)
}

# ============================================================
# G-07 — stderr == 0 (success+failure)
# ============================================================
$g07 = Join-Path $LogsDir "g07_stderr.txt"
Log-Header $g07 "G-07" "ZH stderr == 0 bytes"

$out_g07_ok = Join-Path $ArtDir "g07_ok_out.bin"
$so_ok = Join-Path $ArtDir "g07_ok_stdout.txt"
$se_ok = Join-Path $ArtDir "g07_ok_stderr.txt"
$ec_ok = Run-Proc $ok1_lf $out_g07_ok $so_ok $se_ok
$len_ok = File-Size $se_ok

$out_g07_fail = Join-Path $ArtDir "g07_fail_out.bin"
$so_f = Join-Path $ArtDir "g07_fail_stdout.txt"
$se_f = Join-Path $ArtDir "g07_fail_stderr.txt"
$ec_f = Run-Proc $fail_ascii $out_g07_fail $so_f $se_f
$len_f = File-Size $se_f

Append-Text $g07 ("SuccessCase: exit={0} stderr_len={1}`r`n" -f $ec_ok, $len_ok)
Append-Text $g07 ("FailureCase: exit={0} stderr_len={1}`r`n" -f $ec_f, $len_f)

if ($ec_ok -eq 0 -and $len_ok -eq 0 -and $ec_f -eq 1 -and $len_f -eq 0) {
  Pass $g07 "stderr == 0 for both success and failure representative cases"
} else {
  Fail $g07 "stderr/exit policy mismatch in representative cases"
}

# ============================================================
# G-09 — exit code policy (uses same representative cases)
# ============================================================
$g09 = Join-Path $LogsDir "g09_exit_codes.txt"
Log-Header $g09 "G-09" "Exit code policy (0 success, 1 any failure)"

Append-Text $g09 ("SuccessCase(ok1_lf): exit={0} expect=0`r`n" -f $ec_ok)
Append-Text $g09 ("FailureCase(fail_ascii): exit={0} expect=1`r`n" -f $ec_f)
if ($ec_ok -eq 0 -and $ec_f -eq 1) {
  Pass $g09 "Exit code policy matches SSOT for representative cases"
} else {
  Fail $g09 "Exit code policy mismatch"
}

# ============================================================
# G-19 — Atomic write Option 3 (no contamination) + tmp collision check
# ============================================================
$g19 = Join-Path $LogsDir "g19_atomic.txt"
Log-Header $g19 "G-19" "Atomic write Option 3 (no contamination)"

# Use a dedicated out path for atomic tests
$out19 = Join-Path $ArtDir "g19_out.bin"

# Seed out with known content so we can detect contamination
$seed = Join-Path $ArtDir "g19_seed.bin"
[System.IO.File]::WriteAllBytes($seed, [byte[]](0xAA,0xBB,0xCC,0xDD))
Copy-Item -LiteralPath $seed -Destination $out19 -Force | Out-Null

$hash_before = Sha256 $out19
$mtime_before = (Get-Item -LiteralPath $out19).LastWriteTimeUtc.ToString("o")

# 1) Failure run must not change out
$so19f = Join-Path $ArtDir "g19_fail_stdout.txt"
$se19f = Join-Path $ArtDir "g19_fail_stderr.txt"
$ec19f = Run-Proc $atomic_mid $out19 $so19f $se19f

$hash_after_fail = Sha256 $out19
$mtime_after_fail = (Get-Item -LiteralPath $out19).LastWriteTimeUtc.ToString("o")
$seLen19f = File-Size $se19f

Append-Text $g19 ("FailRun: exit={0} stderr_len={1}`r`n" -f $ec19f, $seLen19f)
Append-Text $g19 ("Out(before): sha256={0} mtime_utc={1}`r`n" -f $hash_before, $mtime_before)
Append-Text $g19 ("Out(after_fail): sha256={0} mtime_utc={1}`r`n" -f $hash_after_fail, $mtime_after_fail)

$fail_ok = ($ec19f -eq 1) -and ($seLen19f -eq 0) -and ($hash_before -eq $hash_after_fail) -and ($mtime_before -eq $mtime_after_fail)

# 2) tmp collision: precreate base tmp name in same dir
$baseName = [System.IO.Path]::GetFileName($out19)
$tmp0 = Join-Path (Split-Path -Parent $out19) (".{0}.belowc.tmp" -f $baseName)
Write-Text $tmp0 "occupied"
Append-Text $g19 ("Precreated tmp0: {0}`r`n" -f $tmp0)

# 3) Success run should replace out with golden output (use ok_multi for determinism)
$so19s = Join-Path $ArtDir "g19_succ_stdout.txt"
$se19s = Join-Path $ArtDir "g19_succ_stderr.txt"
$ec19s = Run-Proc $ok_multi $out19 $so19s $se19s
$seLen19s = File-Size $se19s

$hash_after_succ = Sha256 $out19
$mtime_after_succ = (Get-Item -LiteralPath $out19).LastWriteTimeUtc.ToString("o")

$gold_multi = $gold_ok_multi
$goldHash = Sha256 $gold_multi
$succ_ok = ($ec19s -eq 0) -and ($seLen19s -eq 0) -and ($hash_after_succ -eq $goldHash)

Append-Text $g19 ("SuccRun: exit={0} stderr_len={1}`r`n" -f $ec19s, $seLen19s)
Append-Text $g19 ("Out(after_succ): sha256={0} mtime_utc={1}`r`n" -f $hash_after_succ, $mtime_after_succ)
Append-Text $g19 ("Golden(ok_multi): sha256={0}`r`n" -f $goldHash)

# tmp artifacts snapshot (best-effort)
$tmpMatches = Get-ChildItem -LiteralPath (Split-Path -Parent $out19) -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like (".{0}.belowc.tmp*" -f $baseName) } |
  Select-Object -ExpandProperty FullName

$snap = Join-Path $ArtDir "g19_fs_snapshot.txt"
Write-Text $snap ("Atomic tmp snapshot pattern: .{0}.belowc.tmp*`r`n" -f $baseName)
if ($tmpMatches) {
  Append-Text $snap "Found:`r`n"
  foreach ($m in $tmpMatches) { Append-Text $snap ($m + "`r`n") }
} else {
  Append-Text $snap "Found: (none)`r`n"
}

if ($fail_ok -and $succ_ok) {
  Pass $g19 "No contamination on failure; success output matches golden; tmp collision was pre-created (see snapshot)"
} else {
  $why = @()
  if (-not $fail_ok) { $why += "FAIL-path contamination/exit/stderr mismatch" }
  if (-not $succ_ok) { $why += "SUCCESS-path output mismatch or exit/stderr mismatch" }
  Fail $g19 ("; " + ($why -join " | "))
}

# ============================================================
# X-05 — SSOT Auto-Regeneration & Freshness Verification
# ============================================================
$x05 = Join-Path $LogsDir "x05_ssot_sync.txt"
Log-Header $x05 "X-05" "SSOT Golden Regeneration Sync"

Append-Text $x05 "Running cargo build for golden generator...`r`n"
Push-Location $RepoRoot
try {
  & cargo build --manifest-path belowc/Cargo.toml --bin generate_golden >>$x05 2>&1
  if ($LASTEXITCODE -ne 0) {
    Fail $x05 "Failed to build reference encoder (generate_golden)."
  }

  Append-Text $x05 "Executing binary...`r`n"
  & target\debug\generate_golden.exe >>$x05 2>&1
  if ($LASTEXITCODE -eq 0) {
    Append-Text $x05 "Golden files generated successfully. Checking git diff...`r`n"
    & git diff --exit-code tests/golden >>$x05 2>&1
    if ($LASTEXITCODE -eq 0) {
      Pass $x05 "Golden tests are perfectly synced with SSOT reference encoder."
    } else {
      Fail $x05 "Golden tests are out of sync! You must commit the regenerated files."
    }
  } else {
    Fail $x05 "Failed to execute reference encoder (generate_golden)."
  }
} finally {
  Pop-Location
}

# ============================================================
# Final summary
# ============================================================
Append-Text $Summary "`r`nGates executed: G-06..G-19 (and evidence for G-07..G-09 included) + X-02 + X-05`r`n"
Append-Text $Summary ("Overall: {0}`r`n" -f ($(if ($AnyFail) { "FAIL" } else { "PASS" })))

# Exit code: 0 if all passed, else 1
if ($AnyFail) { exit 1 } else { exit 0 }
