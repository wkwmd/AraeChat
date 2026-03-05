#![no_std]

/// Streaming output sink to avoid allocation.
/// Guest can implement this as “incremental SHA-256 update + len_out++”.
pub trait ByteSink {
    fn write(&mut self, bytes: &[u8]);
}

#[inline]
fn is_skip(c: char) -> bool {
    c == ' ' || c == '\t' || c == '\r'
}

#[inline]
fn is_newline(c: char) -> bool {
    c == '\n'
}

/// `jung -> state` mapping, sealed by `spec/ssot.lock.md`.
#[inline]
fn jung_to_state(jung: u32) -> Option<u8> {
    match jung {
        11 => Some(0),
        0  => Some(1),
        4  => Some(2),
        20 => Some(3),
        8  => Some(4),
        13 => Some(5),
        18 => Some(6),
        19 => Some(7),
        _ => None,
    }
}

/// Returns state in 0..=7 if valid; otherwise None.
/// Valid iff:
/// - U+AC00..U+D7A3
/// - jong == 0
/// - jung in AllowedJung set (via mapping above)
#[inline]
fn hangul_state(c: char) -> Option<u8> {
    let code = c as u32;
    if !(0xAC00..=0xD7A3).contains(&code) {
        return None;
    }
    let s = code - 0xAC00;
    let jong = s % 28;
    if jong != 0 {
        return None;
    }
    let jung = (s / 28) % 21;
    jung_to_state(jung)
}

/// LUT acc(0..7) -> u32 word, sealed by `spec/ssot.lock.md`.
#[inline]
fn acc_to_word(acc: u8) -> u32 {
    match acc & 7 {
        0 => 0x0000_0013,
        1 => 0x0010_0513,
        2 => 0x0020_0513,
        3 => 0x0030_0513,
        4 => 0x0040_0513,
        5 => 0x0050_0513,
        6 => 0x0060_0513,
        _ => 0x0000_0073, // 7
    }
}

/// Phase-1 validation: ensures the entire input is valid *before* any output is emitted.
/// This matches ZK SSOT semantics: if invalid => exit=1 and out_bytes := empty (no partial output).
pub fn validate(in_bytes: &[u8]) -> bool {
    let Ok(s) = core::str::from_utf8(in_bytes) else { return false; };

    for c in s.chars() {
        if is_skip(c) || is_newline(c) {
            continue;
        }
        if hangul_state(c).is_none() {
            return false;
        }
    }
    true
}

/// Emits output to `sink` using the sealed E1b/LUT semantics.
/// Returns `(exit_flag, len_out_bytes)`.
///
/// Contract:
/// - If input invalid (including non-UTF8), emits nothing and returns (1, 0).
/// - If valid, returns (0, len_out) and emits full output.
pub fn eval(in_bytes: &[u8], sink: &mut dyn ByteSink) -> (u8, u64) {
    let Ok(s) = core::str::from_utf8(in_bytes) else { return (1, 0); };
    if !validate(in_bytes) {
        return (1, 0);
    }

    let mut acc: u8 = 0;
    let mut line_has_valid = false;
    let mut len_out: u64 = 0;

    #[inline]
    fn emit_word(acc: u8, sink: &mut dyn ByteSink, len_out: &mut u64) {
        let w = acc_to_word(acc);
        let le = w.to_le_bytes();
        sink.write(&le);
        *len_out += 4;
    }

    for c in s.chars() {
        if is_skip(c) {
            continue;
        }
        if is_newline(c) {
            if line_has_valid {
                emit_word(acc, sink, &mut len_out);
            }
            acc = 0;
            line_has_valid = false;
            continue;
        }

        let state = hangul_state(c).unwrap();
        acc = (acc | state) & 0b111;
        line_has_valid = true;
    }

    // EOF flush
    if line_has_valid {
        emit_word(acc, sink, &mut len_out);
    }

    (0, len_out)
}
