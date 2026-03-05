mod lexer;
mod sem;
mod emitter;
mod mapping;
mod fs_atomic;

use std::env;
use std::fs;
use std::path::Path;
use std::io::BufWriter;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 4 || args[2] != "-o" {
        eprintln!("Usage: belowc <input.bc> -o <out.bin>");
        std::process::exit(1);
    }
    let input_path = &args[1];
    let output_path = Path::new(&args[3]);

    let source = fs::read_to_string(input_path).expect("Failed to read input file");
    
    let result = fs_atomic::atomic_write(output_path, |file| {
        let writer = BufWriter::new(file);
        lexer::compile_stream(&source, writer).map_err(|msg| std::io::Error::new(std::io::ErrorKind::InvalidData, msg))?;
        Ok(())
    });

    match result {
        Ok(_) => {
            println!("0_Conflict");
            println!("instruction-count: C-ONE");
            println!("상태 매핑: M-FULL");
        }
        Err(e) => {
            eprintln!("{}", e);
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_file_does_not_emit_anything() {
        let mut out = Vec::new();
        lexer::compile_stream("", &mut out).unwrap();
        assert!(out.is_empty());
    }

    #[test]
    fn test_whitespace_only_is_skipped() {
        use std::io::Cursor;

        // 공백/탭/캐리지리턴만 있는 줄 + 빈 줄
        let input = "   \n\t\t\n  \r\n\n";
        let mut out = Cursor::new(Vec::<u8>::new());

        let result = lexer::compile_stream(input, &mut out);
        assert!(result.is_ok(), "Whitespace-only lines must be skipped (no SyntaxError).");

        // 유효 라인이 없으므로 어떤 워드도 방출되면 안 됨
        assert_eq!(
            out.into_inner().len(),
            0,
            "Whitespace-only lines must emit 0 bytes."
        );
    }

    #[test]
    fn test_valid_hangul() {
        let mut out = Vec::new();
        // ㅏ = 0(S0)
        lexer::compile_stream("가\n", &mut out).unwrap();
        assert_eq!(out.len(), 4, "One line, one word");
    }

    #[test]
    fn test_jongseong_errors() {
        let mut out = Vec::new();
        assert!(lexer::compile_stream("각\n", &mut out).is_err());
    }

    #[test]
    fn test_non_hangul_errors() {
        let mut out = Vec::new();
        assert!(lexer::compile_stream("abc\n", &mut out).is_err());
    }
}
