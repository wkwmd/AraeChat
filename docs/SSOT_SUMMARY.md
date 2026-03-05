# SSOT Summary — BelowCode v1 (`belowc_bin`)

본 문서는 BelowCode v1의 Single Source of Truth(SSOT)를 “사람이 빠르게 검토”할 수 있도록 1장으로 요약한 것이다.  
규칙/상수의 최종 봉인은 `spec/ssot.lock.md`가 정본이며, 본 문서는 그 내용을 설명/요약한다.

- Sealed date (UTC+9): 2026-03-05
- Platforms: Windows / Linux / macOS (의미 동일)

---

## 0) Global invariants (all platforms)

- CLI: `belowc <in> <out>` (positional 2 args, flags 없음)
- Exit code: success `0`, any failure `1`
- stderr: always `0 bytes`
- Memory: `no_std`, no `alloc`, no heap, no external crates
- Streaming: single-pass; no accumulation of input/output
- Output: stream of 32-bit words written **Little-endian**

---

## 1) Lexer / Input acceptance

### Allowed
- Hangul syllables: `U+AC00..U+D7A3`
- Whitespace to skip: `' '`, `'\t'`, `'\r'`
- Newline: `'\n'`

### Forbidden (immediate failure)
- Any character outside the allowed set (ASCII/숫자/기호/자모 포함)
- Any Hangul syllable that has a final consonant (jongseong)

### Hangul decomposition (sealed)
For syllable `code`:
- `s = code - 0xAC00`
- `jong = s % 28`
- `jung = (s / 28) % 21`
- Rule: `jong != 0` ⇒ immediate failure

---

## 2) T1 — AllowedJung & Jung→state mapping

### AllowedJung (exactly 8)
`{ 0, 4, 8, 11, 13, 18, 19, 20 }`  
Outside set ⇒ immediate failure.

### Jung→state (3-bit, sealed)
| jung | state |
|---:|---:|
| 11 | 0 |
| 0  | 1 |
| 4  | 2 |
| 20 | 3 |
| 8  | 4 |
| 13 | 5 |
| 18 | 6 |
| 19 | 7 |

---

## 3) E1b — Streaming accumulation & emission

Per line:
- Start: `acc = 0`, `line_has_valid = false`
- For each valid syllable: `acc = (acc | state) & 0b111`, set `line_has_valid = true`

Emission:
- On `'\n'`:
  - if `line_has_valid`: emit exactly **one** 32-bit word (from `acc`)
  - else: emit nothing
  - reset line state

EOF flush:
- At EOF, if `line_has_valid`: emit exactly **one** 32-bit word

---

## 4) LUT — `acc` (0..7) → `u32` word (sealed)

| acc | word |
|---:|---:|
| 0 | `0x00000013` |
| 1 | `0x00100513` |
| 2 | `0x00200513` |
| 3 | `0x00300513` |
| 4 | `0x00400513` |
| 5 | `0x00500513` |
| 6 | `0x00600513` |
| 7 | `0x00000073` |

Endianness:
- Words are written **Little-endian** to the `.bin` output.

---

## 5) Atomic write — Option 3 (no contamination)

Property:
- Failure path MUST NOT create/modify `out` (no contamination).
- Success path MUST write to a temp file then replace `out` atomically.

Temp naming (same directory as `out`):
- Base: `.<basename>.belowc.tmp`
- Collision: `.<basename>.belowc.tmp.<n>` for `n=1..8`

Unix outcome:
- Exclusive create temp, stream write, (recommended) `fsync`, `rename(temp, out)`, unlink temp on failure.

Windows outcome:
- Create temp, replace-rename using preferred API/fallback, delete temp on failure.

---

## References

- Normative lock: `spec/ssot.lock.md`
- Platform notes: `docs/PLATFORMS.md`
- Unix porting notes: `docs/UNIX_PORTING_REPORT.md`
