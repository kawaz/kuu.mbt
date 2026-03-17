import Foundation

/// Homebrew `brew` CLI schema definition for kuu WASM bridge.
enum BrewSchema {

    // MARK: - Public

    static func build() -> [String: Any] {
        [
            "version": 1,
            "description": "Homebrew — The Missing Package Manager for macOS (or Linux)",
            "require_cmd": true,
            "opts": globalOpts() + subcommands(),
        ]
    }

    // MARK: - Global Options

    static func globalOpts() -> [[String: Any]] {
        [
            flag("verbose", shorts: "v", global: true,
                 description: "Print additional output"),
            flag("debug", shorts: "d", global: true,
                 description: "Display debug information"),
            flag("quiet", shorts: "q", global: true,
                 description: "Suppress output"),
        ]
    }

    // MARK: - Subcommands

    static func subcommands() -> [[String: Any]] {
        [
            installCommand(),
            searchCommand(),
            tapCommand(),
            upgradeCommand(),
            listCommand(),
        ]
    }

    // MARK: - install

    static func installCommand() -> [String: Any] {
        command("install",
                description: "Install a formula or cask",
                opts: [
                    flag("force", shorts: "f",
                         description: "Force install, skipping checks"),
                    flag("build-from-source", shorts: "s",
                         description: "Compile from source"),
                    flag("dry-run", shorts: "n",
                         description: "Show what would be installed"),
                    flag("formula", aliases: ["formulae"],
                         description: "Treat all arguments as formulae"),
                    flag("cask", aliases: ["casks"],
                         description: "Treat all arguments as casks"),
                    flag("HEAD",
                         description: "Install the HEAD version"),
                    flag("keep-tmp",
                         description: "Retain temporary files"),
                    flag("ask",
                         description: "Ask before downloading"),
                    stringOpt("cc",
                              description: "Compiler to use (e.g. gcc-9, clang)"),
                    rest("packages"),
                ],
                exclusive: [["formula", "cask"]])
    }

    // MARK: - search

    static func searchCommand() -> [String: Any] {
        command("search",
                description: "Search for formulae and casks",
                opts: [
                    flag("formula", aliases: ["formulae"],
                         description: "Search only formulae"),
                    flag("cask", aliases: ["casks"],
                         description: "Search only casks"),
                    flag("desc",
                         description: "Search descriptions"),
                    positional("query"),
                ],
                exclusive: [["formula", "cask"]])
    }

    // MARK: - tap

    static func tapCommand() -> [String: Any] {
        command("tap",
                description: "Add a tap (third-party repository)",
                opts: [
                    flag("force",
                         description: "Force auto-update"),
                    flag("repair",
                         description: "Repair symlinks"),
                    flag("eval-all",
                         description: "Evaluate all formulae in the new tap"),
                    flag("custom-remote",
                         description: "Install with a custom remote"),
                    positional("repository"),
                    positional("url"),
                ])
    }

    // MARK: - upgrade

    static func upgradeCommand() -> [String: Any] {
        command("upgrade",
                description: "Upgrade outdated formulae and casks",
                opts: [
                    flag("force", shorts: "f",
                         description: "Force upgrade"),
                    flag("dry-run", shorts: "n",
                         description: "Show what would be upgraded"),
                    flag("formula", aliases: ["formulae"],
                         description: "Upgrade only formulae"),
                    flag("cask", aliases: ["casks"],
                         description: "Upgrade only casks"),
                    flag("greedy", shorts: "g",
                         description: "Include auto_updates casks"),
                    flag("greedy-latest",
                         description: "Include latest-version casks"),
                    flag("greedy-auto-updates",
                         description: "Include auto_updates-only casks"),
                    flag("ask",
                         description: "Ask before upgrading"),
                    flag("display-times",
                         description: "Show install times"),
                    rest("packages"),
                ],
                exclusive: [["formula", "cask"]])
    }

    // MARK: - list

    static func listCommand() -> [String: Any] {
        command("list",
                description: "List installed formulae and casks",
                aliases: ["ls"],
                opts: [
                    flag("formula", aliases: ["formulae"],
                         description: "List only formulae"),
                    flag("cask", aliases: ["casks"],
                         description: "List only casks"),
                    flag("full-name",
                         description: "Show fully-qualified names"),
                    flag("versions",
                         description: "Show version numbers"),
                    flag("pinned",
                         description: "List pinned formulae only"),
                    flag("installed-on-request",
                         description: "List manually installed"),
                    flag("installed-as-dependency",
                         description: "List dependency-installed"),
                    flag("one-per-line", shorts: "1",
                         description: "One entry per line"),
                    flag("long-format", shorts: "l",
                         description: "Long listing format"),
                    flag("reverse", shorts: "r",
                         description: "Reverse sort order"),
                    flag("time-sort", shorts: "t",
                         description: "Sort by modification time"),
                    rest("packages"),
                ],
                exclusive: [["formula", "cask"]])
    }

    // MARK: - Schema Helpers

    private static func flag(
        _ name: String,
        shorts: String? = nil,
        global: Bool = false,
        aliases: [String]? = nil,
        description: String? = nil
    ) -> [String: Any] {
        var opt: [String: Any] = ["kind": "flag", "name": name]
        if let s = shorts { opt["shorts"] = s }
        if global { opt["global"] = true }
        if let a = aliases { opt["aliases"] = a }
        if let d = description { opt["description"] = d }
        return opt
    }

    private static func stringOpt(
        _ name: String,
        default defaultValue: String? = nil,
        choices: [String]? = nil,
        description: String? = nil
    ) -> [String: Any] {
        var opt: [String: Any] = ["kind": "string", "name": name]
        if let d = defaultValue { opt["default"] = d }
        if let c = choices { opt["choices"] = c }
        if let d = description { opt["description"] = d }
        return opt
    }

    private static func positional(_ name: String) -> [String: Any] {
        ["kind": "positional", "name": name]
    }

    private static func rest(_ name: String) -> [String: Any] {
        ["kind": "rest", "name": name]
    }

    private static func command(
        _ name: String,
        description: String? = nil,
        aliases: [String]? = nil,
        opts: [[String: Any]] = [],
        exclusive: [[String]]? = nil
    ) -> [String: Any] {
        var cmd: [String: Any] = ["kind": "command", "name": name, "opts": opts]
        if let d = description { cmd["description"] = d }
        if let a = aliases { cmd["aliases"] = a }
        if let e = exclusive { cmd["exclusive"] = e }
        return cmd
    }
}
