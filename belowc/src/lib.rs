const LUT: [u32; 8] = [
    0x00000013, 0x00100513, 0x00200513, 0x00300513, 0x00400513, 0x00500513, 0x00600513, 0x00000073,
];

pub fn encode(input: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    let mut acc = 0;
    let mut line_has_valid = false;

    for c in input.chars() {
        if c == '\n' {
            if line_has_valid {
                out.extend_from_slice(&LUT[acc as usize].to_le_bytes());
            }
            acc = 0;
            line_has_valid = false;
        } else if c == ' ' || c == '\t' || c == '\r' {
            continue;
        } else {
            let code = c as u32;
            if code < 0xAC00 || code > 0xD7A3 {
                return Err(format!("Forbidden character: {}", c));
            }

            let s = code - 0xAC00;
            let jong = s % 28;
            if jong != 0 {
                return Err(format!("Forbidden: Jongseong exists in '{}'", c));
            }

            let jung = (s / 28) % 21;
            let state = match jung {
                11 => 0,
                0 => 1,
                4 => 2,
                20 => 3,
                8 => 4,
                13 => 5,
                18 => 6,
                19 => 7,
                _ => return Err(format!("Forbidden jung index: {}", jung)),
            };

            acc = (acc | state) & 0b111;
            line_has_valid = true;
        }
    }

    if line_has_valid {
        out.extend_from_slice(&LUT[acc as usize].to_le_bytes());
    }

    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode_empty() {
        assert_eq!(encode("").unwrap(), vec![]);
    }

    #[test]
    fn test_encode_whitespace() {
        assert_eq!(encode(" \t\r\n \n").unwrap(), vec![]);
    }

    #[test]
    fn test_encode_single_char() {
        // 가 (jung 0 -> state 1)
        assert_eq!(encode("가").unwrap(), LUT[1].to_le_bytes());
    }

    #[test]
    fn test_encode_jong_error() {
        // 각 (jong != 0)
        assert!(encode("각").is_err());
    }

    #[test]
    fn test_encode_invalid_jung() {
        // 개 (jung = 1, not allowed)
        assert!(encode("개").is_err());
    }

    #[test]
    fn test_encode_multi_lines() {
        let input = "가\n거가\n괴긔\n";
        let out = encode(input).unwrap();
        let mut expected = Vec::new();
        // 가: state 1 -> acc 1
        expected.extend_from_slice(&LUT[1].to_le_bytes());
        // 거(2) 가(1): acc = (0|2) | 1 = 3 -> acc 3
        expected.extend_from_slice(&LUT[3].to_le_bytes());
        // 괴(0) 긔(7): acc = (0|0) | 7 = 7 -> acc 7
        expected.extend_from_slice(&LUT[7].to_le_bytes());

        assert_eq!(out, expected);
    }
}
