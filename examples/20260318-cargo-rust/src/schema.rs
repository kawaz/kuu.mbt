//! Type-safe schema builder for kuu WASM bridge.
//!
//! Provides helper functions that generate the JSON schema
//! expected by kuu's WASM bridge.

use serde_json::{json, Value};

/// Top-level schema for kuu parsing.
pub struct Schema {
    pub description: String,
    pub opts: Vec<Value>,
    pub require_cmd: bool,
    pub exclusive: Vec<Vec<String>>,
    pub required: Vec<String>,
}

impl Schema {
    /// Convert the schema + args into the JSON input for kuu_parse.
    pub fn to_json(&self, args: &[String]) -> Value {
        let mut obj = json!({
            "version": 1,
            "description": self.description,
            "opts": self.opts,
            "args": args,
        });
        if self.require_cmd {
            obj["require_cmd"] = json!(true);
        }
        if !self.exclusive.is_empty() {
            obj["exclusive"] = json!(self.exclusive);
        }
        if !self.required.is_empty() {
            obj["required"] = json!(self.required);
        }
        obj
    }
}

// --- Opt definition helpers ---
// Each function returns a serde_json::Value representing one opt definition.
// Optional parameters use the builder pattern via OptDef wrapper.

/// A mutable opt definition that supports chaining.
pub struct OptDef(pub Value);

impl OptDef {
    pub fn shorts(mut self, s: &str) -> Self {
        self.0["shorts"] = json!(s);
        self
    }

    pub fn description(mut self, d: &str) -> Self {
        self.0["description"] = json!(d);
        self
    }

    pub fn global(mut self) -> Self {
        self.0["global"] = json!(true);
        self
    }

    pub fn hidden(mut self) -> Self {
        self.0["hidden"] = json!(true);
        self
    }

    pub fn aliases(mut self, a: &[&str]) -> Self {
        self.0["aliases"] = json!(a);
        self
    }

    #[allow(dead_code)]
    pub fn default_bool(mut self, v: bool) -> Self {
        self.0["default"] = json!(v);
        self
    }

    pub fn default_str(mut self, v: &str) -> Self {
        self.0["default"] = json!(v);
        self
    }

    #[allow(dead_code)]
    pub fn default_int(mut self, v: i64) -> Self {
        self.0["default"] = json!(v);
        self
    }

    pub fn choices(mut self, c: &[&str]) -> Self {
        self.0["choices"] = json!(c);
        self
    }

    pub fn implicit_value_str(mut self, v: &str) -> Self {
        self.0["implicit_value"] = json!(v);
        self
    }

    pub fn env(mut self, name: &str) -> Self {
        self.0["env"] = json!(name);
        self
    }

    #[allow(dead_code)]
    pub fn variation_false(mut self, prefix: &str) -> Self {
        self.0["variation_false"] = json!(prefix);
        self
    }

    #[allow(dead_code)]
    pub fn variation_toggle(mut self, prefix: &str) -> Self {
        self.0["variation_toggle"] = json!(prefix);
        self
    }

    /// Finalize into a JSON Value.
    pub fn build(self) -> Value {
        self.0
    }
}

// --- Constructors ---

pub fn flag(name: &str) -> OptDef {
    OptDef(json!({"kind": "flag", "name": name}))
}

pub fn count(name: &str) -> OptDef {
    OptDef(json!({"kind": "count", "name": name}))
}

pub fn string_opt(name: &str) -> OptDef {
    OptDef(json!({"kind": "string", "name": name}))
}

pub fn int_opt(name: &str) -> OptDef {
    OptDef(json!({"kind": "int", "name": name}))
}

pub fn append_string(name: &str) -> OptDef {
    OptDef(json!({"kind": "append_string", "name": name}))
}

pub fn positional(name: &str) -> OptDef {
    OptDef(json!({"kind": "positional", "name": name}))
}

pub fn rest(name: &str) -> OptDef {
    OptDef(json!({"kind": "rest", "name": name}))
}

pub fn dashdash() -> Value {
    json!({"kind": "dashdash"})
}

/// Build a command definition.
pub fn command(name: &str) -> CommandDef {
    CommandDef {
        name: name.into(),
        description: String::new(),
        aliases: Vec::new(),
        opts: Vec::new(),
        require_cmd: false,
        exclusive: Vec::new(),
        required: Vec::new(),
    }
}

pub struct CommandDef {
    name: String,
    description: String,
    aliases: Vec<String>,
    opts: Vec<Value>,
    require_cmd: bool,
    exclusive: Vec<Vec<String>>,
    required: Vec<String>,
}

impl CommandDef {
    pub fn description(mut self, d: &str) -> Self {
        self.description = d.into();
        self
    }

    pub fn aliases(mut self, a: &[&str]) -> Self {
        self.aliases = a.iter().map(|s| s.to_string()).collect();
        self
    }

    #[allow(dead_code)]
    pub fn require_cmd(mut self) -> Self {
        self.require_cmd = true;
        self
    }

    pub fn exclusive(mut self, names: &[&str]) -> Self {
        self.exclusive
            .push(names.iter().map(|s| s.to_string()).collect());
        self
    }

    pub fn required_opt(mut self, name: &str) -> Self {
        self.required.push(name.into());
        self
    }

    pub fn opt(mut self, def: OptDef) -> Self {
        self.opts.push(def.build());
        self
    }

    pub fn opts(mut self, defs: Vec<Value>) -> Self {
        self.opts.extend(defs);
        self
    }

    pub fn dashdash(mut self) -> Self {
        self.opts.push(dashdash());
        self
    }

    pub fn build(self) -> Value {
        let mut cmd = json!({
            "kind": "command",
            "name": self.name,
            "opts": self.opts,
        });
        if !self.description.is_empty() {
            cmd["description"] = json!(self.description);
        }
        if !self.aliases.is_empty() {
            cmd["aliases"] = json!(self.aliases);
        }
        if self.require_cmd {
            cmd["require_cmd"] = json!(true);
        }
        if !self.exclusive.is_empty() {
            cmd["exclusive"] = json!(self.exclusive);
        }
        if !self.required.is_empty() {
            cmd["required"] = json!(self.required);
        }
        cmd
    }
}

// --- Shared option groups (cargo-specific helpers) ---

/// Common compilation options shared by build/check/test/bench/run/doc.
pub fn compilation_opts() -> Vec<Value> {
    vec![
        flag("release")
            .shorts("r")
            .description("Build artifacts in release mode, with optimizations")
            .build(),
        string_opt("profile")
            .description("Build artifacts with the specified profile")
            .build(),
        int_opt("jobs")
            .shorts("j")
            .description("Number of parallel jobs, defaults to # of CPUs")
            .env("CARGO_BUILD_JOBS")
            .build(),
        flag("keep-going")
            .description("Do not abort the build as soon as there is an error")
            .build(),
        string_opt("target")
            .description("Build for the target triple")
            .env("CARGO_BUILD_TARGET")
            .build(),
        string_opt("target-dir")
            .description("Directory for all generated artifacts")
            .env("CARGO_TARGET_DIR")
            .build(),
    ]
}

/// Feature selection options.
pub fn feature_opts() -> Vec<Value> {
    vec![
        append_string("features")
            .shorts("F")
            .description("Space or comma separated list of features to activate")
            .build(),
        flag("all-features")
            .description("Activate all available features")
            .build(),
        flag("no-default-features")
            .description("Do not activate the `default` feature")
            .build(),
    ]
}

/// Package selection options.
pub fn package_opts() -> Vec<Value> {
    vec![
        string_opt("package")
            .shorts("p")
            .description("Package to build")
            .build(),
        flag("workspace")
            .description("Build all packages in the workspace")
            .build(),
        string_opt("exclude")
            .description("Exclude packages from the build")
            .build(),
    ]
}

/// Target selection options.
pub fn target_selection_opts() -> Vec<Value> {
    vec![
        flag("lib").description("Build only this package's library").build(),
        flag("bins").description("Build all binaries").build(),
        string_opt("bin").description("Build only the specified binary").build(),
        flag("examples").description("Build all examples").build(),
        string_opt("example").description("Build only the specified example").build(),
        flag("tests").description("Build all test targets").build(),
        string_opt("test").description("Build only the specified test target").build(),
        flag("benches").description("Build all bench targets").build(),
        string_opt("bench").description("Build only the specified bench target").build(),
        flag("all-targets").description("Build all targets").build(),
    ]
}
