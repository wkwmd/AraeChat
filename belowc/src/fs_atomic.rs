use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub fn tmp_path_for(out: &Path) -> PathBuf {
    let mut s = out.as_os_str().to_os_string();
    s.push(".tmp");
    PathBuf::from(s)
}

/// Write to `out.tmp`, then atomically replace `out` on success.
/// If `f` fails, `out` is not modified (best effort).
pub fn atomic_write<F>(out: &Path, f: F) -> io::Result<()>
where
    F: FnOnce(&mut fs::File) -> io::Result<()>,
{
    let tmp = tmp_path_for(out);

    // 1) create tmp (truncate)
    let mut file = fs::File::create(&tmp)?;
    // 2) do write
    if let Err(e) = f(&mut file) {
        drop(file);
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    // 3) ensure bytes hit OS buffers
    file.sync_all()?;
    drop(file);

    // 4) replace out (Windows-friendly)
    if out.exists() {
        fs::remove_file(out)?;
    }
    fs::rename(&tmp, out)?;

    Ok(())
}
