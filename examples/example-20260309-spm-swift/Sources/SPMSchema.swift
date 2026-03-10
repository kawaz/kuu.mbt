/// SPM CLI schema definition for kuu WASM bridge.
/// Models: swift build | test | run | package (init | update | resolve | show-dependencies | ...)
enum SPMSchema {
    static func build() -> [String: Any] {
        [
            "version": 1,
            "description": "swift - Swift Package Manager",
            "opts": globalOpts() + [
                command("build", description: "Build Swift packages", opts: [
                    stringOpt("product", description: "Build the specified product"),
                    stringOpt("target", description: "Build the specified target"),
                    flag("show-bin-path", description: "Print the binary output path"),
                    flag("build-tests", description: "Build both source and test targets"),
                    stringOpt("build-system", description: "Build system to use", choices: ["native", "xcode"]),
                ]),
                command("test", description: "Run package tests", opts: [
                    stringOpt("filter", description: "Run test cases matching a regular expression"),
                    appendString("skip", description: "Skip test cases matching a regular expression"),
                    flag("parallel", description: "Run tests in parallel"),
                    intOpt("num-workers", description: "Number of parallel workers"),
                    flag("enable-code-coverage", description: "Enable code coverage"),
                    stringOpt("xunit-output", description: "Path to generate xUnit XML output"),
                    flag("list-tests", description: "List available tests without running them"),
                ]),
                command("run", description: "Build and run an executable product", opts: [
                    flag("skip-build", description: "Skip building the executable product"),
                    flag("build-tests", description: "Build both source and test targets"),
                    positional("executable", description: "The executable to run"),
                    rest("arguments", description: "Arguments passed to the executable"),
                ]),
                command("package", description: "Perform operations on Swift packages", opts: [
                    command("init", description: "Initialize a new package", opts: [
                        stringOpt("type", description: "Package type", choices: ["empty", "library", "executable", "system-module", "manifest", "build-tool-plugin", "command-plugin", "macro"]),
                        stringOpt("name", description: "Provide custom package name"),
                    ]),
                    command("update", description: "Update package dependencies", opts: [
                        flag("dry-run", shorts: "n", description: "Display the list of dependencies that can be updated"),
                    ]),
                    command("resolve", description: "Resolve package dependencies", opts: [
                        stringOpt("version", description: "The version to resolve at"),
                        stringOpt("branch", description: "The branch to resolve at"),
                        stringOpt("revision", description: "The revision to resolve at"),
                        positional("package-name", description: "The name of the package to resolve"),
                    ]),
                    command("show-dependencies", description: "Print the resolved dependency graph", opts: [
                        stringOpt("format", description: "Output format", choices: ["text", "dot", "json", "flatlist"]),
                        stringOpt("output-path", shorts: "o", description: "The output path"),
                    ]),
                    command("clean", description: "Delete build artifacts"),
                    command("reset", description: "Reset the complete cache/build directory"),
                    command("edit", description: "Put a package in editable mode", opts: [
                        stringOpt("revision", description: "The revision to edit"),
                        stringOpt("branch", description: "The branch to create"),
                        stringOpt("path", description: "Create or use the checkout at this path"),
                        positional("package-name", description: "The name of the package to edit"),
                    ]),
                    command("unedit", description: "Remove a package from editable mode", opts: [
                        flag("force", description: "Unedit the package even if it has uncommitted changes"),
                        positional("package-name", description: "The name of the package to unedit"),
                    ]),
                    command("describe", description: "Describe the current package"),
                    command("dump-package", description: "Print parsed Package.swift as JSON"),
                    command("add-dependency", description: "Add a package dependency", opts: [
                        positional("dependency", description: "URL or path of the package to add"),
                        stringOpt("from", description: "The minimum version requirement"),
                        stringOpt("exact", description: "Depend on the exact version"),
                        stringOpt("up-to-next-major-from", description: "Up to next major version"),
                        stringOpt("branch", description: "Depend on a specific branch"),
                        stringOpt("revision", description: "Depend on a specific revision"),
                    ]),
                    command("add-target", description: "Add a new target to the manifest", opts: [
                        stringOpt("type", description: "Target type", choices: ["library", "executable", "test", "plugin", "macro"]),
                        appendString("dependencies", description: "Target dependencies"),
                        positional("name", description: "Name of the new target"),
                    ]),
                ]),
            ] as [Any],
        ]
    }

    // MARK: - Global Options

    private static func globalOpts() -> [[String: Any]] {
        [
            flag("verbose", shorts: "v", global: true, description: "Increase verbosity to include informational output"),
            flag("very-verbose", global: true, aliases: ["vv"], description: "Increase verbosity to include debug output"),
            flag("quiet", shorts: "q", global: true, description: "Decrease verbosity to only include error output"),
            stringOpt("package-path", global: true, description: "Specify the package path to operate on"),
            stringOpt("scratch-path", global: true, description: "Specify a custom scratch directory path (default .build)"),
            stringOpt("cache-path", global: true, description: "Specify the shared cache directory path"),
            stringOpt("configuration", shorts: "c", global: true, description: "Build with configuration", choices: ["debug", "release"]),
            stringOpt("arch", global: true, description: "Build for the specified architecture"),
            stringOpt("swift-sdk", global: true, description: "Filter by Swift SDK"),
            intOpt("jobs", shorts: "j", global: true, description: "The number of jobs to spawn in parallel"),
            flag("disable-sandbox", global: true, description: "Disable using the sandbox when executing subprocesses"),
            flag("enable-dependency-cache", global: true, description: "Use a shared cache when fetching dependencies"),
            flag("enable-build-manifest-caching", global: true, description: "Enable build manifest caching"),
        ]
    }

    // MARK: - Schema Helpers

    private static func flag(_ name: String, shorts: String? = nil, global: Bool = false, aliases: [String]? = nil, description: String = "") -> [String: Any] {
        var d: [String: Any] = ["kind": "flag", "name": name, "description": description]
        if let s = shorts { d["shorts"] = s }
        if global { d["global"] = true }
        if let a = aliases { d["aliases"] = a }
        return d
    }

    private static func stringOpt(_ name: String, shorts: String? = nil, global: Bool = false, description: String = "", choices: [String]? = nil) -> [String: Any] {
        var d: [String: Any] = ["kind": "string", "name": name, "default": "", "description": description]
        if let s = shorts { d["shorts"] = s }
        if global { d["global"] = true }
        if let c = choices { d["choices"] = c }
        return d
    }

    private static func intOpt(_ name: String, shorts: String? = nil, global: Bool = false, description: String = "") -> [String: Any] {
        var d: [String: Any] = ["kind": "int", "name": name, "default": 0, "description": description]
        if let s = shorts { d["shorts"] = s }
        if global { d["global"] = true }
        return d
    }

    private static func appendString(_ name: String, description: String = "") -> [String: Any] {
        ["kind": "append_string", "name": name, "description": description]
    }

    private static func positional(_ name: String, description: String = "") -> [String: Any] {
        ["kind": "positional", "name": name, "description": description]
    }

    private static func rest(_ name: String, description: String = "") -> [String: Any] {
        ["kind": "rest", "name": name, "description": description]
    }

    private static func command(_ name: String, description: String = "", opts: [[String: Any]] = []) -> [String: Any] {
        var d: [String: Any] = ["kind": "command", "name": name, "description": description]
        if !opts.isEmpty { d["opts"] = opts }
        return d
    }
}
