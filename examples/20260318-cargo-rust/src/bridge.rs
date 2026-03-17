//! kuu WASM bridge client.
//!
//! Communicates with kuu's WASM bridge via Node.js subprocess.
//! Input: JSON schema + args → Output: JSON parse result.

use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Deserialize;

/// Error types for the kuu bridge.
#[derive(Debug, thiserror::Error)]
pub enum BridgeError {
    #[error("Node.js not found. Install Node.js v25+ with js-string builtins support.")]
    NodeNotFound,

    #[error("kuu WASM not built. Run `moon build --target wasm-gc --release` first.")]
    WasmNotBuilt,

    #[error("bridge process failed: {0}")]
    ProcessFailed(String),

    #[error("invalid JSON response: {0}")]
    InvalidJson(#[from] serde_json::Error),

    #[error("bridge I/O error: {0}")]
    Io(#[from] std::io::Error),
}

/// Successful parse result from kuu.
#[derive(Debug, Deserialize)]
pub struct ParseSuccess {
    pub values: serde_json::Map<String, serde_json::Value>,
    pub command: Option<CommandResult>,
}

/// A matched subcommand and its parsed values.
#[derive(Debug, Deserialize)]
pub struct CommandResult {
    pub name: String,
    pub values: serde_json::Map<String, serde_json::Value>,
    pub command: Option<Box<CommandResult>>,
}

/// Parse result: either success, help request, or error.
#[derive(Debug)]
pub enum ParseResult {
    Ok(ParseSuccess),
    Help(String),
    Error { message: String, help: Option<String> },
}

/// Resolve the bridge.mjs path relative to the current executable or source.
fn bridge_script_path() -> PathBuf {
    // Try relative to the source directory first (for development)
    let candidates = [
        Path::new(env!("CARGO_MANIFEST_DIR")).join("src/bridge.mjs"),
        PathBuf::from("src/bridge.mjs"),
    ];
    for p in &candidates {
        if p.exists() {
            return p.clone();
        }
    }
    candidates[0].clone()
}

/// Call kuu's WASM bridge with the given JSON input.
pub fn kuu_parse(input: &serde_json::Value) -> Result<ParseResult, BridgeError> {
    let bridge_path = bridge_script_path();

    // Check Node.js availability
    let node = which_node()?;

    let input_json = serde_json::to_string(input)?;

    let output = Command::new(&node)
        .arg(&bridge_path)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            if let Some(ref mut stdin) = child.stdin {
                stdin.write_all(input_json.as_bytes())?;
            }
            drop(child.stdin.take());
            child.wait_with_output()
        })
        .map_err(|e| BridgeError::ProcessFailed(e.to_string()))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(BridgeError::ProcessFailed(format!(
            "exit code {}: {}",
            output.status.code().unwrap_or(-1),
            stderr.trim()
        )));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let raw: serde_json::Value = serde_json::from_str(stdout.trim())?;
    let obj = raw
        .as_object()
        .ok_or_else(|| BridgeError::ProcessFailed("response is not an object".into()))?;

    let ok = obj.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);

    if ok {
        let success: ParseSuccess = serde_json::from_value(raw)?;
        Ok(ParseResult::Ok(success))
    } else if obj
        .get("help_requested")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
    {
        let help = obj
            .get("help")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        Ok(ParseResult::Help(help))
    } else {
        let message = obj
            .get("error")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown error")
            .to_string();
        let help = obj.get("help").and_then(|v| v.as_str()).map(String::from);
        Ok(ParseResult::Error { message, help })
    }
}

fn which_node() -> Result<PathBuf, BridgeError> {
    let output = Command::new("which")
        .arg("node")
        .output()
        .map_err(|_| BridgeError::NodeNotFound)?;
    if output.status.success() {
        let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
        Ok(PathBuf::from(path))
    } else {
        Err(BridgeError::NodeNotFound)
    }
}
