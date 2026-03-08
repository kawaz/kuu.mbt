# kuu Swift API 設計書

## 設計思想

### Swift way な API 哲学

kuu の Swift ラッパーは「Swift ユーザーが Swift-native だと感じる CLI パーサ」を目指す。
core (MoonBit/WASM) の低レベル API を FFI で利用しつつ、Swift のイディオムで包み隠す。

- **Protocol-Oriented**: `ParsableCommand` プロトコルでコマンドを定義
- **Property Wrapper Driven**: `@Flag`, `@Option`, `@Argument`, `@DashDash` で宣言的にオプション定義
- **Type Safety**: required は non-optional 型、optional は `T?`
- **Nested Commands**: `@CommandGroup` で自然なサブコマンドツリー
- **Validation Built-in**: property wrapper のパラメータで制約を表現

### swift-argument-parser との違い

swift-argument-parser は優れたライブラリだが、kuu core の強みを活かす点で差別化する:

| 機能 | swift-argument-parser | kuu/swift |
|---|---|---|
| バリエーション (`--no-xxx`) | `@Flag(inversion:)` 限定 | `variations:` で任意プレフィックスを指定 |
| 暗黙値 (`--color` = `always`) | 未サポート | `implicitValue:` で対応 |
| count フラグ (`-vvv`) | `@Flag(.count)` | `@Count` 専用 wrapper で明確 |
| フィルタチェーン | Transform のみ | `trim`, `nonEmpty`, `oneOf`, `inRange` を宣言的に |
| exclusive グループ | `@Flag` enum ベース | `@ExclusiveGroup` で任意の型の組み合わせ |
| serial positional | 手動 | `@Serial` で ordered positional 列を宣言 |
| WASM core | - | パースロジックが言語非依存。全プラットフォーム同一動作 |

---

## プロトコル

### `ParsableCommand`

コマンドの基本プロトコル。すべてのコマンド・サブコマンドが準拠する。

```swift
protocol ParsableCommand {
    /// コマンドのメタデータ
    static var configuration: CommandConfiguration { get }

    /// パース後に呼ばれるエントリポイント
    mutating func run() throws

    /// デフォルト初期化子（property wrapper のデフォルト値で初期化）
    init()
}
```

### `CommandConfiguration`

```swift
struct CommandConfiguration {
    var commandName: String?         // nil の場合は型名から自動導出
    var abstract: String             // 短い説明（--help の1行目）
    var discussion: String           // 詳細説明
    var subcommands: [ParsableCommand.Type]
    var defaultSubcommand: ParsableCommand.Type?
    var helpNames: NameSpecification  // help フラグの名前
}
```

### `ParsableArguments`

オプション群だけを定義する（`run()` を持たない）。共通オプションの mixin に使う。

```swift
protocol ParsableArguments {
    init()
}
```

---

## Property Wrapper 一覧

### `@Flag` — Bool フラグ

```swift
@propertyWrapper
struct Flag {
    // 基本
    var name: NameSpecification      // .long, .short, .customLong("xxx"), .customShort("x")
    var help: ArgumentHelp?
    var isGlobal: Bool               // default: false
    var isHidden: Bool               // default: false

    // kuu 固有
    var defaultValue: Bool           // default: false
    var variations: [Variation]      // default: []

    var wrappedValue: Bool
}
```

### `@Option` — 値付きオプション（String, Int, Double, カスタム型）

```swift
@propertyWrapper
struct Option<Value: ExpressibleByArgument> {
    var name: NameSpecification
    var help: ArgumentHelp?
    var isGlobal: Bool
    var isHidden: Bool

    // 値
    var defaultValue: Value?          // nil なら required（wrappedValue は non-optional）

    // kuu 固有
    var implicitValue: Value?         // --color (値なし) = implicitValue
    var choices: [Value]?             // 列挙制限
    var filters: [Filter<Value>]      // post フィルタ
    var variations: [Variation]

    // required の場合
    var wrappedValue: Value           // non-optional

    // optional の場合（defaultValue ありまたは Value? に束縛）
    // var wrappedValue: Value?
}
```

**required/optional の判定ルール**:
- `defaultValue` が `nil` かつ型が non-optional → required（パース失敗でエラー）
- `defaultValue` あり → optional（wrappedValue は non-optional、デフォルトが入る）
- プロパティの型自体が `Value?` → optional（wrappedValue は `Value?`）

### `@Count` — カウントフラグ

```swift
@propertyWrapper
struct Count {
    var name: NameSpecification
    var help: ArgumentHelp?
    var isGlobal: Bool
    var variations: [Variation]

    var wrappedValue: Int             // -vvv → 3
}
```

### `@Argument` — 位置引数

```swift
@propertyWrapper
struct Argument<Value: ExpressibleByArgument> {
    var help: ArgumentHelp?

    var wrappedValue: Value           // required
    // var wrappedValue: Value?       // optional
}
```

### `@Rest` — 残余位置引数

```swift
@propertyWrapper
struct Rest<Value: ExpressibleByArgument> {
    var help: ArgumentHelp?

    var wrappedValue: [Value]         // 常に配列
}
```

### `@DashDash` — `--` 以降の引数

```swift
@propertyWrapper
struct DashDash {
    var separator: String             // default: "--"
    var help: ArgumentHelp?

    var wrappedValue: [String]
}
```

### `@OptionGroup` — 共通オプションの mixin

```swift
@propertyWrapper
struct OptionGroup<Value: ParsableArguments> {
    var isGlobal: Bool                // default: false

    var wrappedValue: Value
}
```

### `@Repeatable` — 繰り返しオプション

```swift
@propertyWrapper
struct Repeatable<Value: ExpressibleByArgument> {
    var name: NameSpecification
    var help: ArgumentHelp?

    var wrappedValue: [Value]         // --author a --author b → ["a", "b"]
}
```

---

## 補助型

### `NameSpecification`

```swift
enum NameSpecification {
    case long                         // プロパティ名から自動導出（camelCase → kebab-case）
    case short                        // プロパティ名の頭文字
    case customLong(String)
    case customShort(Character)
    case longAndShort                 // 両方
    case custom(long: String?, short: Character?)
}
```

### `Variation`

kuu core の `--no-xxx`, `--reset-xxx` 等を Swift で表現。

```swift
enum Variation {
    case toggle(prefix: String)       // --{prefix}-{name}: トグル
    case `true`(prefix: String)       // --{prefix}-{name}: 常に true
    case `false`(prefix: String)      // --{prefix}-{name}: 常に false
    case reset(prefix: String)        // --{prefix}-{name}: デフォルトに戻す
    case unset(prefix: String)        // --{prefix}-{name}: 未設定状態に戻す

    // ショートハンド
    static var inversion: Variation { .false(prefix: "no") }
}
```

### `Filter<Value>`

kuu core の FilterChain を Swift で表現。

```swift
enum Filter<Value> {
    // String 用
    case trim
    case nonEmpty
    case oneOf([String])

    // Numeric 用
    case inRange(ClosedRange<Value>)

    // 汎用
    case custom((Value) throws -> Value)
}
```

### `ArgumentHelp`

```swift
struct ArgumentHelp: ExpressibleByStringLiteral {
    var abstract: String
    var discussion: String?
    var valueName: String?             // ヘルプ表示のプレースホルダ（例: "N", "MSG"）
}
```

### `ExpressibleByArgument`

CLI 引数から変換可能な型を表すプロトコル。

```swift
protocol ExpressibleByArgument {
    init?(argument: String)
    static var defaultCompletionKind: CompletionKind { get }
}

// 標準準拠
extension String: ExpressibleByArgument { ... }
extension Int: ExpressibleByArgument { ... }
extension Double: ExpressibleByArgument { ... }
extension Bool: ExpressibleByArgument { ... }
```

### `ExclusiveGroup`

相互排他制約を静的に記述するためのマーカー。

```swift
/// コマンド定義内で使用:
/// static var exclusions: [[AnyOption]] { get }
```

---

## 型マッピング（core API → Swift API）

| core (MoonBit) | Swift property wrapper | wrappedValue |
|---|---|---|
| `flag(name, default?, ...)` | `@Flag` | `Bool` |
| `string_opt(name, default, ...)` | `@Option<String>` | `String` or `String?` |
| `int_opt(name, default, ...)` | `@Option<Int>` | `Int` or `Int?` |
| `count(name, ...)` | `@Count` | `Int` |
| `append_string(name, ...)` | `@Repeatable<String>` | `[String]` |
| `append_int(name, ...)` | `@Repeatable<Int>` | `[Int]` |
| `positional(name, ...)` | `@Argument<String>` | `String` or `String?` |
| `rest(name, ...)` | `@Rest<String>` | `[String]` |
| `dashdash()` | `@DashDash` | `[String]` |
| `sub(name, ...)` | `Subcommand` (型で表現) | - |
| `require_cmd()` | `CommandConfiguration` + 空 `defaultSubcommand` | - |
| `exclusive([...])` | `static var exclusions` | - |
| `required(opt)` | non-optional 型 + `defaultValue` なし | - |
| `serial(setup)` | プロパティ宣言順 = 位置引数順 | - |

---

## core API との対応表

### Parser 操作

| core API | Swift での表現 |
|---|---|
| `Parser::new()` | `ParsableCommand` 型の `init()` が暗黙的に生成 |
| `p.set_description(s)` | `CommandConfiguration(abstract: s)` |
| `p.parse(args)` | `MyCommand.main()` / `MyCommand.parseAsRoot()` |
| `result.child("xxx")` | `switch` on enum subcommand or type-based dispatch |
| `opt.get() -> T?` | property wrapper の `wrappedValue` に直接アクセス |

### オプション定義

| core API | Swift での表現 |
|---|---|
| `p.flag(name: "verbose", short: 'v', global: true)` | `@Flag(name: .longAndShort, isGlobal: true) var verbose = false` |
| `p.string_opt(name: "branch", default: "", short: 'b')` | `@Option(name: .longAndShort) var branch: String?` |
| `p.int_opt(name: "depth", default: 0)` | `@Option var depth: Int = 0` |
| `p.count(name: "verbose", short: 'v')` | `@Count(name: .longAndShort) var verbose: Int` |
| `p.append_string(name: "author")` | `@Repeatable var author: [String]` |
| `p.positional(name: "url")` | `@Argument var url: String` (required) |
| `p.positional(name: "dir")` | `@Argument var directory: String?` (optional) |
| `p.rest(name: "files")` | `@Rest var files: [String]` |
| `p.dashdash()` | `@DashDash var extraArgs: [String]` |

### 制約

| core API | Swift での表現 |
|---|---|
| `p.exclusive([a, b])` | `static var exclusions: [[AnyOption]] { [[$force, $forceLease]] }` |
| `p.required(opt)` | non-optional 型 + `defaultValue` なし |

### フィルタ

| core API | Swift での表現 |
|---|---|
| `Filter::trim().then(Filter::non_empty())` | `@Option(filters: [.trim, .nonEmpty])` |
| `Filter::one_of(choices)` | `@Option(choices: ["a", "b", "c"])` |
| `Filter::in_range(1, 100)` | `@Option(filters: [.inRange(1...100)])` |

### バリエーション

| core API | Swift での表現 |
|---|---|
| `variation_false: Some("no")` | `@Flag(variations: [.inversion])` |
| `variation_reset: Some("no")` | `@Flag(variations: [.reset(prefix: "no")])` |
| `variation_unset: Some("no")` | `@Flag(variations: [.unset(prefix: "no")])` |

### サブコマンド

| core API | Swift での表現 |
|---|---|
| `p.sub(name: "clone")` | `struct Clone: ParsableCommand { ... }` を subcommands に登録 |
| `p.require_cmd()` | `defaultSubcommand` を nil にする（デフォルト動作） |

---

## エラーハンドリング

```swift
enum KuuError: Error, CustomStringConvertible {
    case parseError(message: String, helpText: String)
    case helpRequested(text: String)
    case validationError(message: String)
}
```

- `parseError`: core の `ParseError` に対応
- `helpRequested`: core の `HelpRequested` に対応。`main()` 内で自動キャッチして stdout に出力
- `validationError`: Swift 側の追加バリデーション失敗

---

## 実行フロー

```
1. ユーザーが MyCommand.main() を呼ぶ
2. Swift ラッパーが property wrapper のメタデータを収集
3. kuu core (WASM) の Parser を構築し、各 property wrapper に対応する
   flag/string_opt/int_opt/... を登録
4. core.parse(CommandLine.arguments) を実行
5. パース結果を各 property wrapper の wrappedValue に書き戻す
6. run() を呼ぶ
```

---

## 設計上のトレードオフ

### Mirror vs Macro

Swift での property wrapper メタデータ収集には2つのアプローチがある:

1. **Mirror (Runtime Reflection)**: swift-argument-parser が採用。`Mirror(reflecting:)` でプロパティを列挙
2. **Swift Macros (Compile-time)**: Swift 5.9+ のマクロでコンパイル時にコード生成

初期実装は **Mirror ベース** を採用する。理由:
- swift-argument-parser との API 互換性が高い
- 実装が枯れている
- マクロは Swift 5.9+ 限定で、ビルドツールチェーンの制約がある

将来的にマクロベースへの移行パスを残す（property wrapper の外部 API は変えない）。

### ヘルプ生成

core が生成するヘルプテキストをそのまま使う。Swift 側で独自にヘルプを組み立てない。
理由: core のヘルプ生成は全言語で一貫した出力を保証する。
