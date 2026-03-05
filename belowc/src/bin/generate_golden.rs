use belowc::encode;
use std::fs;
use std::path::{Path, PathBuf};

fn get_repo_root() -> PathBuf {
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    PathBuf::from(manifest_dir).parent().unwrap().to_path_buf()
}

fn main() {
    let repo_root = get_repo_root();
    let vectors_dir = repo_root.join("tests").join("vectors");
    let golden_dir = repo_root.join("tests").join("golden");

    println!("Scanning vectors in {:?}", vectors_dir);
    println!("Emitting golden outputs to {:?}", golden_dir);

    if !golden_dir.exists() {
        fs::create_dir_all(&golden_dir).unwrap();
    }

    let mut success_count = 0;
    
    for entry in fs::read_dir(&vectors_dir).expect("Failed to read vectors directory") {
        let entry = entry.unwrap();
        let path = entry.path();
        
        if path.is_file() && path.extension().and_then(|s| s.to_str()) == Some("txt") {
            let filename = path.file_stem().unwrap().to_str().unwrap();
            
            // Only generate golden binaries for 'ok_' vectors since fail ones don't emit
            if filename.starts_with("ok_") {
                let text = fs::read_to_string(&path).expect("Failed to read text vector");
                match encode(&text) {
                    Ok(bytes) => {
                        let gold_path = golden_dir.join(format!("{}.bin", filename));
                        fs::write(&gold_path, bytes).expect("Failed to write golden binary");
                        println!("Generated golden for {}", filename);
                        success_count += 1;
                    }
                    Err(e) => {
                        eprintln!("Failed to encode golden for {}! Error: {}", filename, e);
                        std::process::exit(1);
                    }
                }
            }
        }
    }
    
    println!("Successfully regenerated {} golden test vectors.", success_count);
}
