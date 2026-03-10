import Foundation

// ──────────────────────────────────────────────
// SPM CLI parser demo using kuu (WASM bridge)
// ──────────────────────────────────────────────
// This program demonstrates kuu's cross-language capability:
//   Swift -> bun -> kuu WASM -> JSON result
//
// Usage:
//   spm-swift build --product MyApp -c release -v
//   spm-swift test --filter ParserTests --parallel
//   spm-swift run my-tool -- --input data.json
//   spm-swift package init --type executable --name MyApp
//   spm-swift --help

let bridge = KuuBridge()
let schema = SPMSchema.build()

// Drop argv[0] (executable name)
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

    // Display parsed result
    printHeader("Global Options")
    printIfSet("verbose", result.bool("verbose"))
    printIfSet("very-verbose", result.bool("very-verbose"))
    printIfSet("quiet", result.bool("quiet"))
    printIfNonEmpty("configuration", result.string("configuration"))
    printIfNonEmpty("package-path", result.string("package-path"))
    printIfNonEmpty("scratch-path", result.string("scratch-path"))
    printIfNonEmpty("cache-path", result.string("cache-path"))
    printIfNonEmpty("arch", result.string("arch"))
    printIfNonEmpty("swift-sdk", result.string("swift-sdk"))
    if let jobs = result.int("jobs"), jobs != 0 { printKV("jobs", jobs) }
    printIfSet("disable-sandbox", result.bool("disable-sandbox"))
    printIfSet("enable-dependency-cache", result.bool("enable-dependency-cache"))

    // Subcommand routing
    guard let cmd = result.command else {
        printHeader("No Subcommand")
        print("  (use --help to see available commands)")
        exit(0)
    }

    switch cmd.name {
    case "build":
        printHeader("Command: build")
        printIfNonEmpty("product", cmd.string("product"))
        printIfNonEmpty("target", cmd.string("target"))
        printIfSet("show-bin-path", cmd.bool("show-bin-path"))
        printIfSet("build-tests", cmd.bool("build-tests"))
        printIfNonEmpty("build-system", cmd.string("build-system"))

    case "test":
        printHeader("Command: test")
        printIfNonEmpty("filter", cmd.string("filter"))
        let skips = cmd.strings("skip")
        if !skips.isEmpty { printKV("skip", skips.joined(separator: ", ")) }
        printIfSet("parallel", cmd.bool("parallel"))
        if let n = cmd.int("num-workers"), n != 0 { printKV("num-workers", n) }
        printIfSet("enable-code-coverage", cmd.bool("enable-code-coverage"))
        printIfNonEmpty("xunit-output", cmd.string("xunit-output"))
        printIfSet("list-tests", cmd.bool("list-tests"))

    case "run":
        printHeader("Command: run")
        printIfNonEmpty("executable", cmd.string("executable"))
        printIfSet("skip-build", cmd.bool("skip-build"))
        printIfSet("build-tests", cmd.bool("build-tests"))
        let passthrough = cmd.strings("arguments")
        if !passthrough.isEmpty { printKV("arguments", passthrough.joined(separator: " ")) }

    case "package":
        printHeader("Command: package")
        if let sub = cmd.command {
            printPackageSubcommand(sub)
        } else {
            print("  (use 'package --help' for subcommands)")
        }

    default:
        printHeader("Command: \(cmd.name)")
        print("  values: \(cmd.values)")
    }

} catch {
    fputs("fatal: \(error)\n", stderr)
    exit(2)
}

// MARK: - Package subcommand display

func printPackageSubcommand(_ sub: CommandResult) {
    switch sub.name {
    case "init":
        printKV("subcommand", "init")
        printIfNonEmpty("type", sub.string("type"))
        printIfNonEmpty("name", sub.string("name"))

    case "update":
        printKV("subcommand", "update")
        printIfSet("dry-run", sub.bool("dry-run"))

    case "resolve":
        printKV("subcommand", "resolve")
        printIfNonEmpty("package-name", sub.string("package-name"))
        printIfNonEmpty("version", sub.string("version"))
        printIfNonEmpty("branch", sub.string("branch"))
        printIfNonEmpty("revision", sub.string("revision"))

    case "show-dependencies":
        printKV("subcommand", "show-dependencies")
        printIfNonEmpty("format", sub.string("format"))
        printIfNonEmpty("output-path", sub.string("output-path"))

    case "add-dependency":
        printKV("subcommand", "add-dependency")
        printIfNonEmpty("dependency", sub.string("dependency"))
        printIfNonEmpty("from", sub.string("from"))
        printIfNonEmpty("exact", sub.string("exact"))
        printIfNonEmpty("branch", sub.string("branch"))

    case "add-target":
        printKV("subcommand", "add-target")
        printIfNonEmpty("name", sub.string("name"))
        printIfNonEmpty("type", sub.string("type"))
        let deps = sub.strings("dependencies")
        if !deps.isEmpty { printKV("dependencies", deps.joined(separator: ", ")) }

    default:
        printKV("subcommand", sub.name)
    }
}

// MARK: - Output helpers

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
