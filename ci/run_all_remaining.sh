#!/usr/bin/env bash
# ci/run_all_remaining.sh
# BelowCode v1 - Unix batch runner for G-06..G-19 evidence generation
# Policy: do not write to stderr; write all diagnostics to ci/logs/*.txt

set -u
# NOTE: do NOT use 'set -e' because we want to log all failures and return at end.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXE="$REPO_ROOT/target/release/belowc_bin"

TESTS_ROOT="$REPO_ROOT/tests"
VEC_DIR="$TESTS_ROOT/vectors"
GOLD_DIR="$TESTS_ROOT/golden"

CI_DIR="$REPO_ROOT/ci"
LOGS_DIR="$CI_DIR/logs"
ART_DIR="$CI_DIR/artifacts"

ANY_FAIL=0
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

ensure_dir() { [ -d "$1" ] || mkdir -p "$1" >/dev/null 2>/dev/null; }

write_text() {
  # write UTF-8 text
  local p="$1"; shift
  printf "%s" "$*" >"$p" 2>/dev/null
}

append_text() {
  local p="$1"; shift
  printf "%s" "$*" >>"$p" 2>/dev/null
}

file_size() {
  # portable bytes count
  if [ ! -f "$1" ]; then echo 0; return; fi
  wc -c <"$1" 2>/dev/null | tr -d ' '
}

sha256() {
  if [ ! -f "$1" ]; then echo ""; return; fi
  if command -v shasum >/dev/null 2>/dev/null; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print toupper($1)}'
  elif command -v sha256sum >/dev/null 2>/dev/null; then
    sha256sum "$1" 2>/dev/null | awk '{print toupper($1)}'
  else
    echo ""
  fi
}

log_header() {
  local log="$1" gate="$2" title="$3"
  write_text "$log" "Gate: $gate — $title
Timestamp: $TS
"
}

pass() {
  local log="$1"; shift
  append_text "$log" "STATUS: PASS
$*
"
}

fail() {
  local log="$1"; shift
  append_text "$log" "STATUS: FAIL
$*
"
  ANY_FAIL=1
}

# Run belowc with redirections, return exit code.
run_proc() {
  local in_path="$1" out_path="$2" so="$3" se="$4"
  rm -f "$so" "$se" >/dev/null 2>/dev/null
  # IMPORTANT: never print to stderr here
  "$EXE" "$in_path" "$out_path" >"$so" 2>"$se"
  echo $?
}

# Run belowc with raw argv (for CLI negative tests)
run_proc_raw() {
  local so="$1" se="$2"; shift 2
  rm -f "$so" "$se" >/dev/null 2>/dev/null
  "$EXE" "$@" >"$so" 2>"$se"
  echo $?
}

ensure_dir "$LOGS_DIR"
ensure_dir "$ART_DIR"

SUMMARY="$LOGS_DIR/run_all_summary.txt"
write_text "$SUMMARY" "BelowCode v1 batch run
Timestamp: $TS
"

PREFLIGHT="$LOGS_DIR/run_all_preflight.txt"
write_text "$PREFLIGHT" ""
if [ ! -f "$EXE" ]; then
  append_text "$PREFLIGHT" "Missing exe: $EXE
"
  append_text "$SUMMARY" "Preflight: FAIL (missing exe)
"
  exit 1
fi
if [ ! -d "$VEC_DIR" ]; then
  append_text "$PREFLIGHT" "Missing vectors dir: $VEC_DIR
"
  append_text "$SUMMARY" "Preflight: FAIL (missing vectors dir)
"
  exit 1
fi
if [ ! -d "$GOLD_DIR" ]; then
  append_text "$PREFLIGHT" "Missing golden dir: $GOLD_DIR
"
  append_text "$SUMMARY" "Preflight: FAIL (missing golden dir)
"
  exit 1
fi
append_text "$PREFLIGHT" "Exe: $EXE
Vectors: $VEC_DIR
Golden: $GOLD_DIR
"

OK1_LF="$VEC_DIR/ok_min_1line_lf.txt"
OK1_EOF="$VEC_DIR/ok_min_1line_eof.txt"
OK_MULTI="$VEC_DIR/ok_multi_lines_mix.txt"

FAIL_ASCII="$VEC_DIR/fail_ascii.txt"
FAIL_JAMO="$VEC_DIR/fail_jamo.txt"
FAIL_JONG="$VEC_DIR/fail_jong.txt"
FAIL_JUNG="$VEC_DIR/fail_disallowed_jung.txt"
ATOMIC_MID="$VEC_DIR/atomic_fail_mid.txt"

GOLD_OK1_LF="$GOLD_DIR/ok_min_1line_lf.bin"
GOLD_OK1_EOF="$GOLD_DIR/ok_min_1line_eof.bin"
GOLD_OK_MULTI="$GOLD_DIR/ok_multi_lines_mix.bin"

# ============================================================
# G-06 — Forbidden Symbols Zero (string scan over binary)
# ============================================================
G06="$LOGS_DIR/g06_symbols.txt"
log_header "$G06" "G-06" "ZH Forbidden Symbols Zero (string scan)"

FORBIDDEN=("malloc" "free" "realloc" "mmap" "VirtualAlloc" "RtlAllocateHeap" "HeapAlloc" "HeapFree" "LocalAlloc" "GlobalAlloc")
append_text "$G06" "Target: $EXE
Scanner: strings | grep (best-effort)
Patterns: ${FORBIDDEN[*]}
"

# best-effort: strings may not exist on mac by default, so fallback to grep -a.
HITS=()
if command -v strings >/dev/null 2>/dev/null; then
  BIN_TEXT="$(strings "$EXE" 2>/dev/null || true)"
else
  BIN_TEXT="$(LC_ALL=C grep -a -o -E '.{0,200}' "$EXE" 2>/dev/null || true)"
fi

for pat in "${FORBIDDEN[@]}"; do
  if printf "%s" "$BIN_TEXT" | grep -F "$pat" >/dev/null 2>/dev/null; then
    HITS+=("$pat")
  fi
done

if [ "${#HITS[@]}" -eq 0 ]; then
  pass "$G06" "Hits: 0"
else
  fail "$G06" "Hits: ${#HITS[@]} => ${HITS[*]}"
fi

# ============================================================
# X-02 — Forbidden Symbol/Import Reference Proof (Native Extractor)
# ============================================================
X02="$LOGS_DIR/x02_symbol_dump.txt"
log_header "$X02" "X-02" "Zero Symbols Proof (Native OS extractor)"

append_text "$X02" "Target: $EXE
"

X02_HITS=()
X02_DUMP=""
if [ "$(uname)" = "Darwin" ]; then
  append_text "$X02" "Scanner: nm -u (macOS undefined symbols)
"
  X02_DUMP="$(nm -u "$EXE" 2>/dev/null || true)"
else
  append_text "$X02" "Scanner: nm -u (Linux undefined symbols)
"
  X02_DUMP="$(nm -u "$EXE" 2>/dev/null || true)"
fi

append_text "$X02" "--- SYMBOL DUMP START ---
$X02_DUMP
--- SYMBOL DUMP END ---
"

for pat in "${FORBIDDEN[@]}"; do
  if printf "%s" "$X02_DUMP" | grep -F "$pat" >/dev/null 2>/dev/null; then
    X02_HITS+=("$pat")
  fi
done

if [ "${#X02_HITS[@]}" -eq 0 ]; then
  pass "$X02" "Hits: 0"
else
  fail "$X02" "Hits: ${#X02_HITS[@]} => ${X02_HITS[*]}"
fi

# ============================================================
# G-08 — CLI matrix (arity/flags)
# ============================================================
G08="$LOGS_DIR/g08_cli_matrix.txt"
log_header "$G08" "G-08" "CLI Contract positional 2 args, no flags"

declare -a CASES
CASES=("argc0||1" "argc1|in.txt|1" "argc3|in.txt out.bin x|1" "flag|-o out.bin in.txt|1")

for entry in "${CASES[@]}"; do
  name="${entry%%|*}"
  rest="${entry#*|}"
  argv="${rest%%|*}"
  expect="${entry##*|}"

  so="$ART_DIR/g08_${name}_stdout.txt"
  se="$ART_DIR/g08_${name}_stderr.txt"

  if [ -z "$argv" ]; then
    ec="$(run_proc_raw "$so" "$se")"
  else
    # shellcheck disable=SC2086
    ec="$(run_proc_raw "$so" "$se" $argv)"
  fi

  se_len="$(file_size "$se")"
  append_text "$G08" "Case $name: exit=$ec stderr_len=$se_len expect_exit=$expect
"

  if [ "$ec" != "$expect" ] || [ "$se_len" != "0" ]; then
    fail "$G08" "CLI case failed: $name"
  fi
done

# mark pass if no failures were appended in this gate
if ! grep -F "STATUS: FAIL" "$G08" >/dev/null 2>/dev/null; then
  pass "$G08" "All CLI negative cases match exit=1 and stderr_len=0"
fi

# ============================================================
# G-10..G-13 — lexer & T1 (black-box)
# ============================================================
run_vector() {
  local gate_log="$1" name="$2" in_path="$3" expect_exit="$4" out_path="$5"
  local so="$ART_DIR/${name}_stdout.txt"
  local se="$ART_DIR/${name}_stderr.txt"
  rm -f "$out_path" >/dev/null 2>/dev/null

  ec="$(run_proc "$in_path" "$out_path" "$so" "$se")"
  se_len="$(file_size "$se")"
  out_exists=0; [ -f "$out_path" ] && out_exists=1

  append_text "$gate_log" "$name: in=$(basename "$in_path") exit=$ec stderr_len=$se_len expect_exit=$expect_exit out_exists=$out_exists
"
  if [ "$ec" != "$expect_exit" ] || [ "$se_len" != "0" ]; then
    fail "$gate_log" "Vector failed: $name"
  fi
}

G10="$LOGS_DIR/g10_lexer_allow.txt"; log_header "$G10" "G-10" "Lexer allow-set only"
G11="$LOGS_DIR/g11_lexer_forbid.txt"; log_header "$G11" "G-11" "Lexer forbidden immediate"
G12="$LOGS_DIR/g12_no_jong.txt"; log_header "$G12" "G-12" "Lexer no-jong immediate"
G13="$LOGS_DIR/g13_t1_allowed.txt"; log_header "$G13" "G-13" "T1 AllowedJung only"

OUT_G10="$ART_DIR/g10_out.bin"
run_vector "$G10" "g10_ok1_lf" "$OK1_LF" 0 "$OUT_G10"
run_vector "$G10" "g10_ok_multi" "$OK_MULTI" 0 "$OUT_G10"
if ! grep -F "STATUS: FAIL" "$G10" >/dev/null 2>/dev/null; then pass "$G10" "Allow-set vectors succeeded with stderr_len=0"; fi

OUT_G11="$ART_DIR/g11_out.bin"
run_vector "$G11" "g11_fail_ascii" "$FAIL_ASCII" 1 "$OUT_G11"
run_vector "$G11" "g11_fail_jamo" "$FAIL_JAMO" 1 "$OUT_G11"
if ! grep -F "STATUS: FAIL" "$G11" >/dev/null 2>/dev/null; then pass "$G11" "Forbidden vectors failed (exit=1) with stderr_len=0"; fi

OUT_G12="$ART_DIR/g12_out.bin"
run_vector "$G12" "g12_fail_jong" "$FAIL_JONG" 1 "$OUT_G12"
if ! grep -F "STATUS: FAIL" "$G12" >/dev/null 2>/dev/null; then pass "$G12" "jong!=0 vector failed (exit=1) with stderr_len=0"; fi

OUT_G13="$ART_DIR/g13_out.bin"
run_vector "$G13" "g13_ok1_lf" "$OK1_LF" 0 "$OUT_G13"
run_vector "$G13" "g13_fail_jung" "$FAIL_JUNG" 1 "$OUT_G13"
if ! grep -F "STATUS: FAIL" "$G13" >/dev/null 2>/dev/null; then pass "$G13" "T1 allowed passed and disallowed failed, stderr_len=0"; fi

# ============================================================
# G-17 — golden bin compare
# ============================================================
G17="$LOGS_DIR/g17_emit_hex.txt"
log_header "$G17" "G-17" "E1b emit: C-ONE, LE, LUT encoding (golden compare)"

golden_compare() {
  local name="$1" in_path="$2" gold_path="$3" out_path="$4"
  local so="$ART_DIR/g17_${name}_stdout.txt"
  local se="$ART_DIR/g17_${name}_stderr.txt"
  rm -f "$out_path" >/dev/null 2>/dev/null

  ec="$(run_proc "$in_path" "$out_path" "$so" "$se")"
  se_len="$(file_size "$se")"

  if [ "$ec" != "0" ] || [ "$se_len" != "0" ] || [ ! -f "$out_path" ]; then
    append_text "$G17" "$name: RUN_FAIL exit=$ec stderr_len=$se_len out_exists=$([ -f "$out_path" ] && echo 1 || echo 0)
"
    fail "$G17" "Golden run failed: $name"
    return
  fi

  # Compare bytes
  if cmp -s "$out_path" "$gold_path" >/dev/null 2>/dev/null; then
    append_text "$G17" "$name: out_len=$(file_size "$out_path") gold_len=$(file_size "$gold_path") match=true
"
  else
    append_text "$G17" "$name: out_len=$(file_size "$out_path") gold_len=$(file_size "$gold_path") match=false
"
    # write short prefixes for debugging
    out_hex="$(xxd -p -l 32 "$out_path" 2>/dev/null | tr -d '\n' || true)"
    gold_hex="$(xxd -p -l 32 "$gold_path" 2>/dev/null | tr -d '\n' || true)"
    append_text "$G17" "$name: out_hex_prefix=$out_hex
"
    append_text "$G17" "$name: gold_hex_prefix=$gold_hex
"
    fail "$G17" "Golden mismatch: $name"
  fi
}

OUT_G17_1="$ART_DIR/g17_out_ok1_lf.bin"
OUT_G17_2="$ART_DIR/g17_out_ok1_eof.bin"
OUT_G17_3="$ART_DIR/g17_out_ok_multi.bin"

golden_compare "ok1_lf" "$OK1_LF" "$GOLD_OK1_LF" "$OUT_G17_1"
golden_compare "ok1_eof" "$OK1_EOF" "$GOLD_OK1_EOF" "$OUT_G17_2"
golden_compare "ok_multi" "$OK_MULTI" "$GOLD_OK_MULTI" "$OUT_G17_3"

if ! grep -F "STATUS: FAIL" "$G17" >/dev/null 2>/dev/null; then
  cp -f "$OUT_G17_3" "$ART_DIR/g17_out.bin" >/dev/null 2>/dev/null || true
  pass "$G17" "Golden compares matched; copied ok_multi output to ci/artifacts/g17_out.bin"
fi

# ============================================================
# G-16 — acc rule (inferred by ok_multi)
# ============================================================
G16="$LOGS_DIR/g16_acc_rule.txt"
log_header "$G16" "G-16" "E1b acc update rule correctness (inferred by golden)"
append_text "$G16" "Inference basis: ok_multi_lines_mix.txt lines => expected acc sequence [1,3,7,7] and empty line emits 0 bytes.
If G-17 golden compare PASS for ok_multi_lines_mix, then acc OR-update & line-independence & LUT mapping are consistent with SSOT.
"
if [ -f "$OUT_G17_3" ] && ! grep -F "STATUS: FAIL" "$G17" >/dev/null 2>/dev/null; then
  pass "$G16" "G-17(ok_multi) artifact exists and matched; acc-rule inferred consistent"
else
  fail "$G16" "Missing or mismatched G-17 ok_multi artifact; cannot infer"
fi

# ============================================================
# G-18 — EOF flush (already covered by ok1_eof golden compare)
# ============================================================
G18="$LOGS_DIR/g18_eof_flush.txt"
log_header "$G18" "G-18" "E1b EOF flush (3B)"
if [ -f "$OUT_G17_2" ] && ! grep -F "STATUS: FAIL" "$G17" >/dev/null 2>/dev/null; then
  pass "$G18" "EOF-flush golden compare executed under G-17 (ok1_eof) and produced output"
else
  fail "$G18" "Missing/mismatched G-17 ok1_eof output; EOF flush not evidenced"
fi

# ============================================================
# G-15 — streaming & no accumulation (source audit) [belowc_bin only]
# ============================================================
G15="$LOGS_DIR/g15_streaming_audit.txt"
log_header "$G15" "G-15" "E1b streaming & no accumulation (source audit)"
AUDIT_ROOT="$REPO_ROOT/belowc_bin"

TOKENS=("Vec<" "collect::<Vec" "to_vec(" "String::" "format!" "println!" "eprintln!")
append_text "$G15" "Audit root: $AUDIT_ROOT
Tokens: ${TOKENS[*]}
"

if [ ! -d "$AUDIT_ROOT" ]; then
  fail "$G15" "Missing audit root: $AUDIT_ROOT"
else
  H=0
  # grep -R can emit to stderr for permission errors; redirect it to /dev/null
  for t in "${TOKENS[@]}"; do
    if grep -R -n -F "$t" "$AUDIT_ROOT" >/dev/null 2>/dev/null; then
      matches="$(grep -R -n -F "$t" "$AUDIT_ROOT" 2>/dev/null || true)"
      if [ -n "$matches" ]; then
        if [ "$H" -eq 0 ]; then append_text "$G15" "Hits:
"; fi
        append_text "$G15" "$matches
"
        H=1
      fi
    fi
  done

  if [ "$H" -eq 0 ]; then
    pass "$G15" "No forbidden accumulation/printing tokens found in *.rs"
  else
    fail "$G15" "Forbidden tokens found"
  fi
fi

# ============================================================
# G-07 — stderr == 0 bytes (success + failure representative)
# ============================================================
G07="$LOGS_DIR/g07_stderr.txt"
log_header "$G07" "G-07" "ZH stderr == 0 bytes"

OUT_OK="$ART_DIR/g07_ok_out.bin"
SO_OK="$ART_DIR/g07_ok_stdout.txt"
SE_OK="$ART_DIR/g07_ok_stderr.txt"
EC_OK="$(run_proc "$OK1_LF" "$OUT_OK" "$SO_OK" "$SE_OK")"
LEN_OK="$(file_size "$SE_OK")"

OUT_F="$ART_DIR/g07_fail_out.bin"
SO_F="$ART_DIR/g07_fail_stdout.txt"
SE_F="$ART_DIR/g07_fail_stderr.txt"
EC_F="$(run_proc "$FAIL_ASCII" "$OUT_F" "$SO_F" "$SE_F")"
LEN_F="$(file_size "$SE_F")"

append_text "$G07" "SuccessCase: exit=$EC_OK stderr_len=$LEN_OK
FailureCase: exit=$EC_F stderr_len=$LEN_F
"

if [ "$EC_OK" = "0" ] && [ "$LEN_OK" = "0" ] && [ "$EC_F" = "1" ] && [ "$LEN_F" = "0" ]; then
  pass "$G07" "stderr == 0 for both success and failure representative cases"
else
  fail "$G07" "stderr/exit policy mismatch in representative cases"
fi

# ============================================================
# G-09 — exit code policy
# ============================================================
G09="$LOGS_DIR/g09_exit_codes.txt"
log_header "$G09" "G-09" "Exit code policy (0 success, 1 any failure)"
append_text "$G09" "SuccessCase(ok1_lf): exit=$EC_OK expect=0
FailureCase(fail_ascii): exit=$EC_F expect=1
"
if [ "$EC_OK" = "0" ] && [ "$EC_F" = "1" ]; then
  pass "$G09" "Exit code policy matches SSOT for representative cases"
else
  fail "$G09" "Exit code policy mismatch"
fi

# ============================================================
# G-19 — Atomic write Option 3 (no contamination) + tmp collision check
# ============================================================
G19="$LOGS_DIR/g19_atomic.txt"
log_header "$G19" "G-19" "Atomic write Option 3 (no contamination)"

OUT19="$ART_DIR/g19_out.bin"
SEED="$ART_DIR/g19_seed.bin"

# seed out with known bytes
printf "\xAA\xBB\xCC\xDD" >"$SEED" 2>/dev/null
cp -f "$SEED" "$OUT19" >/dev/null 2>/dev/null || true

HASH_BEFORE="$(sha256 "$OUT19")"
MTIME_BEFORE="$(stat -c "%Y" "$OUT19" 2>/dev/null || stat -f "%m" "$OUT19" 2>/dev/null || stat -s "$OUT19" 2>/dev/null | grep -o 'mtime=[0-9]*' | cut -d= -f2 || echo "")"

# 1) failure run must not change out
SO19F="$ART_DIR/g19_fail_stdout.txt"
SE19F="$ART_DIR/g19_fail_stderr.txt"
EC19F="$(run_proc "$ATOMIC_MID" "$OUT19" "$SO19F" "$SE19F")"
LEN19F="$(file_size "$SE19F")"

HASH_AFTER_FAIL="$(sha256 "$OUT19")"
MTIME_AFTER_FAIL="$(stat -c "%Y" "$OUT19" 2>/dev/null || stat -f "%m" "$OUT19" 2>/dev/null || stat -s "$OUT19" 2>/dev/null | grep -o 'mtime=[0-9]*' | cut -d= -f2 || echo "")"

append_text "$G19" "FailRun: exit=$EC19F stderr_len=$LEN19F
Out(before): sha256=$HASH_BEFORE mtime=$MTIME_BEFORE
Out(after_fail): sha256=$HASH_AFTER_FAIL mtime=$MTIME_AFTER_FAIL
"

FAIL_OK=0
if [ "$EC19F" = "1" ] && [ "$LEN19F" = "0" ] && [ "$HASH_BEFORE" = "$HASH_AFTER_FAIL" ] && [ "$MTIME_BEFORE" = "$MTIME_AFTER_FAIL" ]; then
  FAIL_OK=1
fi

# 2) tmp collision: precreate base tmp name in same dir
BASE="$(basename "$OUT19")"
TMP0="$ART_DIR/.${BASE}.belowc.tmp"
write_text "$TMP0" "occupied"
append_text "$G19" "Precreated tmp0: $TMP0
"

# 3) success run should match golden(ok_multi)
SO19S="$ART_DIR/g19_succ_stdout.txt"
SE19S="$ART_DIR/g19_succ_stderr.txt"
EC19S="$(run_proc "$OK_MULTI" "$OUT19" "$SO19S" "$SE19S")"
LEN19S="$(file_size "$SE19S")"

HASH_AFTER_SUCC="$(sha256 "$OUT19")"
MTIME_AFTER_SUCC="$(stat -c "%Y" "$OUT19" 2>/dev/null || stat -f "%m" "$OUT19" 2>/dev/null || stat -s "$OUT19" 2>/dev/null | grep -o 'mtime=[0-9]*' | cut -d= -f2 || echo "")"
GOLD_HASH="$(sha256 "$GOLD_OK_MULTI")"

append_text "$G19" "SuccRun: exit=$EC19S stderr_len=$LEN19S
Out(after_succ): sha256=$HASH_AFTER_SUCC mtime=$MTIME_AFTER_SUCC
Golden(ok_multi): sha256=$GOLD_HASH
"

SUCC_OK=0
if [ "$EC19S" = "0" ] && [ "$LEN19S" = "0" ] && [ "$HASH_AFTER_SUCC" = "$GOLD_HASH" ]; then
  SUCC_OK=1
fi

# tmp snapshot
SNAP="$ART_DIR/g19_fs_snapshot.txt"
write_text "$SNAP" "Atomic tmp snapshot pattern: .${BASE}.belowc.tmp*
"
# list matching tmp artifacts (best-effort)
ls -a "$ART_DIR" 2>/dev/null | grep -E "^\.\Q${BASE}\E\.belowc\.tmp" >>"$SNAP" 2>/dev/null || true

if [ "$FAIL_OK" = "1" ] && [ "$SUCC_OK" = "1" ]; then
  pass "$G19" "No contamination on failure; success output matches golden; tmp collision was pre-created (see snapshot)"
else
  why=""
  if [ "$FAIL_OK" != "1" ]; then why="${why}FAIL-path contamination/exit/stderr mismatch; "; fi
  if [ "$SUCC_OK" != "1" ]; then why="${why}SUCCESS-path output mismatch or exit/stderr mismatch; "; fi
  fail "$G19" "; $why"
fi

append_text "$SUMMARY" "
Gates executed: G-06..G-19 (and evidence for G-07..G-09 included) + X-02
Overall: $( [ "$ANY_FAIL" = "1" ] && echo FAIL || echo PASS )
"

exit "$ANY_FAIL"
