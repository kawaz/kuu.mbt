// mygit — A sample git-like CLI built with kuu-rs to demonstrate all API features.
//
// This is a design mock: it shows the intended API surface, not a compilable program.
// The `kuu` crate and its derive macros do not yet exist; this file serves as the
// specification for their implementation.

use kuu::{Args, KuuError, KuuValue, Subcommand};

// ─── Root CLI ───────────────────────────────────────────────────────────────

#[derive(Args)]
#[kuu(description = "mygit - A sample git-like CLI built with kuu", require_cmd)]
struct Mygit {
    /// Increase verbosity (-v, -vv, -vvv)
    #[kuu(count, short = 'v', global, variation_reset = "no")]
    verbose: i64,

    /// Suppress output
    #[kuu(short = 'q', global, exclusive_group = "verbosity")]
    quiet: bool,

    // verbose is also in the "verbosity" exclusive group
    #[kuu(skip)] // marker: verbose and quiet are exclusive (see below)

    /// When to use colors
    #[kuu(
        default = "auto",
        global,
        choices = ["always", "never", "auto"],
        implicit_value = "always"
    )]
    color: String,

    /// Internal debug flag (hidden from help)
    #[kuu(name = "debug-internal", hidden, global)]
    debug_internal: bool,

    #[kuu(subcommand)]
    command: Command,
}

// exclusive_group は同一グループ名を持つフィールド同士が排他になる。
// count フィールド (verbose) にも exclusive_group を付けたい場合:
//
//   #[kuu(count, short = 'v', global, exclusive_group = "verbosity", variation_reset = "no")]
//   verbose: i64,
//
// ただし count は i64 で flag ではないため、上の例では quiet 側にだけ付けている。
// core 側では p.exclusive([verbose.as_ref(), quiet.as_ref()]) に対応。

// ─── Subcommand Enum ────────────────────────────────────────────────────────

#[derive(Subcommand)]
enum Command {
    /// Clone a repository
    Clone(CloneArgs),

    /// Record changes
    Commit(CommitArgs),

    /// Show commit logs
    Log(LogArgs),

    /// Manage tracked repositories
    Remote(RemoteArgs),

    /// Update remote refs
    Push(PushArgs),
}

// ─── clone ──────────────────────────────────────────────────────────────────

#[derive(Args)]
#[kuu(description = "mygit clone - Clone a repository")]
struct CloneArgs {
    /// Repository URL (required positional)
    #[kuu(positional)]
    url: String,

    /// Target directory (optional positional)
    #[kuu(positional)]
    directory: Option<String>,

    /// Shallow clone with N commits
    #[kuu(value_name = "N")]
    depth: Option<i64>,

    /// Checkout this branch
    #[kuu(short = 'b', value_name = "BRANCH")]
    branch: Option<String>,

    /// Create a bare repository
    bare: bool,
}

// ─── commit ─────────────────────────────────────────────────────────────────

#[derive(Args)]
#[kuu(description = "mygit commit - Record changes")]
struct CommitArgs {
    /// Commit message (required, trimmed, must be non-empty)
    #[kuu(short = 'm', value_name = "MSG", filter = "trim | non_empty")]
    message: String,

    /// Stage all modified files
    #[kuu(short = 'a')]
    all: bool,

    /// Amend the previous commit
    amend: bool,

    /// Run pre-commit hooks (--no-verify to skip)
    #[kuu(default = true, variation_false = "no")]
    verify: bool,
}

// ─── log ────────────────────────────────────────────────────────────────────

#[derive(Args)]
#[kuu(description = "mygit log - Show commit logs")]
struct LogArgs {
    /// One line per commit
    oneline: bool,

    /// Limit number of commits
    #[kuu(short = 'n', value_name = "N", name = "max-count")]
    max_count: Option<i64>,

    /// Filter by author (repeatable: --author A --author B)
    #[kuu(value_name = "PATTERN")]
    author: Vec<String>,

    /// Pretty-print format
    #[kuu(choices = ["oneline", "short", "medium", "full", "fuller", "reference", "raw"])]
    format: Option<LogFormat>,

    /// Limit to paths
    #[kuu(rest)]
    paths: Vec<String>,
}

/// Log output format (auto-generates choices)
#[derive(KuuValue)]
enum LogFormat {
    Oneline,
    Short,
    Medium,
    Full,
    Fuller,
    Reference,
    Raw,
}

// ─── remote (nested subcommands) ────────────────────────────────────────────

#[derive(Args)]
#[kuu(description = "mygit remote - Manage remotes", require_cmd)]
struct RemoteArgs {
    #[kuu(subcommand)]
    command: RemoteCommand,
}

#[derive(Subcommand)]
enum RemoteCommand {
    /// Add a remote
    Add(RemoteAddArgs),

    /// Remove a remote
    Remove(RemoteRemoveArgs),
}

#[derive(Args)]
#[kuu(description = "mygit remote add - Add a new remote", serial)]
struct RemoteAddArgs {
    /// Remote name
    #[kuu(positional)]
    name: String,

    /// Remote URL
    #[kuu(positional)]
    url: String,
}
// serial + never(): #[kuu(serial)] on struct auto-wraps all positionals
// in serial() and appends never() to reject extra arguments.

#[derive(Args)]
#[kuu(description = "mygit remote remove - Remove a remote")]
struct RemoteRemoveArgs {
    /// Remote name
    #[kuu(positional)]
    name: String,
}

// ─── push ───────────────────────────────────────────────────────────────────

#[derive(Args)]
#[kuu(description = "mygit push - Push to remote")]
struct PushArgs {
    /// Force push
    #[kuu(short = 'f', exclusive_group = "force_mode")]
    force: bool,

    /// Safer force push
    #[kuu(name = "force-with-lease", exclusive_group = "force_mode")]
    force_with_lease: bool,

    /// Set upstream for the branch
    #[kuu(short = 'u', name = "set-upstream")]
    set_upstream: bool,
}

// ─── main ───────────────────────────────────────────────────────────────────

fn main() -> Result<(), KuuError> {
    let cli = Mygit::parse()?;

    // Global options are always available
    println!("verbose: {}", cli.verbose);
    println!("quiet: {}", cli.quiet);
    println!("color: {}", cli.color);

    // Type-safe subcommand dispatch — no string matching, no unwrap()
    match cli.command {
        Command::Clone(c) => {
            println!("clone url: {}", c.url); // String, not Option — guaranteed present
            if let Some(dir) = &c.directory {
                println!("clone dir: {}", dir);
            }
            if let Some(depth) = c.depth {
                println!("clone depth: {}", depth);
            }
            if let Some(branch) = &c.branch {
                println!("clone branch: {}", branch);
            }
            println!("clone bare: {}", c.bare);
        }

        Command::Commit(c) => {
            println!("commit message: {}", c.message); // String — filter ensures non-empty
            println!("commit all: {}", c.all);
            println!("commit amend: {}", c.amend);
            println!("commit verify: {}", c.verify); // default=true, --no-verify flips
        }

        Command::Log(l) => {
            println!("log oneline: {}", l.oneline);
            if let Some(n) = l.max_count {
                println!("log max-count: {}", n);
            }
            if !l.author.is_empty() {
                println!("log authors: {:?}", l.author);
            }
            if let Some(fmt) = &l.format {
                println!("log format: {}", fmt);
            }
            if !l.paths.is_empty() {
                println!("log paths: {:?}", l.paths);
            }
        }

        Command::Remote(r) => match r.command {
            RemoteCommand::Add(a) => {
                // serial positionals: name and url are both required
                println!("remote add: {} {}", a.name, a.url);
            }
            RemoteCommand::Remove(r) => {
                println!("remote remove: {}", r.name);
            }
        },

        Command::Push(p) => {
            println!("push force: {}", p.force);
            println!("push force-with-lease: {}", p.force_with_lease);
            println!("push set-upstream: {}", p.set_upstream);
        }
    }

    Ok(())
}
