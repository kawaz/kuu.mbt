//! embed-poc: embed+extract+exec パターンの実動検証 (Rust)。
//!
//! /usr/bin/pwd を include_bytes! で同梱し、展開して実行する。

use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::Command;

const EMBEDDED_CMD: &[u8] = include_bytes!("../bin/embedded-cmd-linux-amd64");

fn main() {
    // 1. embedded バイナリのサイズ確認
    println!("[1] embedded binary loaded: {} bytes", EMBEDDED_CMD.len());

    // 2. キャッシュディレクトリに展開
    let path = match extract_to_cache(EMBEDDED_CMD) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("extract failed: {e}");
            std::process::exit(1);
        }
    };
    println!("[2] extracted to: {}", path.display());

    // 3. 展開したバイナリを exec
    let output = Command::new(&path).output().expect("exec failed");
    let stdout = String::from_utf8_lossy(&output.stdout);
    print!("[3] exec result: {stdout}");

    // 4. 2回目: キャッシュヒット確認
    let path2 = extract_to_cache(EMBEDDED_CMD).expect("second extract failed");
    if path == path2 {
        println!("[4] cache hit confirmed (same path)");
    } else {
        println!("[4] WARNING: cache miss (different path: {})", path2.display());
    }

    println!("\n=== embed+extract+exec: OK ===");
}

fn extract_to_cache(data: &[u8]) -> Result<PathBuf, String> {
    // Simple hash: first 16 hex chars of content
    let hash: String = data.iter().take(8).map(|b| format!("{b:02x}")).collect();

    let cache_dir = std::env::var("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
            PathBuf::from(home).join(".cache")
        })
        .join("kuu-embed-poc");

    std::fs::create_dir_all(&cache_dir).map_err(|e| format!("mkdir: {e}"))?;

    let bin_path = cache_dir.join(format!("cmd-{hash}"));
    if bin_path.exists() {
        return Ok(bin_path); // cache hit
    }

    // Atomic write: temp → rename
    let tmp_path = cache_dir.join(format!("cmd-{hash}.tmp"));
    std::fs::write(&tmp_path, data).map_err(|e| format!("write: {e}"))?;
    std::fs::set_permissions(&tmp_path, std::fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("chmod: {e}"))?;
    std::fs::rename(&tmp_path, &bin_path).map_err(|e| format!("rename: {e}"))?;

    Ok(bin_path)
}
