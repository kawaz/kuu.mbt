//! Cargo CLI argument parsing demo using kuu WASM bridge.
//!
//! CV: 青山龍星
//!
//! Demonstrates kuu's multi-language capabilities by parsing cargo-like
//! CLI arguments from Rust via the WASM bridge.

mod bridge;
mod schema;

use schema::*;

fn build_cargo_schema() -> Schema {
    // --- Global options ---
    let global_opts: Vec<serde_json::Value> = vec![
        count("verbose")
            .shorts("v")
            .global()
            .description("Use verbose output (-vv very verbose)")
            .build(),
        flag("quiet")
            .shorts("q")
            .global()
            .description("Do not print cargo log messages")
            .build(),
        string_opt("color")
            .global()
            .description("Coloring: auto, always, never")
            .default_str("auto")
            .choices(&["auto", "always", "never"])
            .implicit_value_str("always")
            .build(),
        append_string("config")
            .global()
            .description("Override a configuration value")
            .build(),
        string_opt("manifest-path")
            .global()
            .description("Path to Cargo.toml")
            .build(),
        flag("locked")
            .global()
            .description("Assert that Cargo.lock will remain unchanged")
            .build(),
        flag("offline")
            .global()
            .description("Run without accessing the network")
            .build(),
        flag("frozen")
            .global()
            .description("Equivalent to specifying both --locked and --offline")
            .build(),
        // Top-level only options
        flag("list")
            .description("List installed commands")
            .build(),
        string_opt("explain")
            .description("Provide a detailed explanation of a rustc error message")
            .build(),
        // Unstable / hidden
        string_opt("unstable-flags")
            .shorts("Z")
            .hidden()
            .description("Unstable (nightly-only) flags to Cargo")
            .build(),
    ];

    // --- Subcommands ---

    // build / b
    let build_cmd = command("build")
        .description("Compile a local package and all of its dependencies")
        .aliases(&["b"])
        .opt(string_opt("message-format")
            .description("Error format")
            .default_str("human")
            .choices(&["human", "short", "json", "json-diagnostic-short", "json-diagnostic-rendered-ansi"]))
        .opt(flag("future-incompat-report")
            .description("Outputs a future incompatibility report at the end of the build"))
        // deprecated: --all → --workspace
        .opt(flag("all")
            .description("Alias for --workspace (deprecated)")
            .hidden())
        .opts(compilation_opts())
        .opts(feature_opts())
        .opts(package_opts())
        .opts(target_selection_opts())
        .build();

    // run / r
    let run_cmd = command("run")
        .description("Run a binary or example of the local package")
        .aliases(&["r"])
        .opt(string_opt("bin")
            .description("Name of the bin target to run"))
        .opt(string_opt("example")
            .description("Name of the example target to run"))
        .opt(string_opt("package")
            .shorts("p")
            .description("Package with the target to run"))
        .opts(compilation_opts())
        .opts(feature_opts())
        .dashdash()
        .build();

    // test / t
    let test_cmd = command("test")
        .description("Execute all unit and integration tests and build examples of a local package")
        .aliases(&["t"])
        .opt(positional("TESTNAME")
            .description("If specified, only run tests containing this string in their names"))
        .opt(flag("no-run")
            .description("Compile, but don't run tests"))
        .opt(flag("no-fail-fast")
            .description("Run all tests regardless of failure"))
        .opt(flag("doc")
            .description("Test only this library's documentation"))
        .opts(compilation_opts())
        .opts(feature_opts())
        .opts(package_opts())
        .opts(target_selection_opts())
        .dashdash()
        .build();

    // check / c
    let check_cmd = command("check")
        .description("Check a local package and all of its dependencies for errors")
        .aliases(&["c"])
        .opt(string_opt("message-format")
            .description("Error format")
            .default_str("human")
            .choices(&["human", "short", "json"]))
        .opts(compilation_opts())
        .opts(feature_opts())
        .opts(package_opts())
        .opts(target_selection_opts())
        .build();

    // new
    let new_cmd = command("new")
        .description("Create a new cargo package at <path>")
        .exclusive(&["bin", "lib"])
        .opt(positional("path")
            .description("Path to create the new package"))
        .opt(flag("bin")
            .description("Use a binary (application) template [default]"))
        .opt(flag("lib")
            .description("Use a library template"))
        .opt(string_opt("edition")
            .description("Edition to set for the crate generated")
            .choices(&["2015", "2018", "2021", "2024"]))
        .opt(string_opt("vcs")
            .description("Initialize a new repository for the given version control system")
            .choices(&["git", "hg", "pijul", "fossil", "none"]))
        .opt(string_opt("name")
            .description("Set the resulting package name, defaults to the directory name"))
        .opt(string_opt("registry")
            .description("Registry to use"))
        .required_opt("path")
        .build();

    // add
    let add_cmd = command("add")
        .description("Add dependencies to a Cargo.toml manifest file")
        .exclusive(&["path", "git", "registry"])
        .exclusive(&["dev", "build"])
        .opt(rest("DEP")
            .description("Reference to package to add as a dependency"))
        .opt(flag("no-default-features")
            .description("Disable the default features"))
        .opt(flag("default-features")
            .description("Re-enable the default features"))
        .opt(append_string("features")
            .shorts("F")
            .description("Space or comma separated list of features to activate"))
        .opt(flag("optional")
            .description("Mark the dependency as optional"))
        .opt(flag("no-optional")
            .description("Mark the dependency as required"))
        .opt(string_opt("rename")
            .description("Rename the dependency"))
        .opt(flag("dry-run")
            .shorts("n")
            .description("Don't actually write the manifest"))
        // Source options
        .opt(string_opt("path")
            .description("Filesystem path to local crate to add"))
        .opt(string_opt("git")
            .description("Git repository location"))
        .opt(string_opt("branch")
            .description("Git branch to download the crate from"))
        .opt(string_opt("tag")
            .description("Git tag to download the crate from"))
        .opt(string_opt("rev")
            .description("Git reference to download the crate from"))
        .opt(string_opt("registry")
            .description("Package registry for this dependency"))
        // Section options
        .opt(flag("dev")
            .description("Add as development dependency"))
        .opt(flag("build")
            .description("Add as build dependency"))
        .opt(string_opt("target")
            .description("Add as dependency to the given target platform"))
        .opt(string_opt("package")
            .shorts("p")
            .description("Package to modify"))
        .build();

    // remove / rm
    let remove_cmd = command("remove")
        .description("Remove dependencies from a Cargo.toml manifest file")
        .aliases(&["rm"])
        .opt(rest("DEP_ID")
            .description("Dependencies to be removed"))
        .opt(flag("dry-run")
            .shorts("n")
            .description("Don't actually write the manifest"))
        .opt(flag("dev")
            .description("Remove as development dependency"))
        .opt(flag("build")
            .description("Remove as build dependency"))
        .opt(string_opt("target")
            .description("Remove as dependency from the given target platform"))
        .opt(string_opt("package")
            .shorts("p")
            .description("Package to remove from"))
        .build();

    // clean
    let clean_cmd = command("clean")
        .description("Remove artifacts that cargo has generated in the past")
        .opt(flag("doc")
            .description("Whether or not to clean just the documentation directory"))
        .opt(flag("release")
            .shorts("r")
            .description("Whether or not to clean release artifacts"))
        .opt(flag("dry-run")
            .shorts("n")
            .description("Display what would be deleted without deleting anything"))
        .opt(string_opt("profile")
            .description("Clean artifacts of the specified profile"))
        .opt(string_opt("target")
            .description("Target triple to clean output for"))
        .opt(string_opt("target-dir")
            .description("Directory for all generated artifacts")
            .env("CARGO_TARGET_DIR")) // NOTE: WASM bridge does not yet support env; no-op placeholder for future bridge extension
        .opt(string_opt("package")
            .shorts("p")
            .description("Package to clean artifacts for"))
        .opt(flag("workspace")
            .description("Clean all packages in the workspace"))
        .build();

    // doc / d
    let doc_cmd = command("doc")
        .description("Build a package's documentation")
        .aliases(&["d"])
        .opt(flag("open")
            .description("Opens the docs in a browser after the operation"))
        .opt(flag("no-deps")
            .description("Do not build documentation for dependencies"))
        .opt(flag("document-private-items")
            .description("Document private items"))
        .opts(compilation_opts())
        .opts(feature_opts())
        .opts(package_opts())
        .build();

    let mut all_opts = global_opts;
    all_opts.extend([
        build_cmd, run_cmd, test_cmd, check_cmd,
        new_cmd, add_cmd, remove_cmd, clean_cmd, doc_cmd,
    ]);

    Schema {
        description: "Rust's package manager".into(),
        opts: all_opts,
        require_cmd: false,
        exclusive: vec![
            vec!["verbose".into(), "quiet".into()],
        ],
        required: Vec::new(),
    }
}

/// Returns true if the value is a non-trivial (non-default) parse result worth displaying.
fn is_meaningful(value: &serde_json::Value) -> bool {
    match value {
        serde_json::Value::Null => false,
        serde_json::Value::Bool(false) => false,
        serde_json::Value::Number(n) if n.as_f64() == Some(0.0) => false,
        serde_json::Value::String(s) if s.is_empty() => false,
        serde_json::Value::Array(a) if a.is_empty() => false,
        _ => true,
    }
}

fn display_values(values: &serde_json::Map<String, serde_json::Value>, prefix: &str) {
    for (key, value) in values {
        if is_meaningful(value) {
            println!("{prefix}{key}: {value}");
        }
    }
}

fn display_result(result: &bridge::ParseSuccess, indent: usize) {
    let prefix = " ".repeat(indent);
    display_values(&result.values, &prefix);
    if let Some(ref cmd) = result.command {
        display_command(cmd, indent);
    }
}

fn display_command(cmd: &bridge::CommandResult, indent: usize) {
    let prefix = " ".repeat(indent);
    println!("{prefix}[command: {}]", cmd.name);
    display_values(&cmd.values, &format!("{prefix}  "));
    if let Some(ref nested) = cmd.command {
        display_command(nested, indent + 2);
    }
}

fn run(args: Vec<String>) {
    let schema = build_cargo_schema();
    let input = schema.to_json(&args);

    match bridge::kuu_parse(&input) {
        Ok(bridge::ParseResult::Ok(success)) => {
            println!("Parse succeeded:");
            display_result(&success, 2);
        }
        Ok(bridge::ParseResult::Help(text)) => {
            println!("{text}");
        }
        Ok(bridge::ParseResult::Error { message, help }) => {
            eprintln!("Error: {message}");
            if let Some(h) = help {
                eprintln!("\n{h}");
            }
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("Bridge error: {e}");
            std::process::exit(2);
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        // Demo mode: run several example invocations
        println!("Demo mode: running example invocations...");
        let demos: Vec<Vec<&str>> = vec![
            vec!["build", "--release", "--features", "serde", "-j", "4"],
            vec!["run", "-r", "--bin", "myapp", "--", "--port", "8080"],
            vec!["test", "integration", "--no-fail-fast", "--", "--nocapture"],
            vec!["new", "my-project", "--lib", "--edition", "2024"],
            vec!["add", "serde", "tokio", "--features", "derive", "--dev"],
            vec!["remove", "old-dep", "--dev", "-n"],
            vec!["clean", "--release", "--doc"],
            vec!["check", "-j", "8", "--all-targets"],
            vec!["doc", "--open", "--no-deps"],
            vec!["-vv", "build", "--color=never", "--locked"],
            vec!["--help"],
        ];

        for demo_args in demos {
            let args_str: Vec<String> = demo_args.iter().map(|s| s.to_string()).collect();
            println!("\n{}", "=".repeat(60));
            println!("$ cargo {}", demo_args.join(" "));
            println!("{}", "=".repeat(60));
            run(args_str);
        }
    } else {
        run(args);
    }
}
