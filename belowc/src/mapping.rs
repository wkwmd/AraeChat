// BelowCode v1 - Mapping (E1b)
pub fn jung_to_state(jung: u32) -> Result<u8, String> {
    // 0:ㅏ, 1:ㅐ, 2:ㅑ, 3:ㅒ, 4:ㅓ, 5:ㅔ, 6:ㅕ, 7:ㅖ
    // Map to S0..S7 based on index
    if jung <= 7 {
        Ok(jung as u8)
    } else {
        Err(format!("Undefined jung index: {}", jung))
    }
}
