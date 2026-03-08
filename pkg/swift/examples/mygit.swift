// mygit.swift — kuu/swift API で構築する git クローンのサンプル
//
// これはモックコードです。kuu Swift ラッパーの API 設計を示すために
// 実際のパース実装なしで「ユーザーがどう書くか」を表現しています。

import Kuu

// MARK: - 共通オプション（全サブコマンドで利用可能）

struct GlobalOptions: ParsableArguments {
    @Count(name: .longAndShort, isGlobal: true, variations: [.reset(prefix: "no")])
    var verbose: Int

    @Flag(name: .longAndShort, isGlobal: true)
    var quiet = false

    @Option(isGlobal: true, choices: ["always", "never", "auto"], implicitValue: "always")
    var color: String = "auto"

    @Flag(name: .customLong("debug-internal"), isGlobal: true, isHidden: true)
    var debugInternal = false

    static var exclusions: [[AnyOption]] {
        [[$verbose, $quiet]]
    }
}

// MARK: - Root Command

struct MyGit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mygit",
        abstract: "A sample git-like CLI built with kuu",
        subcommands: [Clone.self, Commit.self, Log.self, Remote.self, Push.self],
        requiresSubcommand: true
    )

    @OptionGroup(isGlobal: true)
    var globals: GlobalOptions
}

// MARK: - clone

struct Clone: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Clone a repository"
    )

    @OptionGroup(isGlobal: true)
    var globals: GlobalOptions

    // required positional（non-optional = 必須）
    @Argument(help: ArgumentHelp("Repository URL", valueName: "URL"))
    var url: String

    // optional positional（Optional 型 = 任意）
    @Argument(help: "Target directory")
    var directory: String?

    @Option(help: ArgumentHelp("Shallow clone with N commits", valueName: "N"))
    var depth: Int?

    @Option(name: .longAndShort, help: ArgumentHelp("Checkout this branch", valueName: "BRANCH"))
    var branch: String?

    @Flag(help: "Create a bare repository")
    var bare = false

    mutating func run() throws {
        if globals.verbose > 0 {
            print("Verbosity level: \(globals.verbose)")
        }
        print("Cloning \(url)...")
        if let dir = directory {
            print("  into: \(dir)")
        }
        if let d = depth {
            print("  depth: \(d)")
        }
        if let b = branch {
            print("  branch: \(b)")
        }
        if bare {
            print("  bare: true")
        }
    }
}

// MARK: - commit

struct Commit: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record changes to the repository"
    )

    @OptionGroup(isGlobal: true)
    var globals: GlobalOptions

    // required option: non-optional + デフォルト値なし
    @Option(name: .longAndShort, help: ArgumentHelp("Commit message", valueName: "MSG"),
            filters: [.trim, .nonEmpty])
    var message: String

    @Flag(name: .longAndShort, help: "Stage all modified files")
    var all = false

    @Flag(help: "Amend the previous commit")
    var amend = false

    // default=true のフラグ。--no-verify で false にする
    @Flag(defaultValue: true, variations: [.false(prefix: "no")],
          help: "Run pre-commit hooks (--no-verify to skip)")
    var verify: Bool

    @Flag(variations: [.unset(prefix: "no")],
          help: "Override author date with committer date")
    var authorDateIsCommitterDate = false

    mutating func run() throws {
        print("Committing: \(message)")
        if all { print("  --all") }
        if amend { print("  --amend") }
        if !verify { print("  --no-verify") }
    }
}

// MARK: - log

struct Log: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show commit logs"
    )

    @OptionGroup(isGlobal: true)
    var globals: GlobalOptions

    @Flag(help: "One line per commit")
    var oneline = false

    @Option(name: .longAndShort, help: ArgumentHelp("Limit number of commits", valueName: "N"))
    var maxCount: Int?

    // repeatable option: --author a --author b
    @Repeatable(help: ArgumentHelp("Filter by author (repeatable)", valueName: "PATTERN"))
    var author: [String]

    @Option(choices: ["oneline", "short", "medium", "full", "fuller", "reference", "raw"],
            help: "Pretty-print format")
    var format: String = "medium"

    @Flag(help: "Draw text-based graph of commit history")
    var graph = false

    // -- 以降を path として受け取る
    @Rest(help: "Limit to paths")
    var paths: [String]

    mutating func run() throws {
        print("Showing log")
        if oneline { print("  --oneline") }
        if let n = maxCount { print("  --max-count=\(n)") }
        if !author.isEmpty { print("  --author: \(author)") }
        print("  --format=\(format)")
        if graph { print("  --graph") }
        if !paths.isEmpty { print("  paths: \(paths)") }
    }
}

// MARK: - remote (nested subcommands)

struct Remote: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage set of tracked repositories",
        subcommands: [Add.self, Remove.self],
        requiresSubcommand: true
    )

    @OptionGroup(isGlobal: true)
    var globals: GlobalOptions

    // MARK: remote add

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a remote"
        )

        @OptionGroup(isGlobal: true)
        var globals: GlobalOptions

        @Flag(name: .longAndShort, help: "Fetch after adding")
        var fetch = false

        // serial positional: name, url の順序固定
        @Argument(help: "Remote name")
        var name: String

        @Argument(help: "Remote URL")
        var url: String

        mutating func run() throws {
            print("Adding remote '\(name)' -> \(url)")
            if fetch { print("  --fetch") }
        }
    }

    // MARK: remote remove

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a remote"
        )

        @OptionGroup(isGlobal: true)
        var globals: GlobalOptions

        @Argument(help: "Remote name")
        var name: String

        mutating func run() throws {
            print("Removing remote '\(name)'")
        }
    }
}

// MARK: - push

struct Push: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Update remote refs along with associated objects"
    )

    @OptionGroup(isGlobal: true)
    var globals: GlobalOptions

    @Argument(help: "Remote name")
    var remote: String?

    @Argument(help: "Branch name")
    var branch: String?

    @Flag(name: .longAndShort, help: "Force push")
    var force = false

    @Flag(help: "Safer force push")
    var forceWithLease = false

    @Flag(name: .longAndShort, help: "Set upstream for the branch")
    var setUpstream = false

    // exclusive: --force と --force-with-lease は同時に使えない
    static var exclusions: [[AnyOption]] {
        [[$force, $forceWithLease]]
    }

    mutating func run() throws {
        let remoteName = remote ?? "origin"
        print("Pushing to \(remoteName)")
        if let b = branch { print("  branch: \(b)") }
        if force { print("  --force") }
        if forceWithLease { print("  --force-with-lease") }
        if setUpstream { print("  --set-upstream") }
    }
}

// MARK: - Entry Point

@main
enum Main {
    static func main() {
        MyGit.main()
    }
}
