//! embed-poc: kuu-cli embed+extract+exec pattern demonstration (Rust).

mod kuu;

use kuu::{OptDef, Schema};

fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();

    let schema = Schema {
        version: 1,
        description: Some("embed-poc - kuu-cli embed pattern demo (Rust)".to_string()),
        opts: vec![
            OptDef {
                kind: "count".to_string(),
                name: "verbose".to_string(),
                shorts: Some("v".to_string()),
                global: Some(true),
                description: Some("Increase verbosity".to_string()),
                ..Default::default()
            },
            OptDef {
                kind: "string".to_string(),
                name: "host".to_string(),
                default: Some(serde_json::Value::String("localhost".to_string())),
                description: Some("Server host".to_string()),
                ..Default::default()
            },
            OptDef {
                kind: "command".to_string(),
                name: "serve".to_string(),
                description: Some("Start server".to_string()),
                opts: Some(vec![
                    OptDef {
                        kind: "int".to_string(),
                        name: "port".to_string(),
                        default: Some(serde_json::json!(8080)),
                        description: Some("Port number".to_string()),
                        ..Default::default()
                    },
                    OptDef {
                        kind: "flag".to_string(),
                        name: "tls".to_string(),
                        description: Some("Enable TLS".to_string()),
                        ..Default::default()
                    },
                ]),
                ..Default::default()
            },
            OptDef {
                kind: "command".to_string(),
                name: "clone".to_string(),
                description: Some("Clone a repository".to_string()),
                opts: Some(vec![
                    OptDef {
                        kind: "int".to_string(),
                        name: "depth".to_string(),
                        default: Some(serde_json::json!(0)),
                        description: Some("Shallow clone depth".to_string()),
                        ..Default::default()
                    },
                    OptDef {
                        kind: "positional".to_string(),
                        name: "url".to_string(),
                        description: Some("Repository URL".to_string()),
                        ..Default::default()
                    },
                ]),
                ..Default::default()
            },
        ],
        args,
        require_cmd: None,
        exclusive: None,
        required: None,
    };

    let result = kuu::kuu_parse(&schema)?;

    if result.help_requested.unwrap_or(false) {
        if let Some(help) = &result.help {
            println!("{help}");
        }
        return Ok(());
    }

    if !result.ok {
        if let Some(err) = &result.error {
            eprintln!("error: {err}");
        }
        if let Some(help) = &result.help {
            eprintln!("{help}");
        }
        std::process::exit(1);
    }

    println!("{}", serde_json::to_string_pretty(&result).unwrap());
    Ok(())
}
