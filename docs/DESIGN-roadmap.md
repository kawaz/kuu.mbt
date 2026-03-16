# kuu 将来計画・未実装設計

[DESIGN-v2.md](DESIGN-v2.md) のアーキテクチャ概要を前提とした、将来の実装計画と設計案。

> **注意**: 以下は全て設計案であり、実装時に変更される可能性がある。

---

## 進行中

### Opt[T] setter 追加 + clone/adjust 実装

**状態**: PoC 中

Opt[T] に setter クロージャを追加し、ValRef を持たない形で値アクセスを抽象化する。これにより DR-037 の直交プリミティブ（clone, link, adjust）が実装可能になる。

**ブロッカー**: Array の deep-copy 意味論、setter 追加後の構築パターンの確定

**完了後に可能になること**:
- `clone(opt, name)` — 新 Ref + 新 setter/getter ペアで構造コピー
- `link(opt, val_source)` — target の setter/getter ペアを共有
- `adjust(opt, before_pre=..., after_post=...)` — setter をラップして振る舞い変更
- Variation の clone/adjust ベース実装への移行
- group コンビネータ（雛形 clone 方式）

---

## 短期（次に実装する可能性が高いもの）

### 環境変数連携 Phase 2（DR-041）

Phase 1（実装済み）: `env` パラメータでヘルプ表示用メタデータのみ。

Phase 2:
- 実際の環境変数読み取り（Finalize フェーズで適用）
- `env_prefix` — コマンドのプレフィックスと env を結合（例: `MYAPP_PORT`）
- `auto_env` — 全フラグを自動バインド（デフォルト無効）
- Opt レベルの `auto_env : Bool?` で個別制御
- サブコマンドのプレフィックスネスト（`MYAPP_SERVE_PORT`）

優先順位: CLI > 環境変数 > 設定ファイル > initial

**ブロッカー**: MoonBit の環境変数アクセス API（ターゲット別の分岐が必要: JS は `process.env`、WASM は import、native は libc `getenv`）

### エラーメッセージ品質向上

現状: `ParseErrorInfo { message, help_text }` のフラット文字列。

目標: 4層構造 + ErrorKind enum

```
error: unknown option '--prot'
  Help: --port <PORT>    ポート番号を指定 [default: 8080]
  tip: a similar option exists: '--port'
Usage: myapp serve [OPTIONS] <DIR>
For more information, try '--help'.
```

**ブロッカー**: なし（独立して進められる）

#### ErrorKind（設計案）

```moonbit
enum ErrorKind {
  UnknownOption; UnexpectedArgument; MissingRequired; InvalidValue
  ArgumentConflict; AmbiguousMatch; MissingValue; TooManyValues
  MissingSubcommand; PositionalAsFlag; MultipleUse
}
```

#### did you mean? サジェスト

Levenshtein 距離ベース（実装済み）。bpaf 式のコンテキスト認識（"not expected in this context"）は未実装。

#### セマンティックスタイリング

5カテゴリで出力を装飾: error, valid, invalid, literal, hint

### sub_parser_combinator 抽象化（DR-039）

install_eq_split_node と install_short_combine_node を汎用コンビネータとして一般化:

```
sub_parser_combinator(
  pre_filter,      // 引数の前処理（= の位置検出、- prefix 検出等）
  args_generator,  // 元引数から仮想引数列を生成
  sub_opts,        // 委譲先の ExactNode 群
  result_handler,  // 子の Accept を親の Accept に変換
)
```

**ブロッカー**: なし（リファクタリング。現状の install ノードは動作している）

### kawaz/timespec 連携 — 時間系フィルタの組み込み

[kawaz/timespec.mbt](https://github.com/kawaz/timespec.mbt) は CLI 用途に特化した時間指定パーサ。kuu の FilterChain パイプラインと高い親和性がある。

#### 連携方式

**1. FilterChain 組み込みフィルタ**:

```moonbit
// kuu/contrib/timespec/ または kuu core の optional dependency として
let parse_duration_filter : FilterChain[String, @timespec.Duration] =
  Filter::parse(fn(s) { @timespec.parse_duration(s)! })

let parse_timespec_filter : FilterChain[String, @timespec.TimeSpec] =
  Filter::parse(fn(s) { @timespec.parse_timespec(s, default_sign=Minus)! })
```

**2. custom[T] コンビネータでの利用**:

```moonbit
// --since 5m / --since "2026-03-15T12:00:00Z" / --since "3 hours ago"
let since = p.custom(
  name="since",
  pre=Filter::parse(fn(s) { @timespec.parse_timespec(s, default_sign=Minus)! }),
  default=@timespec.TimeSpec::Relative(@timespec.EpochTime(0L), @timespec.Duration(0L)),
)

// --timeout 30s / --timeout 1m30s
let timeout = p.custom(
  name="timeout",
  pre=Filter::parse(fn(s) { @timespec.parse_duration(s)! }),
  default=@timespec.Duration(30_000L),
)
```

**3. TimeRange の2引数パターン（post_hooks 活用）**:

```moonbit
let since = p.string_opt(name="since", default="")
let until = p.string_opt(name="until", default="")
// post_hook で parse_range に渡し、バリデーション + アンカー解決
```

**4. WASM bridge プリセットフィルタ候補**:

JSON スキーマに `"parse_duration"`, `"parse_timespec"` を追加し、多言語からも利用可能にする。

**ブロッカー**: timespec の mooncakes.io パッケージ公開（`moon add kawaz/timespec` を可能にする）

#### 提供形態の検討

| 方式 | メリット | デメリット |
|------|---------|-----------|
| core に組み込み | ゼロコスト利用 | core の依存が増える。core 無改造の原則に反する |
| contrib パッケージ | 依存を選択可能 | ユーザーが追加で `moon add` する手間 |
| example/recipe として提供 | core に影響なし | コピペが必要 |

**推奨**: contrib パッケージ（`kawaz/kuu-timespec`）または kuu ドキュメントの cookbook セクション。core の依存は最小に保つ。

---

## 中期

### ヘルプ生成の拡張

3段階カスタマイズ:
- **Level 0**: 自動生成（現在の実装）
- **Level 1**: 部分フック（セクション単位のカスタマイズ）
- **Level 2**: 全面差し替え（テンプレート方式）

**ブロッカー**: なし

### 補完生成

```moonbit
struct CompletionCandidate {
  value : String
  description : String?       // zsh/fish の説明表示
  group : String?             // zsh のグループ分け
  style : CompletionStyle?    // 警告色等
}
```

3段階カスタマイズ + シェル別出力形式（bash/zsh/fish）。

**ブロッカー**: ヘルプ生成拡張（Level 1 以上）が先にあると設計の見通しが良い

### defaults マルチソースマージ

各デフォルトソースは独立。各ソースごとに新しい Parser で parse し、**明示指定のみ後勝ちマージ**:

```
source1 (config):  --port 3000 --tags a --tags b
source2 (env):     --port 8080
CLI:               --tags c

→ merge: port=8080, tags=[c]
```

**ブロッカー**: 環境変数連携 Phase 2（ValueSource トラッキングと共通基盤）

### ValueSource トラッキング

```moonbit
enum ValueSource {
  Initial         // Opt 定義時の initial 値
  Default(String) // default ソース名
  Environment     // 環境変数から
  CommandLine     // CLI 引数から
}
```

`result.source(opt) -> ValueSource` で値の出所を追跡。`result.is_explicit(opt) -> Bool`。

**ブロッカー**: 環境変数連携 Phase 2

### Visibility — 4段階表示制御

```moonbit
enum Visibility {
  Visible      // デフォルト
  Advanced     // help ✗, 補完 ✓（パワーユーザー向け）
  Deprecated   // help ✓（注記）, 補完 ✗
  Hidden       // help ✗, 補完 ✗（現在は hidden: Bool で部分実装済み）
}
```

`--help-all` で Hidden/Advanced を含む全エントリ表示。auto-env との連動（Hidden/Advanced → auto-env デフォルト Off）。

**ブロッカー**: 補完生成（Visibility の全4段階の意味が確定するため）

### group — 繰り返しオプション群

雛形を clone して各出現の値を保持する:

```moonbit
let upstream_host = opt::str(name="host")
let upstream_timeout = opt::int(name="timeout")
let upstream = opt::group(name="upstream", [upstream_host, upstream_timeout])

let groups = result.get_groups(upstream)  // Array[ParseResult]
```

**ブロッカー**: Opt[T] setter + clone プリミティブ

### mergeable_list（DR-023）

`+/-/...` 修飾子によるベース相対変更:

```
--fields "name,age"      → [name, age]（上書き）
--fields "+extra"        → base + [extra]（追加）
--fields "-name"         → base - [name]（除外）
```

**ブロッカー**: なし（FilterChain で実装可能）

### file コンビネータ

`string_opt` / `int_opt` と並ぶファイルパス特化コンビネータ。`implicit_value` との組み合わせで3値パターン:

- 未指定 → None
- フラグのみ（`--config`）→ デフォルトパス（`~/.config/xxx/xxx.toml`）
- 値指定（`--config path`）→ 指定パス

clap で `num_args=0..=1` + サブコマンド衝突が起きる問題を、kuu は ExactNode 走査 + make_or_node で構造的に回避。

**ブロッカー**: なし（既存の implicit_value + custom[T] で PoC 可能）

---

## 多言語展開

### 調査: 多言語展開する CLI パーサの先行事例

**調査目的**: 「単一コアから複数言語の CLI パーサを提供する」アプローチは前例があるのか。あるならどのような方式か。ないなら kuu のアプローチの新規性を明確にする。

**調査対象**:

| カテゴリ | 対象 | 調査ポイント |
|---------|------|-------------|
| CLI パーサ | clap, cobra, click, argparse, oclif, yargs | 単一言語に閉じているか。多言語展開の議論はあるか |
| マルチ言語ツール基盤 | tree-sitter, protobuf/gRPC, Cap'n Proto | C コア + バインディング方式の実態。バインディング生成の手法 |
| スキーマ駆動コード生成 | OpenAPI Generator, GraphQL codegen, Buf | スキーマから多言語クライアント生成。CLI パーサに応用可能か |
| WASM ベースマルチ言語 | Extism, waPC, Spin | WASM を言語間ブリッジとして使うパターン。Component Model の活用状況 |

**仮説**: CLI パーサで多言語展開しているものはおそらくない。理由は:
1. CLI パーサは各言語のイディオムに強く依存する（derive マクロ、dataclass、struct tag 等）
2. パース自体の計算量は小さく、FFI オーバーヘッドを正当化しにくい
3. 各言語に成熟したネイティブ実装がある

kuu のアプローチが成立する理由は:
1. core が純粋関数ベースで言語非依存
2. DX 層を言語別に提供するため、各言語のイディオムを犠牲にしない
3. Opt 定義が純粋データで JSON にシリアライズ可能（DR-029, DR-030）
4. WASM bridge で「パースロジックの共有」と「DX の言語別最適化」を両立

**ブロッカー**: なし（調査タスク）

### 調査: FFI 連携形態のベストプラクティス

**調査目的**: kuu core (MoonBit/WASM-GC) を各言語から呼ぶ最適な方法を確立する。

**調査項目**:

1. **WASM-GC ランタイムサポート状況**:
   - V8 (Node.js/Deno/Bun): サポート済み（kuu の現在の方式）
   - wasmtime (Rust): WASM-GC サポートは実験段階。進捗追跡が必要
   - wazero (Go): WASM-GC 未サポート（DR-033）。代替アプローチが必要
   - WasmKit (Swift): 同様に未サポート
   - Python (wasmer/wasmtime-py): 状況確認

2. **WASM Component Model / WASI**:
   - wit-bindgen によるインターフェース生成
   - Component Model が WASM-GC と組み合わせて使えるか
   - WASI Preview 2 の CLI 関連機能

3. **非 V8 言語のブリッジパターン**:
   - 現在の方式: Node.js サブプロセス + JSON stdin/stdout（DR-033）
   - 代替1: WASM-GC → 通常 WASM へのコンパイル（可能か？MoonBit の制約は？）
   - 代替2: MoonBit → C/native バックエンドの活用
   - 代替3: 各言語で core を再実装（テストケース共有で品質保証）

4. **先行事例調査**:
   - tree-sitter: C コア + 各言語バインディング生成。最も成功したパターン
   - Extism: WASM プラグインシステム。多言語 SDK を提供。ホスト言語からの呼び出し方式
   - waPC: WASM 上の RPC。ホスト-ゲスト間のコールバック方式

**ブロッカー**: なし（調査タスク）。結果は DR に記録

### 各言語 DX 層の設計・PoC

#### TypeScript DX

```typescript
// 理想の DX イメージ
const parser = kuu.parser({
  verbose: kuu.count({ shorts: 'v', global: true }),
  port: kuu.int({ default: 8080 }),
  host: kuu.string({ default: 'localhost' }),
  serve: kuu.sub({
    dir: kuu.positional(),
  }),
} as const);

const result = parser.parse(process.argv.slice(2));
result.verbose;  // number（型推論で解決）
result.serve?.dir;  // string | undefined
```

TypeScript の union/infer/conditional types で型レベル解決。WASM bridge 経由で kuu core を呼ぶか、pure TS 実装にするかは FFI 調査結果次第。

**ブロッカー**: FFI 調査の完了、WASM bridge の全機能カバー（DR-035）

#### Go DX

```go
// 理想の DX イメージ
type Config struct {
    Verbose int    `kuu:"name=verbose,shorts=v,global"`
    Port    int    `kuu:"name=port,default=8080"`
    Host    string `kuu:"name=host,default=localhost"`
}

func main() {
    var cfg Config
    result, err := kuu.Parse(os.Args[1:], &cfg)
    fmt.Println(cfg.Port)       // 8080
}
```

struct tag + reflect ベース、または codegen（`go generate` で struct から kuu JSON schema を生成）。

**ブロッカー**: FFI 調査の完了。wazero の WASM-GC サポート状況次第で Node.js サブプロセス方式 or pure Go 実装を選択

#### Rust DX

```rust
// 理想の DX イメージ
#[derive(kuu::Parser)]
struct Config {
    #[kuu(shorts = "v", global)]
    verbose: u32,
    #[kuu(default = 8080)]
    port: i32,
}
```

derive マクロで Parser trait を自動実装。core を WASM で呼ぶか FFI で呼ぶかは wasmtime の WASM-GC サポート次第。

**ブロッカー**: FFI 調査。wasmtime WASM-GC 対応のタイムライン

#### Python DX

```python
# 理想の DX イメージ
@kuu.parser
class Config:
    verbose: Annotated[int, kuu.Count(shorts="v", global=True)] = 0
    port: Annotated[int, kuu.Int(default=8080)] = 8080
    host: str = "localhost"

result = Config.parse(sys.argv[1:])
```

dataclass / TypedDict + Annotated type hints。WASM bridge は Node.js サブプロセス経由。

**ブロッカー**: FFI 調査、Python SDK (KuuCore) の設計

#### Swift DX

```swift
// 理想の DX イメージ
struct Config: KuuParsable {
    @KuuCount(shorts: "v", global: true)
    var verbose: Int = 0
    @KuuInt(default: 8080)
    var port: Int = 8080
}

let config = try Config.parse()
```

property wrapper / Codable。WasmKit の WASM-GC 対応状況次第。

**ブロッカー**: FFI 調査、Swift SDK (KuuCore) の設計

### KuuCore — 言語別 SDK 共通基盤（DR-036）

```
Core (MoonBit)   ← 純粋パースエンジン
  ↑
WASM bridge      ← JSON schema → core → JSON result
  ↑
KuuCore (各言語) ← JSON 力学を隠蔽。コールバック仲介。バックエンド抽象化
  ↑
DX API (各言語)  ← 言語イディオムに沿った型安全 API
```

KuuCore の責務:
1. JSON schema の構築（DX 層からの宣言を受けて JSON を組み立て）
2. WASM bridge / サブプロセス / native FFI のバックエンド抽象化
3. custom[T] や post フィルタのコールバック仲介
4. 型安全な結果アクセスの提供

**ブロッカー**: FFI 調査、WASM bridge の安定化

### WASM bridge 全機能カバー（DR-035）

現在の WASM bridge が対応していない機能を追加:
- Variation（Toggle/True/False/Reset/Unset）
- alias / deprecated
- exclusive / required / at_least_one
- implicit_value
- dashdash / append_dashdash
- serial
- プリセット post フィルタ（trim, non_empty, in_range, one_of, parse_duration, parse_timespec 等）

**ブロッカー**: なし（個別に追加可能）

### 調査: core 再実装 vs WASM 共有のトレードオフ

各言語で core を再実装する選択肢も検討する:

| 方式 | メリット | デメリット |
|------|---------|-----------|
| WASM 共有 | パースロジックの一貫性保証。バグ修正が全言語に波及 | WASM-GC の普及待ち。FFI オーバーヘッド。ランタイム依存 |
| core 再実装 | 各言語にネイティブ。ゼロ依存。最適なパフォーマンス | 実装の同期コスト。テストケース共有で品質保証が必要 |
| ハイブリッド | 言語ごとに最適な方式を選択 | 維持コストが最大 |

テストケース共有（入力 → 期待出力の JSON テストスイート）があれば、再実装でも品質保証が可能。kuu のテストは Phase 1-3 から「テストケース = 要件」の思想で蓄積されている。

**ブロッカー**: FFI 調査の結論

---

## エコシステム・インフラ

### パッケージ公開

#### mooncakes.io（MoonBit パッケージレジストリ）

kuu core + dx を `kawaz/kuu` として公開。

**やること**:
- `moon.mod.json` のメタデータ整備（description, keywords, license, repository）
- mooncakes.io のアカウント・トークン設定
- `moon publish` の CI 自動化
- バージョニング方針の確定（semver）
- CHANGELOG の開始

**ブロッカー**: API の安定化（特に Opt[T] setter 追加が breaking change になる可能性）

#### npm（TypeScript/JavaScript）

WASM bridge を npm パッケージとして公開。`@kawaz/kuu` または `kuu`。

**やること**:
- npm パッケージ構造の設計
- TypeScript 型定義の生成
- ESM / CJS 対応
- WASM バイナリの同梱方式（inline base64 vs 別ファイル）

**ブロッカー**: WASM bridge の安定化、TypeScript DX の設計

#### 他言語パッケージ

| レジストリ | パッケージ名 | ブロッカー |
|-----------|------------|-----------|
| PyPI | `kuu` | Python DX 設計、KuuCore Python 実装 |
| crates.io | `kuu` | Rust DX 設計、wasmtime WASM-GC 対応 |
| Go modules | `github.com/kawaz/kuu-go` | Go DX 設計、wazero WASM-GC 対応 or pure Go |
| SwiftPM | `kuu-swift` | Swift DX 設計、WasmKit 対応 |

### CI/CD

現状: ローカル開発のみ。GitHub Actions なし。

**やること**:
- GitHub Actions ワークフロー
  - `moon check --deny-warn` + `moon test`（全ターゲット: wasm-gc, wasm, js）
  - バイナリサイズ計測（`just size` 相当）+ PR コメントでサイズ差分表示
  - `moon fmt` チェック
- リリースワークフロー
  - タグプッシュ → mooncakes.io publish + npm publish
  - CHANGELOG 自動生成
- WASM bridge テスト
  - Node.js テスト（`src/wasm/test.mjs`）

**ブロッカー**: なし

### Web サイト

**目的**: kuu の思想・能力を正確に伝えるドキュメントサイト + ランディングページ

**調査: ドキュメントサイト基盤**:

| ツール | 特徴 | 適性 |
|-------|------|------|
| VitePress | Vue ベース。軽量で高速。中国語圏で人気 | MoonBit コミュニティとの親和性（MoonBit は中国発） |
| Starlight (Astro) | コンテンツ特化。多言語 i18n 標準サポート | 日英の多言語ドキュメントに最適 |
| Docusaurus | React ベース。Meta 製。大規模ドキュメント向け | 機能豊富だがやや重い |
| mdBook | Rust 製。Rust コミュニティで定番 | シンプルだがカスタマイズ性が低い |

**コンテンツ構成**:

```
/                     # ランディングページ（kuu の核心を30秒で伝える）
/guide/               # Getting Started
/guide/quick-start    # Quick Start
/guide/concepts       # コアコンセプト（ExactNode, 4層, 投機実行）
/guide/combinators    # コンビネータリファレンス
/guide/subcommands    # サブコマンド
/guide/filters        # FilterChain
/guide/constraints    # exclusive, required 等
/cookbook/             # レシピ集
/cookbook/timespec     # --since/--until パターン
/cookbook/docker       # Docker CLI クローン
/cookbook/kubectl      # kubectl クローン
/reference/           # API リファレンス（自動生成）
/design/              # 設計ドキュメント（DESIGN-v2.md 等）
/multilang/           # 多言語ガイド
/multilang/typescript # TypeScript での利用
/multilang/go         # Go での利用
/blog/                # 設計思想の解説記事
```

**参考にすべきドキュメントサイト**:

| ライブラリ | URL | 良い点 |
|-----------|-----|--------|
| clap (Rust) | docs.rs/clap | derive マクロの例が豊富。cookbook が実用的 |
| cobra (Go) | cobra.dev | Getting Started が明快 |
| click (Python) | click.palletsprojects.com | 段階的な学習パス |
| oclif (TS) | oclif.io | CLI フレームワークとしてのビジョンが明確 |

**ブロッカー**: コンテンツの準備（DESIGN-v2.md ベースで skeleton は作れる）

### ランディングページ

**目的**: 「kuu は何が違うのか」を30秒で伝える

**キーメッセージ**:
1. 投機実行 + 最長一致 — CLI パーサの新しいパースモデル
2. 全 OptKind を reducer で統一 — `-abc` も `--color=always` も同じアルゴリズム
3. 多言語基盤 — 1つの core から全言語へ
4. FilterChain — 型安全な変換パイプライン

**ライブデモ**:
- ブラウザ上で kuu の WASM を動かし、引数文字列を入力するとパース結果がリアルタイム表示される
- `-abc` の分解過程や最長一致の候補選択を可視化

**ブロッカー**: WASM のブラウザ動作確認（WASM-GC は主要ブラウザでサポート済み）

### Playground

ブラウザ上で kuu のコンビネータを組み合わせてパーサを構築し、引数文字列でテストできるインタラクティブ環境。

**構成**:
- MoonBit の WASM-GC 出力をブラウザで実行
- Monaco Editor でコンビネータ定義を編集
- パース結果 + ヘルプ出力 + エラーメッセージをリアルタイム表示
- 投機実行の過程（各 ExactNode の Accept/Reject/Error）を可視化

**ブロッカー**: Web サイト基盤、WASM のブラウザ実行環境

---

## リファレンス品質の examples

現状: examples/ トップレベルは空（全て archives/ に移動済み）。

### 新規 example の方針

API が安定したら、リファレンス品質の example を作成する:

| example | モデル | 検証対象 |
|---------|--------|---------|
| docker | Docker CLI | deep nesting, exclusive, required, global |
| kubectl | kubectl | `-f` のサブコマンド別バインド, dashdash, choices |
| git | git | 複雑なサブコマンド構造, positional, rest |
| cargo | cargo | ワークスペース系, --manifest-path |
| curl | curl | 大量の単発オプション, `--data @file` |

**ブロッカー**: API 安定化（特に Opt[T] setter 追加後）

### 多言語 example

同一 CLI 仕様を複数言語で実装し、DX の比較素材にする:

```
examples/
  {date}-{name}-moonbit/   # MoonBit 版
  {date}-{name}-typescript/ # TypeScript 版
  {date}-{name}-go/         # Go 版
```

**ブロッカー**: 各言語 DX の最低限の動作

---

## 長期

### @file 展開

引数前処理フック。gcc/javac 方式。PreProcess フェーズ（パースライフサイクルの最初）で展開。

**ブロッカー**: パースライフサイクルの PreProcess フェーズの設計

### 中間 rest 対応

`mv file... dir` パターン。rest の後に固定パラメータが来るケース。

**ブロッカー**: positional 消費アルゴリズムの再設計が必要

### NativeBackend via FFI

WASM bridge に加えて、各言語の FFI を使った native backend。KuuCore 層のバックエンド抽象化により、WASM と native を透過的に切り替え可能にする構想。

MoonBit の native バックエンド（C 出力）が安定すれば、各言語から C FFI で直接呼べる。tree-sitter と同じパターン。

**ブロッカー**: MoonBit native バックエンドの成熟

### 構造化出力

```moonbit
result.to_entries()  // -> Array[(String, String, ValueSource)]
                     //    (name, value_str, source)
```

全パース結果をフラット列挙。JSON 等のシリアライズはユーザー側。

**ブロッカー**: ValueSource トラッキング

### TUI 連携

kuu のパース結果を TUI フレームワーク（bubbletea, ratatui 等）のインタラクティブなフォーム入力に変換する。OptMeta からフォームフィールドを自動生成。

**ブロッカー**: 多言語 DX（Go/Rust が先行する必要あり）

### 設定ファイル読み込み

TOML/YAML/JSON の設定ファイルから defaults を読み込む。viper (Go) のパターン:

```
CLI > 環境変数 > 設定ファイル > initial
```

設定ファイルのパスは `--config` オプション（file コンビネータ）で指定。

**ブロッカー**: defaults マルチソースマージ、file コンビネータ

### MoonBit derive マクロ対応

MoonBit に derive マクロが追加された場合、DX 層が劇的に簡素化される:

```moonbit
#[derive(KuuParser)]
struct Config {
  #[kuu(shorts="v", global)]
  verbose : Int
  #[kuu(default=8080)]
  port : Int
}
```

現在の Parseable trait + FieldRegistry + apply_fn 方式から、derive マクロベースに移行可能。

**ブロッカー**: MoonBit 言語機能の追加

---

## パースライフサイクルの将来形

```
引数入力 → [PreProcess] → [Reduce] → [Validate] → [Finalize] → [Output]
```

| フェーズ | 内容 | 現在の実装 | ブロッカー |
|---------|------|-----------|-----------|
| PreProcess | @file 展開等 | 未実装 | @file 設計 |
| Reduce | 消費ループ | 実装済み（parse_raw） | — |
| Validate | exclusive, requires 等 | post_hooks で実装済み | — |
| Finalize | デフォルト適用・環境変数連携 | post_hooks で実装可能 | 環境変数 Phase 2 |
| Output | ヘルプ・補完・エラー表示 | 基本実装済み | ヘルプ拡張・補完生成 |

post_hooks が将来の Validate/Finalize フェーズの実質基盤として機能する。

---

## 調査タスク一覧

ロードマップの各項目を進める前に必要な調査をまとめる:

| 調査 | 目的 | 成果物 | ブロッカー |
|------|------|--------|-----------|
| 多言語 CLI パーサの先行事例 | kuu アプローチの新規性確認と差別化ポイント明確化 | DR + research ドキュメント | なし |
| FFI 連携ベストプラクティス | 各言語から kuu core を呼ぶ最適な方法の確立 | DR + 各言語 PoC | なし |
| WASM-GC ランタイムサポート状況 | 非 V8 言語のブリッジ方式の決定 | DR（定期更新） | なし |
| WASM Component Model 調査 | wit-bindgen による多言語バインディング自動生成の可能性 | DR | なし |
| core 再実装 vs WASM 共有 | 各言語での最適なアプローチ決定 | DR | FFI 調査 |
| ドキュメントサイト基盤比較 | VitePress/Starlight/Docusaurus の選定 | 選定結果 + skeleton サイト | なし |
| tree-sitter のバインディング生成方式 | 多言語バインディングの成功パターン学習 | 調査メモ | なし |
| MoonBit native バックエンド調査 | C FFI 出力の実用性評価 | PoC | なし |
| 他言語展開を行っている OSS の組織運営 | 多言語メンテナンスの持続可能性 | 調査メモ | なし |
