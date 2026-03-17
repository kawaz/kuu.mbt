import Foundation

// ──────────────────────────────────────────────
// Homebrew CLI parser demo using kuu (WASM bridge)
// ──────────────────────────────────────────────
// Demonstrates kuu's cross-language capability:
//   Swift -> bun -> kuu WASM -> JSON result
//
// Usage:
//   brew-swift install --verbose --formula node npm
//   brew-swift search --desc json
//   brew-swift tap homebrew/cask
//   brew-swift upgrade --dry-run --greedy
//   brew-swift list --versions --formula
//   brew-swift --help

let bridge = KuuBridge()
let schema = BrewSchema.build()
let args = Array(CommandLine.arguments.dropFirst())

do {
    let result = try bridge.parse(schema: schema, args: args)

    if result.helpRequested {
        print(result.help ?? "")
        exit(0)
    }

    if !result.ok {
        fputs("error: \(result.error ?? "unknown")\n", stderr)
        if let help = result.help {
            fputs("\n\(help)\n", stderr)
        }
        exit(1)
    }

    // Global options
    printHeader("Global Options")
    printIfSet("verbose", result.bool("verbose"))
    printIfSet("debug", result.bool("debug"))
    printIfSet("quiet", result.bool("quiet"))

    // Subcommand routing
    guard let cmd = result.command else {
        printHeader("No Subcommand")
        print("  (use --help to see available commands)")
        exit(0)
    }

    switch cmd.name {
    case "install":
        printInstall(cmd)
    case "search":
        printSearch(cmd)
    case "tap":
        printTap(cmd)
    case "upgrade":
        printUpgrade(cmd)
    case "list":
        printList(cmd)
    default:
        printHeader("Command: \(cmd.name)")
        print("  values: \(cmd.values)")
    }

} catch {
    fputs("fatal: \(error)\n", stderr)
    exit(2)
}

// MARK: - Subcommand Display

func printInstall(_ cmd: CommandResult) {
    printHeader("Command: install")
    printIfSet("force", cmd.bool("force"))
    printIfSet("build-from-source", cmd.bool("build-from-source"))
    printIfSet("dry-run", cmd.bool("dry-run"))
    printIfSet("formula", cmd.bool("formula"))
    printIfSet("cask", cmd.bool("cask"))
    printIfSet("HEAD", cmd.bool("HEAD"))
    printIfSet("keep-tmp", cmd.bool("keep-tmp"))
    printIfSet("ask", cmd.bool("ask"))
    printIfNonEmpty("cc", cmd.string("cc"))
    printRestArgs("packages", cmd.strings("packages"))
}

func printSearch(_ cmd: CommandResult) {
    printHeader("Command: search")
    printIfSet("formula", cmd.bool("formula"))
    printIfSet("cask", cmd.bool("cask"))
    printIfSet("desc", cmd.bool("desc"))
    printIfNonEmpty("query", cmd.string("query"))
}

func printTap(_ cmd: CommandResult) {
    printHeader("Command: tap")
    printIfSet("force", cmd.bool("force"))
    printIfSet("repair", cmd.bool("repair"))
    printIfSet("eval-all", cmd.bool("eval-all"))
    printIfSet("custom-remote", cmd.bool("custom-remote"))
    printIfNonEmpty("repository", cmd.string("repository"))
    printIfNonEmpty("url", cmd.string("url"))
}

func printUpgrade(_ cmd: CommandResult) {
    printHeader("Command: upgrade")
    printIfSet("force", cmd.bool("force"))
    printIfSet("dry-run", cmd.bool("dry-run"))
    printIfSet("formula", cmd.bool("formula"))
    printIfSet("cask", cmd.bool("cask"))
    printIfSet("greedy", cmd.bool("greedy"))
    printIfSet("greedy-latest", cmd.bool("greedy-latest"))
    printIfSet("greedy-auto-updates", cmd.bool("greedy-auto-updates"))
    printIfSet("ask", cmd.bool("ask"))
    printIfSet("display-times", cmd.bool("display-times"))
    printRestArgs("packages", cmd.strings("packages"))
}

func printList(_ cmd: CommandResult) {
    printHeader("Command: list")
    printIfSet("formula", cmd.bool("formula"))
    printIfSet("cask", cmd.bool("cask"))
    printIfSet("full-name", cmd.bool("full-name"))
    printIfSet("versions", cmd.bool("versions"))
    printIfSet("pinned", cmd.bool("pinned"))
    printIfSet("installed-on-request", cmd.bool("installed-on-request"))
    printIfSet("installed-as-dependency", cmd.bool("installed-as-dependency"))
    printIfSet("one-per-line", cmd.bool("one-per-line"))
    printIfSet("long-format", cmd.bool("long-format"))
    printIfSet("reverse", cmd.bool("reverse"))
    printIfSet("time-sort", cmd.bool("time-sort"))
    printRestArgs("packages", cmd.strings("packages"))
}

// MARK: - Output Helpers

func printHeader(_ title: String) {
    print("\n[\(title)]")
}

func printKV(_ key: String, _ value: Any) {
    print("  \(key): \(value)")
}

func printIfSet(_ key: String, _ value: Bool) {
    if value { printKV(key, true) }
}

func printIfNonEmpty(_ key: String, _ value: String?) {
    if let v = value, !v.isEmpty { printKV(key, v) }
}

func printRestArgs(_ key: String, _ values: [String]) {
    if !values.isEmpty { printKV(key, values.joined(separator: ", ")) }
}
