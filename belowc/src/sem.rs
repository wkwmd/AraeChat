// BelowCode v1 - Semantics (E1b)
#[inline(always)]
pub fn accumulate_or(acc: u8, state: u8) -> u8 {
    (acc | state) & 0b111
}
