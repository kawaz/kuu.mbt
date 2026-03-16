//! kuu-cli embed+extract+exec pattern for Rust.
//!
//! Embeds the kuu-cli binary via `include_bytes!`, extracts to a cache directory
//! on first use, and executes it as a subprocess for CLI argument parsing.
//!
//! # Architecture
//!
//! ```text
//! Host binary (Rust)
//!   └── include_bytes!("bin/kuu-cli")
//!         └── extract to ~/.cache/kuu/kuu-cli-{hash}
//!               └── exec: stdin JSON → stdout JSON
//! ```

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::OnceLock;

// --- Embedded binary ---

// Platform-specific binary selection at compile time.
// In production, use a build.rs to select the right binary.
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
const KUU_CLI_BYTES: Option<&[u8]> = if cfg!(feature = "embed") {
    Some(include_bytes!("../bin/kuu-cli-linux-amd64"))
} else {
    None
};

#[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
const KUU_CLI_BYTES: Option<&[u8]> = None;

static KUU_CLI_PATH: OnceLock<Result<PathBuf, String>> = OnceLock::new();

/// Resolve the kuu-cli binary path. Extracts from embedded bytes or falls back to PATH.
fn resolve_kuu_cli() -> Result<PathBuf, String> {
    KUU_CLI_PATH
        .get_or_init(|| {
            // 1. Try embedded binary
            if let Some(bytes) = KUU_CLI_BYTES {
                return extract_to_cache(bytes);
            }

            // 2. Fall back to PATH
            which_kuu_cli()
        })
        .clone()
}

fn which_kuu_cli() -> Result<PathBuf, String> {
    let output = Command::new("which")
        .arg("kuu-cli")
        .output()
        .map_err(|e| format!("which kuu-cli: {e}"))?;
    if output.status.success() {
        let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
        Ok(PathBuf::from(path))
    } else {
        Err("kuu-cli not found in PATH".to_string())
    }
}

fn extract_to_cache(data: &[u8]) -> Result<PathBuf, String> {
    use std::os::unix::fs::PermissionsExt;

    let hash = {
        // Simple hash for cache key (first 16 bytes of content as hex)
        let preview: Vec<String> = data.iter().take(8).map(|b| format!("{b:02x}")).collect();
        preview.join("")
    };

    let cache_dir = dirs_cache().join("kuu");
    std::fs::create_dir_all(&cache_dir).map_err(|e| format!("create cache dir: {e}"))?;

    let bin_path = cache_dir.join(format!("kuu-cli-{hash}"));
    if bin_path.exists() {
        return Ok(bin_path);
    }

    // Atomic write
    let tmp_path = cache_dir.join(format!("kuu-cli-{hash}.tmp"));
    std::fs::write(&tmp_path, data).map_err(|e| format!("write binary: {e}"))?;
    std::fs::set_permissions(&tmp_path, std::fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("chmod: {e}"))?;
    std::fs::rename(&tmp_path, &bin_path).map_err(|e| format!("rename: {e}"))?;

    Ok(bin_path)
}

fn dirs_cache() -> PathBuf {
    std::env::var("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
            PathBuf::from(home).join(".cache")
        })
}

// --- Schema types (kuu JSON protocol v1) ---

#[derive(Debug, Serialize)]
pub struct Schema {
    pub version: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub opts: Vec<OptDef>,
    pub args: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub require_cmd: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub exclusive: Option<Vec<Vec<String>>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub required: Option<Vec<String>>,
}

#[derive(Debug, Default, Serialize)]
pub struct OptDef {
    pub kind: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub shorts: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub default: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub global: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hidden: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub aliases: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub choices: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub implicit_value: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub opts: Option<Vec<OptDef>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub require_cmd: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ParseResult {
    pub ok: bool,
    pub values: Option<HashMap<String, serde_json::Value>>,
    pub command: Option<CommandResult>,
    pub error: Option<String>,
    pub help: Option<String>,
    pub help_requested: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CommandResult {
    pub name: String,
    pub values: Option<HashMap<String, serde_json::Value>>,
    pub command: Option<Box<CommandResult>>,
}

// --- kuu-cli execution ---

/// Send schema+args to kuu-cli, return parsed result.
pub fn kuu_parse(schema: &Schema) -> Result<ParseResult, String> {
    let kuu_cli = resolve_kuu_cli()?;
    let input = serde_json::to_string(schema).map_err(|e| format!("serialize schema: {e}"))?;

    let mut child = Command::new(&kuu_cli)
        .arg("parse")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|e| format!("spawn kuu-cli: {e}"))?;

    // Write JSON to stdin
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(input.as_bytes())
            .map_err(|e| format!("write to kuu-cli stdin: {e}"))?;
    }

    let output = child
        .wait_with_output()
        .map_err(|e| format!("wait kuu-cli: {e}"))?;

    serde_json::from_slice(&output.stdout)
        .map_err(|e| format!("parse kuu-cli output: {e} (raw: {})", String::from_utf8_lossy(&output.stdout)))
}
