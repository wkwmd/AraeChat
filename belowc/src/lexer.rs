// BelowCode v1 - Streaming Compiler Front (E1b)
// NOTE: LineBufferForbidden + ResultBufferForbidden
use crate::mapping::jung_to_state;
use crate::sem::accumulate_or;
use crate::emitter::emit_word;
use std::io;

pub fn compile_stream<W: io::Write>(input: &str, mut out: W) -> Result<(), String> {
    let mut acc: u8 = 0;
    let mut has_valid_char = false;

    // We must treat '\n' as line boundary, and also emit at EOF if last line has data.
    for (idx, c) in input.char_indices() {
        match c {
            '\r' | ' ' | '\t' => continue,

            '\n' => {
                if has_valid_char {
                    emit_word(&mut out, acc).map_err(|e| format!("IOError at byte {}: {}", idx, e))?;
                    acc = 0;
                    has_valid_char = false;
                }
            }

            '가'..='힣' => {
                let base = c as u32 - 0xAC00;
                let jung = (base % 588) / 28;
                let jong = base % 28;

                if jong != 0 {
                    return Err(format!("SyntaxError at byte {}: 종성 금지", idx));
                }

                let state = jung_to_state(jung)
                    .map_err(|e| format!("SyntaxError at byte {}: {}", idx, e))?;

                acc = accumulate_or(acc, state);
                has_valid_char = true;
            }

            _ => return Err(format!("SyntaxError at byte {}: 비한글 기호 금지 '{}'", idx, c)),
        }
    }

    // EOF flush (no trailing '\n' required)
    if has_valid_char {
        emit_word(&mut out, acc).map_err(|e| format!("IOError at EOF: {}", e))?;
    }

    Ok(())
}
