# Go 向け kuu 高級 API 設計

## 目標

Go ユーザーが kuu パースエンジンを使うとき、cobra/pflag ユーザーにとって自然で、かつ kuu の強みを活かした型安全な CLI パーサ体験を提供する。

## アーキテクチャ

```
[Go ユーザーコード]
    |  struct tag + コードジェネレータ
    v
[pkg/go/kuu]  ← Go 高級 API（本設計の対象）
    |  wazero 経由の FFI 呼び出し
    v
[kuu core WASM]  ← MoonBit 製パースエンジン
```

### WASM ランタイム

wazero を採用する。理由:
- Pure Go 実装（CGO 不要）
- Go エコシステムとの親和性が最も高い
- wasmtime-go は CGO 必須でクロスコンパイルが困難

---

## API 設計: struct tag ベース + `go generate`

### 設計方針

Go の「構造体がドキュメント」という文化に合わせ、struct tag でオプション定義を行う。
`go generate` でコードジェネレータを実行し、kuu core FFI への binding コードを自動生成する。

### なぜ struct tag + go generate か

| 方式 | 長所 | 短所 |
|---|---|---|
| **struct tag + go generate** | 宣言的、型安全、補完が効く、Go らしい | ジェネレータの実装が必要 |
| ビルダーパターン (cobra 風) | 柔軟、ジェネレータ不要 | ボイラープレートが多い、typo リスク |
| reflection のみ | ジェネレータ不要 | 実行時エラー、パフォーマンス懸念 |

Go コミュニティでは `encoding/json` の struct tag、`go generate` による型安全コード生成が定着しており、この方式が最も自然。

### ただし初期は reflection ベースでもよい

`go generate` 方式は最終的なゴールだが、初期実装では runtime reflection でも十分機能する。
struct tag の仕様を先に固め、内部実装は reflection → codegen と段階的に移行できる。

---

## struct tag 仕様

### 基本構文

```
kuu:"<primary-name>[,option...]"
```

### タグオプション一覧

| オプション | 意味 | 例 |
|---|---|---|
| `--name` | ロングオプション名 | `kuu:"--depth"` |
| `-X` | ショートオプション (1文字) | `kuu:"--verbose,-v"` |
| `alias=NAME` | エイリアス（複数可） | `kuu:"--staged,alias=cached"` |
| `default=VAL` | デフォルト値 | `kuu:"--depth,default=0"` |
| `desc=TEXT` | ヘルプ説明文 | `kuu:"--depth,desc=Shallow clone depth"` |
| `required` | 必須オプション | `kuu:"--message,required"` |
| `global` | グローバルオプション | `kuu:"--verbose,global"` |
| `hidden` | ヘルプ非表示 | `kuu:"--debug,hidden"` |
| `value=NAME` | 値の表示名 | `kuu:"--depth,value=N"` |
| `choices=a\|b\|c` | 選択肢 | `kuu:"--color,choices=always\|never\|auto"` |
| `implicit=VAL` | 値省略時のデフォルト | `kuu:"--color,implicit=always"` |
| `pos` | positional 引数 | `kuu:"url,pos"` |
| `rest` | 残余引数 | `kuu:"files,rest"` |
| `count` | カウンタフラグ | `kuu:"--verbose,count"` |
| `append` | 繰り返し可能オプション | `kuu:"--author,append"` |
| `exclusive=GROUP` | 排他グループ | `kuu:"--force,exclusive=push-force"` |
| `no-VAR` | variation: --no-xxx | `kuu:"--verbose,no-reset"` |

### Go の型によるセマンティクス推論

| Go 型 | kuu マッピング | 必須/任意 |
|---|---|---|
| `bool` | `flag()` | optional (default: false) |
| `string` | `string_opt()` | optional (default: "") |
| `*string` | `string_opt()` | optional (nil = 未指定) |
| `int` | `int_opt()` | optional (default: 0) |
| `[]string` | `append_string()` | optional |
| `[]int` | `append_int()` | optional |

`required` タグが付いたフィールドは、パース後に未設定ならエラーを返す。

---

## サブコマンド設計

### interface + 構造体パターン

```go
// Command interface: サブコマンドが実装する
type Command interface {
    // コマンド名
    Name() string
    // ヘルプ説明
    Description() string
    // 実行 (パース済みの自身が渡される)
    Run(ctx context.Context) error
}
```

サブコマンドは親構造体のフィールドとして埋め込む:

```go
type RootCmd struct {
    Verbose int      `kuu:"--verbose,-v,count,global"`
    Quiet   bool     `kuu:"--quiet,-q,global"`
    Color   string   `kuu:"--color,default=auto,choices=always|never|auto,implicit=always,global"`

    // サブコマンド: kuu:"cmd" タグで宣言
    Clone   *CloneCmd  `kuu:"clone,cmd,desc=Clone a repository"`
    Commit  *CommitCmd `kuu:"commit,cmd,desc=Record changes"`
    Remote  *RemoteCmd `kuu:"remote,cmd,desc=Manage remotes"`
}
```

- ポインタ型 (`*CloneCmd`) でサブコマンドの選択状態を表現
  - `nil` = 未選択、non-nil = 選択済み
- ネストしたサブコマンドも同じパターンで再帰的に定義

### require_cmd の表現

```go
type RemoteCmd struct {
    _ struct{} `kuu:",require_cmd"` // サブコマンド必須

    Add    *RemoteAddCmd    `kuu:"add,cmd,desc=Add a remote"`
    Remove *RemoteRemoveCmd `kuu:"remove,cmd,desc=Remove a remote"`
}
```

### exclusive の表現

```go
type PushCmd struct {
    Force          bool `kuu:"--force,-f,exclusive=force-group"`
    ForceWithLease bool `kuu:"--force-with-lease,exclusive=force-group"`
}
```

同じ `exclusive=GROUP` を持つフィールド同士が排他制約となる。

---

## core FFI レイヤー

### WASM エクスポート関数（想定）

kuu core が WASM としてエクスポートする低レベル API:

```
kuu_parser_new()          -> parser_id
kuu_flag(parser_id, name, ...) -> opt_id
kuu_string_opt(parser_id, name, ...) -> opt_id
kuu_int_opt(parser_id, name, ...) -> opt_id
kuu_count(parser_id, name, ...) -> opt_id
kuu_append_string(parser_id, name, ...) -> opt_id
kuu_append_int(parser_id, name, ...) -> opt_id
kuu_sub(parser_id, name, ...) -> child_parser_id
kuu_positional(parser_id, name, ...) -> opt_id
kuu_rest(parser_id, name, ...) -> opt_id
kuu_exclusive(parser_id, opt_ids...)
kuu_required(parser_id, opt_id)
kuu_require_cmd(parser_id)
kuu_parse(parser_id, args...) -> result_id | error
kuu_get_bool(opt_id) -> (bool, is_set)
kuu_get_string(opt_id) -> (string, is_set)
kuu_get_int(opt_id) -> (int, is_set)
kuu_get_strings(opt_id) -> ([]string, is_set)
kuu_get_ints(opt_id) -> ([]int, is_set)
kuu_result_child(result_id, name) -> child_result_id?
kuu_generate_help(parser_id) -> string
```

### Go 側の低レベルラッパー (internal/ffi)

```go
package ffi

// wazero でロードした kuu.wasm のインスタンスを管理
type Runtime struct { ... }

func NewRuntime() (*Runtime, error)
func (r *Runtime) NewParser() ParserID
func (r *Runtime) Flag(pid ParserID, name string, opts ...FlagOption) OptID
// ... 各 core API に対応
```

### Go 側の高レベル API (pkg/kuu)

```go
package kuu

// Parse は struct tag を解析し、core FFI 経由でパースを実行し、
// 結果を構造体に書き戻す。
func Parse[T any](args []string) (*T, error)

// MustParse はエラー時に os.Exit(1) する Parse のラッパー。
// ヘルプ表示やエラーメッセージの出力も自動で行う。
func MustParse[T any](args []string) *T

// ParseWithConfig はカスタム設定付きの Parse。
func ParseWithConfig[T any](args []string, cfg Config) (*T, error)

type Config struct {
    // HelpWriter: ヘルプ出力先 (default: os.Stderr)
    HelpWriter io.Writer
    // ErrorWriter: エラー出力先 (default: os.Stderr)
    ErrorWriter io.Writer
    // NoExit: MustParse でも os.Exit しない (テスト用)
    NoExit bool
}
```

---

## cobra との差別化

### kuu でしかできないこと

1. **variation 系フラグ**: `--no-verify`, `--reset-author` 等の自動生成。cobra では手動実装が必要
2. **implicit_value**: `--color` (= `--color=always`) のように値省略可能なオプション。pflag の `NoOptDefVal` より宣言的
3. **exclusive 制約**: struct tag で宣言的に排他制約を表現。cobra では `MarkFlagsMutuallyExclusive` を手動呼び出し
4. **serial positional**: 複数の positional 引数を型安全に順序付きで定義
5. **統一パースエンジン**: 全言語で同一のパース挙動を保証（WASM ベース）

### cobra からの移行パス

cobra ユーザーにとって自然な概念対応:

| cobra | kuu (Go) |
|---|---|
| `cobra.Command` | struct + `Command` interface |
| `cmd.Flags().StringP()` | struct tag `kuu:"--name,-n"` |
| `cmd.PersistentFlags()` | `global` タグ |
| `RunE func` | `Run(ctx) error` メソッド |
| `Args: cobra.ExactArgs(1)` | `pos` + `required` タグ |
| `MarkFlagRequired` | `required` タグ |
| `MarkFlagsMutuallyExclusive` | `exclusive=GROUP` タグ |

---

## パース結果へのアクセスパターン

### 基本: 構造体フィールドに直接マッピング

```go
root, err := kuu.Parse[RootCmd](os.Args[1:])
if err != nil { ... }

fmt.Println(root.Verbose)  // int: 0, 1, 2, ...
fmt.Println(root.Color)    // string: "auto", "always", ...
```

### サブコマンドのディスパッチ

```go
switch {
case root.Clone != nil:
    // CloneCmd のフィールドに直接アクセス
    fmt.Println(root.Clone.URL)
    fmt.Println(root.Clone.Depth)
case root.Commit != nil:
    fmt.Println(root.Commit.Message)
}
```

### Command interface による実行

```go
// Command interface を実装していればディスパッチも自動化可能
if err := kuu.Execute[RootCmd](ctx, os.Args[1:]); err != nil {
    os.Exit(1)
}
```

`Execute` は Parse 後にアクティブなサブコマンドの `Run()` を再帰的に呼び出す。

---

## dashdash (--) の扱い

```go
type CheckoutCmd struct {
    Branch string   `kuu:"branch,pos,desc=Branch to checkout"`
    Force  bool     `kuu:"--force,-f"`
    Files  []string `kuu:",dashdash,desc=Files to checkout"` // -- 以降
}
```

`dashdash` タグで `--` 以降の引数をキャプチャする。

---

## 実装フェーズ

### Phase 1: reflection ベース MVP
- struct tag パーサ
- wazero + kuu core WASM ロード
- 基本型 (bool, string, int, []string, []int) のマッピング
- サブコマンド (ポインタ型)
- Parse / MustParse

### Phase 2: 制約・高度な機能
- exclusive, required
- choices, implicit_value
- variation 系フラグ
- dashdash, serial
- count

### Phase 3: codegen
- `kuugen` コマンド (`go generate` 用)
- reflection → 生成コードへの移行
- パフォーマンス最適化

### Phase 4: DX
- エラーメッセージの改善
- シェル補完生成
- ドキュメント生成

---

## 未決定事項

1. **WASM バイナリの配布方法**: Go の embed で同梱するか、別途ダウンロードか
   - 推奨: `//go:embed kuu.wasm` で同梱（依存の透明性）
2. **`go generate` コマンド名**: `kuugen` or `kuu-gen` or `kuu generate`
3. **エラー型の設計**: sentinel error vs typed error vs error wrapping
   - 推奨: `kuu.ParseError` 型 + `errors.Is`/`errors.As` 対応
4. **スレッドセーフティ**: WASM インスタンスの共有方針
   - 推奨: Parse 呼び出しごとに新しい WASM インスタンス（パース処理は高速なので問題ない）
