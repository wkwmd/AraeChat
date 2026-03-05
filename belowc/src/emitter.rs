// BelowCode v1 - RV32I Emitter (E1b streaming)
use std::io;

#[inline]
pub fn state_to_rv32i_word(state: u8) -> u32 {
    match state & 0b111 {
        7 => 0x0000_0073, // ECALL (Ω)
        s => 0x0000_0013 | (10u32 << 7) | ((s as u32) << 20), // ADDI x10, x0, imm
    }
}

#[inline]
pub fn emit_word<W: io::Write>(mut w: W, state: u8) -> io::Result<()> {
    let word = state_to_rv32i_word(state);
    w.write_all(&word.to_le_bytes())
}
