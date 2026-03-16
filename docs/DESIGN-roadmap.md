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

---

## 中期

### ヘルプ生成の拡張

3段階カスタマイズ:
- **Level 0**: 自動生成（現在の実装）
- **Level 1**: 部分フック（セクション単位のカスタマイズ）
- **Level 2**: 全面差し替え（テンプレート方式）

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

### defaults マルチソースマージ

各デフォルトソースは独立。各ソースごとに新しい Parser で parse し、**明示指定のみ後勝ちマージ**:

```
source1 (config):  --port 3000 --tags a --tags b
source2 (env):     --port 8080
CLI:               --tags c

→ merge: port=8080, tags=[c]
```

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

### group — 繰り返しオプション群

雛形を clone して各出現の値を保持する（clone プリミティブ実装後）:

```moonbit
let upstream_host = opt::str(name="host")
let upstream_timeout = opt::int(name="timeout")
let upstream = opt::group(name="upstream", [upstream_host, upstream_timeout])

let groups = result.get_groups(upstream)  // Array[ParseResult]
```

### mergeable_list（DR-023）

`+/-/...` 修飾子によるベース相対変更:

```
--fields "name,age"      → [name, age]（上書き）
--fields "+extra"        → base + [extra]（追加）
--fields "-name"         → base - [name]（除外）
```

---

## 長期

### @file 展開

引数前処理フック。gcc/javac 方式。PreProcess フェーズ（パースライフサイクルの最初）で展開。

### 中間 rest 対応

`mv file... dir` パターン。rest の後に固定パラメータが来るケース。

### 多言語 DX レイヤー（DR-027, DR-036）

KuuCore（各言語）+ DX API（言語イディオム）:

| 言語 | DX 方式 |
|------|---------|
| MoonBit | Parseable trait + apply_fn（実装済み、derive マクロ追加で進化予定） |
| Go | codegen で struct + 純粋関数を生成 |
| TypeScript | union/infer/conditional types で型レベル解決 |
| Rust | derive マクロ |
| Swift | property wrapper / Codable |
| Python | dataclass / TypedDict |

WASM-GC → V8 限定の制約により、非V8言語は Node.js サブプロセス経由。将来的に WASM-GC サポートが広がれば native bridge も可能。

### NativeBackend via FFI

WASM bridge に加えて、各言語の FFI を使った native backend。KuuCore 層のバックエンド抽象化により、WASM と native を透過的に切り替え可能にする構想。

### 構造化出力

```moonbit
result.to_entries()  // -> Array[(String, String, ValueSource)]
                     //    (name, value_str, source)
```

全パース結果をフラット列挙。JSON 等のシリアライズはユーザー側。

---

## パースライフサイクルの将来形

```
引数入力 → [PreProcess] → [Reduce] → [Validate] → [Finalize] → [Output]
```

| フェーズ | 内容 | 現在の実装 |
|---------|------|-----------|
| PreProcess | @file 展開等 | 未実装 |
| Reduce | 消費ループ | 実装済み（parse_raw） |
| Validate | exclusive, requires 等 | post_hooks で実装済み |
| Finalize | デフォルト適用・環境変数連携 | post_hooks で実装可能 |
| Output | ヘルプ・補完・エラー表示 | 基本実装済み |

post_hooks が将来の Validate/Finalize フェーズの実質基盤として機能する。
