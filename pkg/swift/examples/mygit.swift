// mygit.swift -- kuu/swift API で構築する git クローンのサンプル
//
// これはモックコードです。kuu Swift ラッパーの API 設計を示すために
// 実際のパース実装なしで「ユーザーがどう書くか」を表現しています。
//
// MoonBit 版 examples/20260308-mygit/main.mbt と同じ CLI 構造を
// Swift の型システムで表現しています。全14サブコマンドを網羅。

import Kuu

// MARK: - 共通オプション

struct GlobalOptions: ParsableArguments {
    @Count(name: .longAndShort, isGlobal: true, variations: [.reset(prefix: "no")])
    var verbose: Int

    @Flag(name: .longAndShort, isGlobal: true)
    var quiet = false

    @Option(isGlobal: true, choices: ["always", "never", "auto"], implicitValue: "always")
    var color: String = "auto"

    @Flag(name: .customLong("debug-internal"), isGlobal: true, isHidden: true)
    var debugInternal = false

    static var exclusions: [[AnyOption]] { [[$verbose, $quiet]] }
}

// MARK: - Root

struct MyGit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mygit",
        abstract: "A sample git-like CLI built with kuu",
        subcommands: [
            Clone.self, Commit.self, Log.self, Add.self,
            Push.self, Pull.self, Branch.self, Checkout.self,
            Diff.self, Status.self, Tag.self,
            Remote.self, Stash.self, Config.self,
        ],
        requiresSubcommand: true
    )
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
}

// MARK: - clone

struct Clone: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Clone a repository")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Argument(help: ArgumentHelp("Repository URL", valueName: "URL")) var url: String
    @Argument(help: "Target directory") var directory: String?
    @Option(help: ArgumentHelp("Shallow clone with N commits", valueName: "N")) var depth: Int = 0
    @Option(name: .longAndShort, help: ArgumentHelp("Checkout this branch", valueName: "BRANCH")) var branch: String?
    @Flag(help: "Create a bare repository") var bare = false
    mutating func run() throws {
        print("Cloning \(url)...")
        if let dir = directory { print("  into: \(dir)") }
        if depth > 0 { print("  depth: \(depth)") }
        if let b = branch { print("  branch: \(b)") }
        if bare { print("  bare: true") }
    }
}

// MARK: - commit

struct Commit: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Record changes")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    // required + post filter
    @Option(name: .longAndShort, help: ArgumentHelp("Commit message", valueName: "MSG"),
            filters: [.trim, .nonEmpty])
    var message: String
    @Flag(name: .longAndShort, help: "Stage all modified files") var all = false
    @Flag(help: "Amend the previous commit") var amend = false
    // default=true, --no-verify で false
    @Flag(defaultValue: true, variations: [.false(prefix: "no")],
          help: "Run pre-commit hooks") var verify: Bool
    @Flag(variations: [.unset(prefix: "no")],
          help: "Override author date") var authorDateIsCommitterDate = false
    mutating func run() throws {
        print("Committing: \(message)")
        if all { print("  --all") }
        if amend { print("  --amend") }
        if !verify { print("  --no-verify") }
    }
}

// MARK: - log

struct Log: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show commit logs")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Flag(help: "One line per commit") var oneline = false
    @Option(name: .longAndShort, help: ArgumentHelp("Limit commits", valueName: "N")) var maxCount: Int = 0
    @Repeatable(help: ArgumentHelp("Filter by author", valueName: "PATTERN")) var author: [String]
    @Option(choices: ["oneline","short","medium","full","fuller","reference","raw"],
            help: "Pretty-print format") var format: String = "medium"
    @Flag(help: "Draw commit graph") var graph = false
    @Rest(help: "Limit to paths") var paths: [String]
    mutating func run() throws { print("Showing log") }
}

// MARK: - add

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add file contents to the index")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Flag(name: .longAndShort, help: "Allow ignored files") var force = false
    @Flag(name: .customLong("dry-run"), aliases: ["dryrun"], help: "Dry run") var dryRun = false
    @Flag(name: .longAndShort, help: "Interactively stage hunks") var patch = false
    @Rest(help: "Files to add") var files: [String]
    mutating func run() throws { print("git add \(files.joined(separator: " "))") }
}

// MARK: - push

struct Push: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Update remote refs")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Argument(help: "Remote name") var remote: String?
    @Argument(help: "Branch name") var branch: String?
    @Flag(name: .longAndShort, help: "Force push") var force = false
    @Flag(help: "Safer force push") var forceWithLease = false
    static var exclusions: [[AnyOption]] { [[$force, $forceWithLease]] }
    @Flag(help: "Push all tags") var tags = false
    @Flag(name: .longAndShort, help: "Set upstream") var setUpstream = false
    @Flag(name: .longAndShort, help: "Delete remote branch") var delete = false
    mutating func run() throws { print("Pushing to \(remote ?? "origin")") }
}

// MARK: - pull

struct Pull: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Fetch and merge")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Argument(help: "Remote name") var remote: String?
    @Argument(help: "Branch name") var branch: String?
    @Flag(name: .longAndShort, help: "Rebase instead of merge") var rebase = false
    @Flag(help: "Only fast-forward merges") var ffOnly = false
    static var exclusions: [[AnyOption]] { [[$rebase, $ffOnly]] }
    mutating func run() throws { print("git pull") }
}

// MARK: - branch

struct Branch: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List, create, or delete branches")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Argument(help: "Branch name") var name: String?
    @Flag(name: .longAndShort, help: "Delete a branch") var delete = false
    @Flag(name: .customLong("force-delete"), aliases: ["D"], help: "Force delete") var forceDelete = false
    static var exclusions: [[AnyOption]] { [[$delete, $forceDelete]] }
    @Flag(name: .longAndShort, help: "List branches") var list = false
    @Flag(name: .longAndShort, help: "Show local and remote") var all = false
    @Flag(name: .longAndShort, help: "Move/rename") var move = false
    mutating func run() throws { if list || name == nil { print("Listing branches...") } }
}

// MARK: - checkout

struct Checkout: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Switch branches or restore files")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Argument(help: "Branch or commit") var target: String?
    @Option(name: .longAndShort, help: ArgumentHelp("Create new branch", valueName: "BRANCH"))
    var create: String?
    @Flag(name: .longAndShort, help: "Force checkout") var force = false
    @DashDash var files: [String]  // -- 以降のファイル指定
    mutating func run() throws {
        print("git checkout \(target ?? "")")
        if !files.isEmpty { print("  -- \(files.joined(separator: " "))") }
    }
}

// MARK: - diff

struct Diff: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show changes between commits")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Flag(name: .customLong("staged"), aliases: ["cached"], help: "Show staged changes") var staged = false
    @Flag(help: "Show diffstat only") var stat = false
    @Option(name: .longAndShort, help: ArgumentHelp("Lines of context", valueName: "N"),
            implicitValue: 3) var unified: Int = 3  // implicit_value 付き
    @Flag(help: "Show only changed file names") var nameOnly = false
    @Rest(help: "Limit to paths") var paths: [String]
    mutating func run() throws { print("git diff") }
}

// MARK: - status

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show working tree status")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Flag(name: .longAndShort, help: "Short format") var short = false
    @Flag(name: .longAndShort, help: "Show branch info") var branch = false
    @Flag(help: "Machine-readable output") var porcelain = false
    mutating func run() throws { print("git status") }
}

// MARK: - tag

struct Tag: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create, list, delete or verify tags")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Flag(name: .longAndShort, help: "List tags") var list = false
    @Flag(name: .longAndShort, help: "Delete a tag") var delete = false
    @Flag(name: .longAndShort, help: "Annotated tag") var annotate = false
    static var exclusions: [[AnyOption]] { [[$list, $delete, $annotate]] }
    @Option(name: .longAndShort, help: ArgumentHelp("Tag message", valueName: "MSG")) var message: String?
    @Argument(help: "Tag name") var tagname: String?
    mutating func run() throws { print("git tag \(tagname ?? "")") }
}

// MARK: - remote (nested)

struct Remote: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage remotes",
        subcommands: [Add.self, Remove.self, Rename.self],
        requiresSubcommand: true
    )
    @OptionGroup(isGlobal: true) var globals: GlobalOptions

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a remote")
        @OptionGroup(isGlobal: true) var globals: GlobalOptions
        @Flag(name: .longAndShort, help: "Fetch after adding") var fetch = false
        @Serial var spec: RemoteAddSpec  // serial() + never() に対応
        struct RemoteAddSpec: SerialArguments {
            @Argument(help: "Remote name") var name: String
            @Argument(help: "Remote URL") var url: String
        }
        mutating func run() throws { print("Adding remote '\(spec.name)' -> \(spec.url)") }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a remote")
        @OptionGroup(isGlobal: true) var globals: GlobalOptions
        @Argument(help: "Remote name") var name: String
        mutating func run() throws { print("Removing remote '\(name)'") }
    }

    struct Rename: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rename a remote")
        @OptionGroup(isGlobal: true) var globals: GlobalOptions
        @Serial var spec: RenameSpec
        struct RenameSpec: SerialArguments {
            @Argument(help: "Old name") var old: String
            @Argument(help: "New name") var new: String
        }
        mutating func run() throws { print("Renaming '\(spec.old)' -> '\(spec.new)'") }
    }
}

// MARK: - stash (nested)

struct Stash: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stash changes",
        subcommands: [StashPush.self, Pop.self, StashList.self, Drop.self],
        requiresSubcommand: true
    )
    @OptionGroup(isGlobal: true) var globals: GlobalOptions

    struct StashPush: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "push", abstract: "Save modifications")
        @OptionGroup(isGlobal: true) var globals: GlobalOptions
        @Option(name: .longAndShort, help: ArgumentHelp("Message", valueName: "MSG")) var message: String?
        @DashDash var files: [String]
        mutating func run() throws { print("git stash push") }
    }

    struct Pop: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Apply and remove stash")
        @OptionGroup(isGlobal: true) var globals: GlobalOptions
        @Option(help: ArgumentHelp("Stash index", valueName: "N"), implicitValue: 0) var index: Int = 0
        mutating func run() throws { print("git stash pop stash@{\(index)}") }
    }

    struct StashList: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List stash entries")
        @OptionGroup(isGlobal: true) var globals: GlobalOptions
        mutating func run() throws { print("git stash list") }
    }

    struct Drop: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Drop a stash entry")
        @OptionGroup(isGlobal: true) var globals: GlobalOptions
        @Option(help: ArgumentHelp("Stash index", valueName: "N"), implicitValue: 0) var index: Int = 0
        mutating func run() throws { print("git stash drop stash@{\(index)}") }
    }
}

// MARK: - config

struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Get and set options")
    @OptionGroup(isGlobal: true) var globals: GlobalOptions
    @Flag(help: "Use global config") var global = false
    @Flag(help: "Use repository config") var local = false
    @Flag(help: "Use system config") var system = false
    static var exclusions: [[AnyOption]] { [[$global, $local, $system]] }
    @Serial var keyValue: ConfigKeyValue
    struct ConfigKeyValue: SerialArguments {
        @Argument(help: "Config key") var key: String?
        @Argument(help: "Config value") var value: String?
    }
    mutating func run() throws {
        let scope = global ? "--global" : local ? "--local" : system ? "--system" : "(default)"
        if let k = keyValue.key {
            if let v = keyValue.value { print("git config \(scope) \(k) \(v)") }
            else { print("git config \(scope) \(k)") }
        }
    }
}

// MARK: - Entry Point

@main
enum Main {
    static func main() { MyGit.main() }
}
