//! Integration tests for cargo-kuu-example.
//!
//! These tests call the kuu WASM bridge via Node.js subprocess.
//! Prerequisites: Node.js v25+ and `moon build --target wasm-gc --release`.

use std::path::Path;
use std::process::Command;

/// Run the cargo-kuu-example binary with given args and return stdout.
fn run_cargo(args: &[&str]) -> (bool, String, String) {
    let binary = Path::new(env!("CARGO_BIN_EXE_cargo-kuu-example"));
    let output = Command::new(binary)
        .args(args)
        .output()
        .expect("failed to execute binary");
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    (output.status.success(), stdout, stderr)
}

// --- build ---

#[test]
fn build_basic() {
    let (ok, stdout, _) = run_cargo(&["build", "--release", "--features", "serde", "-j", "4"]);
    assert!(ok);
    assert!(stdout.contains("[command: build]"));
    assert!(stdout.contains("release: true"));
    assert!(stdout.contains(r#"features: ["serde"]"#));
    assert!(stdout.contains("jobs: 4"));
}

#[test]
fn build_alias() {
    let (ok, stdout, _) = run_cargo(&["b", "--release"]);
    assert!(ok);
    assert!(stdout.contains("[command: build]"));
    assert!(stdout.contains("release: true"));
}

#[test]
fn build_message_format() {
    let (ok, stdout, _) = run_cargo(&["build", "--message-format", "json"]);
    assert!(ok);
    assert!(stdout.contains(r#"message-format: "json""#));
}

#[test]
fn build_invalid_message_format() {
    let (ok, _, stderr) = run_cargo(&["build", "--message-format", "yaml"]);
    assert!(!ok);
    assert!(stderr.contains("Error"));
}

// --- run ---

#[test]
fn run_with_dashdash() {
    let (ok, stdout, _) = run_cargo(&["run", "--bin", "myapp", "--", "--port", "8080"]);
    assert!(ok);
    assert!(stdout.contains("[command: run]"));
    assert!(stdout.contains(r#"bin: "myapp""#));
    assert!(stdout.contains(r#"--: ["--port","8080"]"#));
}

#[test]
fn run_alias() {
    let (ok, stdout, _) = run_cargo(&["r", "--release"]);
    assert!(ok);
    assert!(stdout.contains("[command: run]"));
}

// --- test ---

#[test]
fn test_with_testname_and_dashdash() {
    let (ok, stdout, _) =
        run_cargo(&["test", "integration", "--no-fail-fast", "--", "--nocapture"]);
    assert!(ok);
    assert!(stdout.contains("[command: test]"));
    assert!(stdout.contains(r#"TESTNAME: "integration""#));
    assert!(stdout.contains("no-fail-fast: true"));
    assert!(stdout.contains(r#"--: ["--nocapture"]"#));
}

#[test]
fn test_alias() {
    let (ok, stdout, _) = run_cargo(&["t", "--no-run"]);
    assert!(ok);
    assert!(stdout.contains("[command: test]"));
    assert!(stdout.contains("no-run: true"));
}

// --- check ---

#[test]
fn check_alias() {
    let (ok, stdout, _) = run_cargo(&["c", "-j", "8"]);
    assert!(ok);
    assert!(stdout.contains("[command: check]"));
    assert!(stdout.contains("jobs: 8"));
}

// --- new ---

#[test]
fn new_basic() {
    let (ok, stdout, _) = run_cargo(&["new", "my-project", "--lib", "--edition", "2024"]);
    assert!(ok);
    assert!(stdout.contains("[command: new]"));
    assert!(stdout.contains(r#"path: "my-project""#));
    assert!(stdout.contains("lib: true"));
    assert!(stdout.contains(r#"edition: "2024""#));
}

#[test]
fn new_exclusive_bin_lib() {
    let (ok, _, stderr) = run_cargo(&["new", "my-project", "--bin", "--lib"]);
    assert!(!ok);
    assert!(stderr.contains("Error"));
}

#[test]
fn new_missing_path() {
    let (ok, _, stderr) = run_cargo(&["new"]);
    assert!(!ok);
    assert!(stderr.contains("Error"));
}

#[test]
fn new_vcs_choices() {
    let (ok, stdout, _) = run_cargo(&["new", "proj", "--vcs", "git"]);
    assert!(ok);
    assert!(stdout.contains(r#"vcs: "git""#));
}

#[test]
fn new_invalid_vcs() {
    let (ok, _, stderr) = run_cargo(&["new", "proj", "--vcs", "svn"]);
    assert!(!ok);
    assert!(stderr.contains("Error"));
}

// --- add ---

#[test]
fn add_multiple_deps() {
    let (ok, stdout, _) = run_cargo(&["add", "serde", "tokio", "--features", "derive", "--dev"]);
    assert!(ok);
    assert!(stdout.contains("[command: add]"));
    assert!(stdout.contains(r#"DEP: ["serde","tokio"]"#));
    assert!(stdout.contains("dev: true"));
}

#[test]
fn add_exclusive_source() {
    let (ok, _, stderr) = run_cargo(&["add", "foo", "--path", ".", "--git", "url"]);
    assert!(!ok);
    assert!(stderr.contains("Error"));
}

#[test]
fn add_dry_run() {
    let (ok, stdout, _) = run_cargo(&["add", "serde", "-n"]);
    assert!(ok);
    assert!(stdout.contains("dry-run: true"));
}

// --- remove ---

#[test]
fn remove_basic() {
    let (ok, stdout, _) = run_cargo(&["remove", "old-dep", "--dev", "-n"]);
    assert!(ok);
    assert!(stdout.contains("[command: remove]"));
    assert!(stdout.contains(r#"DEP_ID: ["old-dep"]"#));
    assert!(stdout.contains("dev: true"));
    assert!(stdout.contains("dry-run: true"));
}

#[test]
fn remove_alias() {
    let (ok, stdout, _) = run_cargo(&["rm", "foo"]);
    assert!(ok);
    assert!(stdout.contains("[command: remove]"));
}

// --- clean ---

#[test]
fn clean_basic() {
    let (ok, stdout, _) = run_cargo(&["clean", "--release", "--doc"]);
    assert!(ok);
    assert!(stdout.contains("[command: clean]"));
    assert!(stdout.contains("release: true"));
    assert!(stdout.contains("doc: true"));
}

// --- doc ---

#[test]
fn doc_basic() {
    let (ok, stdout, _) = run_cargo(&["doc", "--open", "--no-deps"]);
    assert!(ok);
    assert!(stdout.contains("[command: doc]"));
    assert!(stdout.contains("open: true"));
    assert!(stdout.contains("no-deps: true"));
}

#[test]
fn doc_alias() {
    let (ok, stdout, _) = run_cargo(&["d"]);
    assert!(ok);
    assert!(stdout.contains("[command: doc]"));
}

// --- global options ---

#[test]
fn verbose_count() {
    let (ok, stdout, _) = run_cargo(&["-vv", "build"]);
    assert!(ok);
    assert!(stdout.contains("verbose: 2"));
}

#[test]
fn color_implicit_value() {
    let (ok, stdout, _) = run_cargo(&["--color", "build"]);
    assert!(ok);
    assert!(stdout.contains(r#"color: "always""#));
}

#[test]
fn color_explicit() {
    let (ok, stdout, _) = run_cargo(&["--color=never", "build"]);
    assert!(ok);
    assert!(stdout.contains(r#"color: "never""#));
}

#[test]
fn color_invalid() {
    let (ok, _, stderr) = run_cargo(&["--color=bright", "build"]);
    assert!(!ok);
    assert!(stderr.contains("Error"));
}

#[test]
fn exclusive_verbose_quiet() {
    let (ok, _, stderr) = run_cargo(&["-v", "-q", "build"]);
    assert!(!ok);
    assert!(stderr.contains("Error"));
}

#[test]
fn locked_frozen_flags() {
    let (ok, stdout, _) = run_cargo(&["--locked", "--frozen", "build"]);
    assert!(ok);
    assert!(stdout.contains("locked: true"));
    assert!(stdout.contains("frozen: true"));
}

#[test]
fn config_append() {
    let (ok, stdout, _) = run_cargo(&["--config", "build.jobs=4", "--config", "net.offline=true", "build"]);
    assert!(ok);
    assert!(stdout.contains(r#"config: ["build.jobs=4","net.offline=true"]"#));
}

// --- help ---

#[test]
fn top_level_help() {
    let (ok, stdout, _) = run_cargo(&["--help"]);
    assert!(ok);
    assert!(stdout.contains("Rust's package manager"));
    assert!(stdout.contains("Commands:"));
    assert!(stdout.contains("build"));
}

#[test]
fn subcommand_help() {
    let (ok, stdout, _) = run_cargo(&["build", "--help"]);
    assert!(ok);
    assert!(stdout.contains("Compile a local package"));
    assert!(stdout.contains("--release"));
}

// --- error cases ---

#[test]
fn unknown_option() {
    let (ok, _, stderr) = run_cargo(&["--nonexistent"]);
    assert!(!ok);
    assert!(stderr.contains("Error"));
}

#[test]
fn unknown_subcommand() {
    let (ok, _, stderr) = run_cargo(&["nonexistent"]);
    assert!(!ok);
    assert!(stderr.contains("Error"));
}
