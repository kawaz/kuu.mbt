# kuu Swift API 設計書

## 設計思想

### Swift way な API 哲学

kuu の Swift ラッパーは「Swift ユーザーが Swift-native だと感じる CLI パーサ」を目指す。
core (MoonBit/WASM) の低レベル API を FFI で利用しつつ、Swift のイディオムで包み隠す。

- **Protocol-Oriented**: `ParsableCommand` プロトコルでコマンドを定義
- **Property Wrapper Driven**: `@Flag`, `@Option`, `@Argument`, `@DashDash` で宣言的にオプション定義
- **Type Safety**: required は non-optional 型、optional は `T?`
- **Nested Commands**: サブコマンドを型としてネストし、`CommandConfiguration` で登録
- **Validation Built-in**: property wrapper のパラメータで制約を表現

### swift-argument-parser との差別化

swift-argument-parser は優れたライブラリだが、kuu core の強みを活かす点で差別化する:

| 機能 | swift-argument-parser | kuu/swift |
|---|---|---|
| **Variations** | `@Flag(inversion:)` で `--no-` のみ | 5種類の variation を自由に組み合わせ |
| **implicit_value** | 非対応 | `implicitValue:` パラメータで対応 |
| **choices** の宣言的指定 | enum への conform が必要 | `choices: [...]` で直接指定可能 |
| **choices + implicit_value** | 不可能 | 自然に組み合わせ可能 |
| **Serial** (位置引数グループ) | 単純な位置引数のみ | `@Serial` で構造化された位置引数グループ |
| **`--` セパレータ** | 手動処理 | `@DashDash` で型安全に取得 |
| **`append_dashdash`** | 非対応 | `@DashDash(repeating: true)` |
| **排他制約** | `@Flag` の exclusivity のみ | 任意のオプション組み合わせで `exclusive()` |
| **count** (`-vvv`) | `@Flag(.count)` | `@Count` 専用 wrapper で明確 |
| **post フィルタチェーン** | `transform:` のみ | `.trim`, `.nonEmpty`, `.oneOf`, `.inRange` を合成 |
| **クロスプラットフォーム** | Swift Only | WASM ベースで全プラットフォーム同一動作 |
| **他言語との一貫性** | N/A | 同じ core で TS/Go/Rust/Python と同じパース動作を保証 |

---

## FFI 接続方式

### 方式 A: C ABI (推奨)

MoonBit を WASM にコンパイルし、wasm2c 等で C ABI 互換スタティックライブラリ化。Swift Package Manager で配布可能。

**利点**: ネイティブ速度、追加ランタイム不要
**欠点**: wasm2c 等のビルドパイプライン構築が必要

### 方式 B: WasmKit

Swift ネイティブ WASM ランタイム。ビルドパイプラインが単純だが WasmKit 依存。

### 方式 C: JavaScriptCore

Apple プラットフォーム限定。追加依存なしだが JS ブリッジのオーバーヘッド。

### 選定

MVP は **方式 A (C ABI)** を推奨。CLI ツールに求められる起動速度とゼロ依存に最も適合。

---

## プロトコル

### `ParsableCommand`

```swift
protocol ParsableCommand {
    static var configuration: CommandConfiguration { get }
    static var exclusions: [[AnyOption]] { get }
    mutating func run() throws
    init()
}
```

### `CommandConfiguration`

```swift
struct CommandConfiguration {
    var commandName: String?
    var abstract: String
    var discussion: String
    var subcommands: [ParsableCommand.Type]
    var defaultSubcommand: ParsableCommand.Type?
    var requiresSubcommand: Bool      // true -> require_cmd() 相当
    var helpNames: NameSpecification
}
```

### `ParsableArguments`

共通オプションの mixin 用。`run()` を持たない。

```swift
protocol ParsableArguments { init() }
```

### `SerialArguments`

`serial()` に対応する位置引数グループ。

```swift
protocol SerialArguments: ParsableArguments {}
```

---

## Property Wrapper 一覧

### `@Flag` -- Bool フラグ

```swift
@propertyWrapper
struct Flag {
    var name: NameSpecification
    var help: ArgumentHelp?
    var isGlobal: Bool                // default: false
    var isHidden: Bool                // default: false
    var aliases: [String]
    var defaultValue: Bool            // default: false
    var variations: [Variation]

    var wrappedValue: Bool
}
```

### `@Option` -- 値付きオプション

```swift
@propertyWrapper
struct Option<Value: ExpressibleByArgument> {
    var name: NameSpecification
    var help: ArgumentHelp?
    var isGlobal: Bool
    var isHidden: Bool
    var defaultValue: Value?          // nil なら required
    var implicitValue: Value?         // --color (値なし) = implicitValue
    var choices: [Value]?
    var filters: [Filter<Value>]
    var variations: [Variation]

    var wrappedValue: Value           // required (non-optional)
    // var wrappedValue: Value?       // optional
}
```

**required/optional の判定ルール**:
- `defaultValue` nil + non-optional -> required
- `defaultValue` あり -> optional (デフォルト値が入る)
- 型が `Value?` -> optional (未指定は nil)

### `@Count` -- カウントフラグ

```swift
@propertyWrapper
struct Count {
    var name: NameSpecification
    var help: ArgumentHelp?
    var isGlobal: Bool
    var variations: [Variation]
    var wrappedValue: Int             // -vvv -> 3
}
```

### `@Argument` -- 位置引数

```swift
@propertyWrapper
struct Argument<Value: ExpressibleByArgument> {
    var help: ArgumentHelp?
    var wrappedValue: Value           // required (non-optional)
    // var wrappedValue: Value?       // optional
}
```

### `@Rest` -- 残余位置引数

```swift
@propertyWrapper
struct Rest<Value: ExpressibleByArgument> {
    var help: ArgumentHelp?
    var wrappedValue: [Value]
}
```

### `@DashDash` -- `--` 以降の引数

```swift
@propertyWrapper
struct DashDash {
    var separator: String             // default: "--"
    var repeating: Bool               // default: false (true -> append_dashdash)
    var help: ArgumentHelp?
    var wrappedValue: [String]        // repeating=false
    // var wrappedValue: [[String]]   // repeating=true
}
```

### `@OptionGroup` -- 共通オプション mixin

```swift
@propertyWrapper
struct OptionGroup<Value: ParsableArguments> {
    var isGlobal: Bool
    var wrappedValue: Value
}
```

### `@Repeatable` -- 繰り返しオプション

```swift
@propertyWrapper
struct Repeatable<Value: ExpressibleByArgument> {
    var name: NameSpecification
    var help: ArgumentHelp?
    var wrappedValue: [Value]         // --author a --author b -> ["a", "b"]
}
```

### `@Serial` -- 位置引数グループ

```swift
@propertyWrapper
struct Serial<Value: SerialArguments> {
    var wrappedValue: Value
}
```

---

## 補助型

### `NameSpecification`

```swift
enum NameSpecification {
    case long                         // camelCase -> kebab-case 自動導出
    case short
    case customLong(String)
    case customShort(Character)
    case longAndShort
    case custom(long: String?, short: Character?)
}
```

### `Variation`

```swift
enum Variation {
    case toggle(prefix: String)
    case `true`(prefix: String)
    case `false`(prefix: String)
    case reset(prefix: String)
    case unset(prefix: String)
    static var inversion: Variation { .false(prefix: "no") }
}
```

### `Filter<Value>`

```swift
enum Filter<Value> {
    case trim, nonEmpty
    case oneOf([String])
    case inRange(ClosedRange<Value>)
    case custom((Value) throws -> Value)
}
```

### `ArgumentHelp`

```swift
struct ArgumentHelp: ExpressibleByStringLiteral {
    var abstract: String
    var discussion: String?
    var valueName: String?
}
```

### `ExpressibleByArgument`

```swift
protocol ExpressibleByArgument {
    init?(argument: String)
}
// String, Int, Double, Bool が標準準拠
```

---

## 型マッピング（core API -> Swift API）

| core (MoonBit) | Swift | wrappedValue |
|---|---|---|
| `flag(name, ...)` | `@Flag` | `Bool` |
| `string_opt(name, ...)` | `@Option<String>` | `String` / `String?` |
| `int_opt(name, ...)` | `@Option<Int>` | `Int` / `Int?` |
| `count(name, ...)` | `@Count` | `Int` |
| `append_string(name, ...)` | `@Repeatable<String>` | `[String]` |
| `append_int(name, ...)` | `@Repeatable<Int>` | `[Int]` |
| `positional(name, ...)` | `@Argument<String>` | `String` / `String?` |
| `rest(name, ...)` | `@Rest<String>` | `[String]` |
| `dashdash()` | `@DashDash` | `[String]` |
| `append_dashdash()` | `@DashDash(repeating: true)` | `[[String]]` |
| `sub(name, ...)` | nested `ParsableCommand` | - |
| `require_cmd()` | `requiresSubcommand: true` | - |
| `exclusive([...])` | `static var exclusions` | - |
| `required(opt)` | non-optional + no default | - |
| `serial(setup)` | `@Serial` + `SerialArguments` | - |

---

## 内部アーキテクチャ

```
+--------------------------------------------------+
|  User Code                                        |
|  struct MyGit: ParsableCommand { ... }            |
+--------------+-----------------------------------+
               | Swift property wrapper metadata
               v
+--------------------------------------------------+
|  kuu Swift API Layer                              |
|  - ParsableCommand, @Flag, @Option, ...           |
|  - CommandConfiguration, ExclusiveGroup, Serial   |
+--------------+-----------------------------------+
               | core FFI
               v
+--------------------------------------------------+
|  CKuu (C ABI bridge)                              |
|  kuu_parser_new(), kuu_flag(), kuu_parse(), ...   |
+--------------+-----------------------------------+
               | C ABI
               v
+--------------------------------------------------+
|  kuu core (MoonBit -> WASM -> C)                  |
+--------------------------------------------------+
```

### 実行フロー

1. `MyCommand.main()` を呼ぶ
2. property wrapper メタデータを収集
3. core FFI で Parser を構築
4. `core.parse(CommandLine.arguments)` を実行
5. パース結果を wrappedValue に反映
6. サブコマンドがあれば `child()` で辿り型インスタンスを構築
7. `run()` を呼ぶ

---

## エラーハンドリング

```swift
enum KuuError: Error, CustomStringConvertible {
    case parseError(message: String, helpText: String)
    case helpRequested(text: String)
    case validationError(message: String)
}
```

---

## 設計上のトレードオフ

### Mirror vs Macro

初期は **Mirror ベース** (swift-argument-parser 互換)。将来 Swift Macros (SE-0389) へ移行可能。

### ヘルプ生成

core が生成するヘルプをそのまま使う（全言語で一貫した出力を保証）。

---

## 今後の検討事項

- **Swift Macros**: コンパイル時メタデータ走査
- **completion**: zsh/bash/fish 補完スクリプト生成
- **async run**: Swift Concurrency 統合
- **Result Builder DSL**: 動的コマンド構成向けの代替 API
- **WasmKit**: プラグイン動的ロード
