"""cargo CLI の引数スキーマ定義

kuu WASM bridge の JSON スキーマ形式で cargo の主要サブコマンドとオプションを定義する。
cargo --help の出力を参考に、引数パースの検証に十分な範囲で定義。
"""

DESCRIPTION = "mycargo - A sample cargo-like CLI built with kuu"

# --- 共通オプションパターン ---
# cargo の多くのビルド系サブコマンドで共通するオプション群


def _feature_opts() -> list[dict]:
    """features/all-features/no-default-features の共通オプション"""
    return [
        {"kind": "string", "name": "features", "description": "Space or comma separated list of features to activate"},
        {"kind": "flag", "name": "all-features", "description": "Activate all available features"},
        {"kind": "flag", "name": "no-default-features", "description": "Do not activate the default feature"},
    ]


def _build_common_opts() -> list[dict]:
    """build/test/check/bench 等で共通のオプション"""
    return [
        {"kind": "flag", "name": "release", "shorts": "r", "description": "Build in release mode with optimizations"},
        {"kind": "string", "name": "target", "description": "Build for the target triple"},
        *_feature_opts(),
        {"kind": "int", "name": "jobs", "shorts": "j", "description": "Number of parallel jobs"},
        {"kind": "string", "name": "package", "shorts": "p", "description": "Package to build"},
        {"kind": "flag", "name": "workspace", "description": "Build all packages in the workspace"},
    ]


def _target_opts() -> list[dict]:
    """ビルドターゲット選択オプション"""
    return [
        {"kind": "flag", "name": "lib", "description": "Build only this package's library"},
        {"kind": "string", "name": "bin", "description": "Build only the specified binary"},
        {"kind": "string", "name": "example", "description": "Build only the specified example"},
        {"kind": "string", "name": "test", "description": "Build only the specified test target"},
        {"kind": "string", "name": "bench", "description": "Build only the specified bench target"},
        {"kind": "flag", "name": "all-targets", "description": "Build all targets"},
    ]


# --- サブコマンド定義 ---

OPTS: list[dict] = [
    # グローバルオプション
    {"kind": "count", "name": "verbose", "shorts": "v", "global": True, "description": "Use verbose output (-vv for very verbose)"},
    {"kind": "flag", "name": "quiet", "shorts": "q", "global": True, "description": "Do not print cargo log messages"},
    {"kind": "string", "name": "color", "global": True, "description": "Coloring: auto, always, never", "choices": ["auto", "always", "never"], "default": "auto"},
    {"kind": "string", "name": "manifest-path", "global": True, "description": "Path to Cargo.toml"},
    {"kind": "flag", "name": "frozen", "global": True, "description": "Require Cargo.lock and cache are up to date"},
    {"kind": "flag", "name": "locked", "global": True, "description": "Require Cargo.lock is up to date"},
    {"kind": "flag", "name": "offline", "global": True, "description": "Run without accessing the network"},

    # === build ===
    {
        "kind": "command",
        "name": "build",
        "aliases": ["b"],
        "description": "Compile a local package and all of its dependencies",
        "opts": [
            *_build_common_opts(),
            *_target_opts(),
            {"kind": "string", "name": "profile", "description": "Build with the given profile"},
        ],
    },

    # === test ===
    {
        "kind": "command",
        "name": "test",
        "aliases": ["t"],
        "description": "Execute all unit and integration tests and build examples",
        "opts": [
            {"kind": "positional", "name": "testname", "description": "Test name filter"},
            *_build_common_opts(),
            {"kind": "flag", "name": "lib", "description": "Test only this package's library"},
            {"kind": "string", "name": "bin", "description": "Test only the specified binary"},
            {"kind": "flag", "name": "doc", "description": "Test only this library's documentation"},
            {"kind": "flag", "name": "no-run", "description": "Compile, but don't run tests"},
            {"kind": "flag", "name": "no-fail-fast", "description": "Run all tests regardless of failure"},
            {"kind": "rest", "name": "test-args", "description": "Arguments for the test binary"},
        ],
    },

    # === run ===
    {
        "kind": "command",
        "name": "run",
        "aliases": ["r"],
        "description": "Run a binary or example of the local package",
        "opts": [
            *_build_common_opts(),
            {"kind": "string", "name": "bin", "description": "Name of the bin target to run"},
            {"kind": "string", "name": "example", "description": "Name of the example target to run"},
            {"kind": "rest", "name": "args", "description": "Arguments for the binary"},
        ],
    },

    # === bench ===
    {
        "kind": "command",
        "name": "bench",
        "description": "Execute all benchmarks of a local package",
        "opts": [
            {"kind": "positional", "name": "benchname", "description": "Benchmark name filter"},
            *_build_common_opts(),
            {"kind": "string", "name": "bench", "description": "Benchmark only the specified target"},
            {"kind": "rest", "name": "bench-args", "description": "Arguments for the benchmark binary"},
        ],
    },

    # === check ===
    {
        "kind": "command",
        "name": "check",
        "aliases": ["c"],
        "description": "Check a local package and all of its dependencies for errors",
        "opts": [
            *_build_common_opts(),
            *_target_opts(),
            {"kind": "string", "name": "profile", "description": "Check with the given profile"},
        ],
    },

    # === clippy ===
    {
        "kind": "command",
        "name": "clippy",
        "description": "Check a package to catch common mistakes and improve code",
        "opts": [
            *_build_common_opts(),
            {"kind": "flag", "name": "fix", "description": "Automatically apply lint suggestions"},
            {"kind": "flag", "name": "allow-dirty", "description": "Fix even if the working directory has changes"},
            {"kind": "flag", "name": "allow-staged", "description": "Fix even if there are staged changes"},
            {"kind": "rest", "name": "clippy-args", "description": "Arguments for clippy"},
        ],
    },

    # === fmt ===
    {
        "kind": "command",
        "name": "fmt",
        "description": "Format all bin and lib files of the current crate",
        "opts": [
            {"kind": "flag", "name": "check", "description": "Run in check mode (exit with 1 if not formatted)"},
            {"kind": "flag", "name": "all", "description": "Format all packages in the workspace"},
            {"kind": "string", "name": "package", "shorts": "p", "description": "Package to format"},
            {"kind": "rest", "name": "fmt-args", "description": "Arguments for rustfmt"},
        ],
    },

    # === doc ===
    {
        "kind": "command",
        "name": "doc",
        "aliases": ["d"],
        "description": "Build a package's documentation",
        "opts": [
            *_build_common_opts(),
            {"kind": "flag", "name": "open", "description": "Open the docs in a browser after building"},
            {"kind": "flag", "name": "no-deps", "description": "Don't build documentation for dependencies"},
            {"kind": "flag", "name": "document-private-items", "description": "Document private items"},
        ],
    },

    # === new ===
    {
        "kind": "command",
        "name": "new",
        "description": "Create a new cargo package at <path>",
        "opts": [
            {"kind": "positional", "name": "path", "description": "Directory path for the new package"},
            {"kind": "flag", "name": "lib", "description": "Use a library template"},
            {"kind": "string", "name": "name", "description": "Set the package name (defaults to directory name)"},
            {"kind": "string", "name": "edition", "description": "Edition to set for the crate", "choices": ["2015", "2018", "2021", "2024"]},
            {"kind": "string", "name": "vcs", "description": "Initialize a VCS repository", "choices": ["git", "hg", "pijul", "fossil", "none"]},
        ],
    },

    # === init ===
    {
        "kind": "command",
        "name": "init",
        "description": "Create a new cargo package in an existing directory",
        "opts": [
            {"kind": "positional", "name": "path", "description": "Directory path (defaults to current directory)"},
            {"kind": "flag", "name": "lib", "description": "Use a library template"},
            {"kind": "string", "name": "name", "description": "Set the package name"},
            {"kind": "string", "name": "edition", "description": "Edition to set for the crate", "choices": ["2015", "2018", "2021", "2024"]},
        ],
    },

    # === publish ===
    {
        "kind": "command",
        "name": "publish",
        "description": "Upload a package to the registry",
        "opts": [
            {"kind": "flag", "name": "dry-run", "description": "Perform all checks without uploading"},
            {"kind": "flag", "name": "allow-dirty", "description": "Allow publishing with uncommitted changes"},
            {"kind": "string", "name": "token", "description": "API token to use"},
            {"kind": "string", "name": "registry", "description": "Registry to publish to"},
            {"kind": "string", "name": "package", "shorts": "p", "description": "Package to publish"},
        ],
    },

    # === install ===
    {
        "kind": "command",
        "name": "install",
        "description": "Install a Rust binary",
        "opts": [
            {"kind": "positional", "name": "crate", "description": "Crate to install"},
            {"kind": "string", "name": "version", "description": "Specify a version to install"},
            {"kind": "string", "name": "git", "description": "Git URL to install from"},
            {"kind": "string", "name": "branch", "description": "Branch to use when installing from git"},
            {"kind": "string", "name": "path", "description": "Filesystem path to local crate to install"},
            {"kind": "flag", "name": "force", "shorts": "f", "description": "Force overwriting existing crates"},
            {"kind": "string", "name": "root", "description": "Directory to install packages into"},
            {"kind": "int", "name": "jobs", "shorts": "j", "description": "Number of parallel jobs"},
            *_feature_opts(),
        ],
    },

    # === clean ===
    {
        "kind": "command",
        "name": "clean",
        "description": "Remove artifacts that cargo has generated in the past",
        "opts": [
            {"kind": "flag", "name": "release", "description": "Remove only release artifacts"},
            {"kind": "string", "name": "target", "description": "Target triple to clean"},
            {"kind": "string", "name": "target-dir", "description": "Directory for all generated artifacts"},
            {"kind": "string", "name": "package", "shorts": "p", "description": "Package to clean"},
        ],
    },

    # === update ===
    {
        "kind": "command",
        "name": "update",
        "description": "Update dependencies as recorded in the local lock file",
        "opts": [
            {"kind": "positional", "name": "spec", "description": "Package spec to update"},
            {"kind": "flag", "name": "recursive", "description": "Force updating all dependencies of the specified package"},
            {"kind": "string", "name": "precise", "description": "Update a single dependency to exactly PRECISE"},
            {"kind": "flag", "name": "dry-run", "description": "Don't actually write the lockfile"},
        ],
    },
]
