use belowc::encode;
use rand::prelude::*;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const ALLOWED_JUNG: [u32; 8] = [11, 0, 4, 20, 8, 13, 18, 19];
const NUM_CASES: usize = 10_000;
const MAX_LEN: usize = 100;

fn get_bin_path() -> PathBuf {
    let mut path = env!("CARGO_MANIFEST_DIR").to_string();
    path.push_str("/../target/release/belowc_bin");
    if cfg!(target_os = "windows") {
        path.push_str(".exe");
    }
    PathBuf::from(path)
}

fn generate_valid_char(rng: &mut impl Rng) -> char {
    let cho = rng.random_range(0..19);
    let jung = *ALLOWED_JUNG.choose(rng).unwrap();
    let jong = 0;
    let code = 0xAC00 + (cho * 21 * 28) + (jung * 28) + jong;
    char::from_u32(code).unwrap()
}

fn generate_invalid_char(rng: &mut impl Rng) -> char {
    let kind = rng.random_range(0..3);
    match kind {
        0 => {
            // jong != 0
            let cho = rng.random_range(0..19);
            let jung = rng.random_range(0..21);
            let jong = rng.random_range(1..28);
            let code = 0xAC00 + (cho * 21 * 28) + (jung * 28) + jong;
            char::from_u32(code).unwrap()
        }
        1 => {
            // invalid jung (but jong = 0)
            let cho = rng.random_range(0..19);
            let mut jung = rng.random_range(0..21);
            while ALLOWED_JUNG.contains(&jung) {
                jung = rng.random_range(0..21);
            }
            let code = 0xAC00 + (cho * 21 * 28) + (jung * 28) + 0;
            char::from_u32(code).unwrap()
        }
        _ => {
            // completely random non-Hangul or ascii
            let c: u32 = rng.random_range(32..127); // ascii printable
            char::from_u32(c).unwrap_or('A')
        }
    }
}

fn generate_whitespace(rng: &mut impl Rng) -> char {
    let ws = [' ', '\t', '\r', '\n'];
    *ws.choose(rng).unwrap()
}

fn generate_fuzz_case(rng: &mut impl Rng, force_valid: bool) -> String {
    let len = rng.random_range(0..MAX_LEN);
    let mut s = String::with_capacity(len);
    
    for _ in 0..len {
        let r = rng.random_range(0..100);
        if r < 10 {
            s.push(generate_whitespace(rng));
        } else if r < 20 && !force_valid {
            s.push(generate_invalid_char(rng));
        } else {
            s.push(generate_valid_char(rng));
        }
    }
    s
}

#[test]
fn execute_fuzz_against_bin() {
    let bin_path = get_bin_path();
    if !bin_path.exists() {
        println!("Warning: belowc_bin not found at {:?}. Skipping fuzzer (needs to be built in release first).", bin_path);
        return;
    }

    let tmp_dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join("belowc_fuzz");
    let _ = fs::remove_dir_all(&tmp_dir);
    fs::create_dir_all(&tmp_dir).unwrap();

    let mut rng = rand::rng();

    for i in 0..NUM_CASES {
        let force_valid = rng.random_bool(0.7); // 70% chance to be completely valid structure
        let case_str = generate_fuzz_case(&mut rng, force_valid);
        
        // 1. Host reference encoding Result
        let ref_res = encode(&case_str);

        // 2. Binary execution
        let in_file = tmp_dir.join(format!("fuzz_{}.txt", i));
        let out_file = tmp_dir.join(format!("fuzz_{}.bin", i));
        fs::write(&in_file, &case_str).unwrap();

        let output = Command::new(&bin_path)
            .arg(&in_file)
            .arg(&out_file)
            .output()
            .expect("Failed to execute belowc_bin");

        // 3. Compare property
        if let Ok(expected_bytes) = ref_res {
            // Reference succeeded => bin must exit 0 and bytes MUST match exactly.
            assert!(
                output.status.success(),
                "Case {}: Ref succeeded but bin failed with code {:?}! err length: {}\ninput (bytes): {:?}",
                i, output.status.code(), output.stderr.len(), case_str.as_bytes()
            );

            let actual_bytes = match fs::read(&out_file) {
                Ok(b) => b,
                Err(_) => vec![], // If no output emitted (len 0), file might not be created per atomic tests
            };

            assert_eq!(
                expected_bytes, actual_bytes,
                "Case {}: Binary output data mismatch!",
                i
            );
        } else {
            // Reference failed => bin must exit 1.
            assert!(
                !output.status.success(),
                "Case {}: Ref failed but bin SUCCESS with code {:?}! input (bytes): {:?}",
                i, output.status.code(), case_str.as_bytes()
            );
        }

        // Cleanup to prevent disk from filling up
        let _ = fs::remove_file(&in_file);
        let _ = fs::remove_file(&out_file);
    }
    
    let _ = fs::remove_dir_all(&tmp_dir);
}
