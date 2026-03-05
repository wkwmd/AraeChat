# SSOT LOCK — BelowCode v1 (Sealed constants & rules)

본 문서는 BelowCode v1의 “변하면 안 되는” 규칙/상수(SSOT)를 사람에게 읽히는 형태로 봉인한다.  
구현은 본 문서와 동치여야 하며, 플랫폼(Windows/Linux/macOS)에 의해 의미가 달라지면 안 된다.

- Sealed date (UTC+9): 2026-03-05
- Scope: Core SSOT (Gates G-01..G-19의 의미를 규정하는 규칙/상수)

---

## 0) Global invariants (All platforms)

| Item | Rule (sealed) |
|---|---|
| CLI | `belowc <in> <out>` exactly 2 positional args, no flags |
| Exit code | success `0`, any failure `1` |
| stderr | always `0 bytes` |
| Memory | `no_std`, no `alloc`, no heap, no external crates |
| Streaming | single-pass, no accumulation of input/output |
| Output | stream of 32-bit words written **Little-endian** |

---

## 1) Lexer / Character acceptance

### Allowed characters (sealed)
- Hangul syllables: `U+AC00 .. U+D7A3`
- Whitespace to skip: `' '`, `'\t'`, `'\r'`
- Newline: `'\n'`

### Forbidden characters (sealed)
- Any character not in the allowed set.
- Any Hangul syllable with a final consonant (jongseong) present.

### Hangul decomposition (sealed)
For syllable `code`:
- `s = code - 0xAC00`
- `jong = s % 28`
- `jung = (s / 28) % 21`
- **Rule:** `jong != 0` ⇒ immediate failure (exit=1, stderr_len=0, no out contamination)

---

## 2) T1 — AllowedJung + Jung→State mapping

### AllowedJung set (sealed)
Exactly the following `jung` indices are accepted:

`{ 0, 4, 8, 11, 13, 18, 19, 20 }`

Anything outside the set ⇒ immediate failure.

### Jung → state (3-bit) mapping (sealed)
Let `state` be a 3-bit value in `[0..7]`.

| `jung` | state |
|---:|---:|
| 11 | 0 |
| 0  | 1 |
| 4  | 2 |
| 20 | 3 |
| 8  |  4 |
| 13 | 5 |
| 18 | 6 |
| 19 | 7 |

Notes:
- `jung=19` maps to state 7 and is treated identically to any other state (no special-case logic).

---

## 3) E1b — Streaming accumulation & emission

### Line state (sealed)
- At the start of each line: `acc = 0`
- Track whether a line has at least one valid syllable: `line_has_valid`

### Accumulation rule (sealed)
For each valid syllable on the line:
- `acc = (acc | state) & 0b111`

### Emission rule (C-ONE) (sealed)
On newline `'\n'`:
- if `line_has_valid == true`: emit **exactly one** 32-bit word derived from `acc`
- if `line_has_valid == false`: emit nothing
- then reset line state for the next line

### EOF flush (sealed)
At end-of-file:
- if `line_has_valid == true`: emit **exactly one** 32-bit word derived from `acc`
- otherwise emit nothing

---

## 4) LUT — `acc` (0..7) → `u32` word

The mapping below is sealed and must be used for emission:

| `acc` | `u32` word |
|---:|---:|
| 0 | `0x00000013` |
| 1 | `0x00100513` |
| 2 | `0x00200513` |
| 3 | `0x00300513` |
| 4 | `0x00400513` |
| 5 | `0x00500513` |
| 6 | `0x00600513` |
| 7 | `0x00000073` |

### Endianness (sealed)
- Words are written to `.bin` in **Little-endian** byte order.

---

## 5) Atomic write — Option 3 (no contamination)

### Core property (sealed)
- Failure path MUST NOT create or modify the output file (`out`) — **no contamination**.
- Success path MUST write to a temporary file, then replace `out` atomically.

### Temporary file naming (sealed)
- The temp file is created in the **same directory** as `out`.
- Base temp name: `.<basename>.belowc.tmp`
- If that exists, try: `.<basename>.belowc.tmp.<n>` for `n = 1..8` (max 8 attempts)

### Unix behavior (sealed outcome)
- Create temp using exclusive creation (e.g., `O_CREAT|O_EXCL`).
- Write stream to temp.
- (Recommended) flush (`fsync`) before rename where possible.
- Atomically replace using `rename(temp, out)`.
- On any failure: delete temp if created; `out` must remain unchanged.

### Windows behavior (sealed outcome)
- Create temp using `CreateFileW`.
- Rename/replace via preferred API, with fallback (e.g., `MoveFileExW(REPLACE_EXISTING|WRITE_THROUGH)`).
- On any failure: delete temp if created; `out` must remain unchanged.

---

## 6) Representative syllable set (informative; not normative)

A common “coverage” set for `jung` mapping with `cho=0` and `jong=0`:

- 괴, 가, 거, 기, 고, 구, 그, 긔

This section is informative; the normative rules are above.

---
End of SSOT LOCK.
