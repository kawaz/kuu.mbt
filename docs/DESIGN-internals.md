# kuu 詳細実装仕様

[DESIGN-v2.md](DESIGN-v2.md) のアーキテクチャ概要を前提とした、実装レベルの詳細仕様。

---

## Parser struct

```moonbit
pub(all) struct Parser {
  next_id : () -> Int                    // ID 採番クロージャ（子パーサと共有）
  nodes : Array[ExactNode]              // ExactNode フラットリスト（名前付きオプション）
  global_nodes : Array[ExactNode]       // global=true のノード（子パーサに伝播）
  positionals : Array[PositionalEntry]  // 位置パラメータエントリ
  current_positional : Ref[Int]          // 次に消費する positional のインデックス
  parsed : Ref[Bool]                     // パース済みフラグ（opt.get() で参照）
  children : Map[String, ParseResult]    // サブコマンド名 → 子 ParseResult
  metas : Array[OptMeta]                // ヘルプ生成用メタ情報
  description : Ref[String]             // パーサの説明文（ヘルプ表示用）
  post_hooks : Array[() -> Unit raise ParseError]  // パース後フック
  registered_names : Map[String, Bool]   // 重複検出用
  duplicate_errors : Array[String]       // 遅延エラーメッセージ
  force_unclaimed : Array[String]       // 強制 unclaimed 引数（短結合の未消費残りなど）
  node_templates : Map[Int, NodeTemplate] // alias/clone 用ノード生成ファクトリ
  eq_fallback_nodes : Array[ExactNode]  // eq_split 用フォールバックノード（implicit_value 付きの --opt=--value 対応）
  deprecated_usages : Array[(String, String)]  // deprecated 使用記録（name, msg）
}
```

子パーサは `next_id` を親と共有し、ID 空間を統一する。`global_nodes` は子パーサの構築時にコピーされるが、遅延同期により cmd 定義後に追加された global も子パーサで使える。

---

## ExactNode の種類

各コンビネータが生成する ExactNode の一覧:

| 生成関数 | consumed | 用途 | 詳細 |
|---------|----------|------|------|
| `make_flag_node` | 1 | フラグ | 名前のみマッチ。cell.val を反転/設定 |
| `make_value_node` | 2 | 値オプション | 名前 + 次の引数を消費 |
| `make_choice_value_node` | 2 | choices の候補 | 名前 + 値一致で Accept。値不一致で Reject |
| `make_implicit_flag_node` | 1 | implicit_value | 名前のみで暗黙値を適用 |
| `make_soft_value_node` | 2 or Reject | implicit 共存時の値ノード | 値が `--` prefix なら Reject（フォールバック許可） |
| `make_soft_custom_value_node` | 2 or Reject | implicit 共存時の custom | soft_value の custom[T] 版 |
| `make_custom_choice_value_node` | 2 or Reject | choices + implicit | choices + soft_value の合成 |
| `make_or_node` | 最大 | コンポジット | 子ノードの最長一致。ambiguous 検出 |
| `make_reduced_value_node` | 2 | reducer 経由 | make_reducer で生成した reducer を呼ぶ |

### make_or_node の動作

```
make_or_node(children):
  for each child in children:
    result = child.try_reduce(args, pos)
    if Accept: 候補に追加（consumed, commit を記録）
    if Error: 即 return Error
    if Reject: skip
  → 候補の consumed 最大を選択
  → 最大が複数: Error(ambiguous)
  → 最大が1つ: Accept(consumed, commit)
  → 候補なし: Reject
```

---

## PositionalEntry

```moonbit
pub(all) struct PositionalEntry {
  handler : (Array[String], Int) -> TryResult  // 位置パラメータハンドラ
  is_rest : Bool                                // true なら繰り返し消費
  greedy : Bool                                 // true なら OC Phase で消費
}
```

- `is_rest=false`: 1回消費したら `current_positional` を進める
- `is_rest=true`: 同じハンドラを繰り返し使用。stop_before で Reject → 次へ
- `greedy=true`: OC Phase で ExactNode と同列に消費試行。デフォルト false

---

## NodeTemplate

```moonbit
pub(all) struct NodeTemplate {
  make_node : (String) -> ExactNode   // 新しい名前で ExactNode を生成するファクトリ
  is_global : Bool                    // global ノードかどうか
  make_eq_fallback : ((String) -> ExactNode)?  // eq_split フォールバック用（implicit_value 付きのみ）
}
```

register_option / cmd が `node_templates[id]` に登録。alias / clone コンビネータがファクトリを使って新しい ExactNode を生成する。チェーン alias の committed 伝搬は Accessor.set_commit 経由で root まで辿る（NodeTemplate にターゲット参照を持たない）。

---

## ReduceCtx と ReduceAction

```moonbit
pub(all) struct ReduceCtx[T] {
  current : T              // 現在の累積値
  action : ReduceAction    // 今回のアクション
}

pub(all) enum ReduceAction {
  Value(String?)           // 正方向: Flag/Count は None、Single/Append は Some(value)
}
```

reducer のシグネチャ: `(ReduceCtx[T]) -> T?!ParseError`

make_reducer が FilterChain + Accumulator から自動生成:

```moonbit
fn make_reducer[T, U](
  pre   : FilterChain[String, U],
  accum : Accumulator[T, U],
) -> (ReduceCtx[T]) -> T?!ParseError {
  fn(ctx) {
    match ctx.action {
      Value(Some(s)) => Some(accum(ctx.current, pre.run(s)!))
      _ => None
    }
  }
}
```

---

## install ノードの詳細アルゴリズム

### install_eq_split_node

`--name=value` を分解し、既存の value ノードに委譲する:

1. `needs_value=true` かつ name が `--` で始まるノードを収集
2. `=` の位置で name/value を分割し、`[name, value]` で各ノードの try_reduce を呼ぶ
3. **consumed≥2 gate**: composite ノードが implicit (consumed=1) を返した場合は無視（値が消費されていないため）
4. 失敗した場合、`eq_fallback_nodes` でも試行（implicit_value 付きオプションの `--opt=--value` パターン対応）
5. 最長一致で勝者を選び、`Accept(consumed=1)` で返す（元の `--name=value` は1トークン）

### install_short_combine_node

`-abc` 等の結合ショートオプションを分解する:

1. `-X` 形式（長さ2、`-` prefix、`--` 非prefix）のノードを収集
2. 結合文字列を左から1文字ずつ走査
3. 各文字に対して:
   - **remaining がある場合**: まず value trial（needs_value=true のノードのみ、consumed≥2）→ 成功なら remaining 全体を値として消費。失敗なら flag trial
   - **remaining がない場合**: flag trial → 失敗なら外引数（args[pos+1]）で value trial
4. 全文字が消費できたら `Accept(consumed=total)`
5. 1文字でも失敗したら Reject

**型情報の活用**: `needs_value` フラグにより、`-vA1B1` のような「フラグ + 値」の混在パターンも正確に分解できる。`-v` がフラグ（needs_value=false）、`-A` が値オプション（needs_value=true）なら、`A` の後の `1` を `-A` の値として消費し、`B1` は別の `-B 1` として処理。

### install_separator_node

`--` を ExactNode 化。`Parser::new(dashdash=true)` の初期化時に自動登録（デフォルト ON）。`--` を検出したら残りの args を `force_unclaimed` に追加し、P Phase で positional に転送する。

---

## パースライフサイクル

```
引数入力
  → [parsed ガード] — 同一 Parser での2回呼び出しを禁止（DR-026）
  → [validate_no_duplicate_names] — 重複名を検出して ParseError
  → [install_eq_split_node] — --name=value 対応
  → [install_short_combine_node] — -abc 対応
  → [OC Phase] — ExactNode 走査 + 最長一致 + greedy positional
  → [P Phase] — force_unclaimed + unclaimed を non-greedy positional で消費
  → [post_hooks] — 値変換・遅延バリデーション（exclusive, required 等）
  → [parsed = true]
```

post_hooks は `Parser.post_hooks: Array[() -> Unit raise ParseError]` として実装されており、string_opt の `post` パラメータや exclusive/required の制約チェックなど、パース後のクロスカッティングな処理に使用。

---

## OptMeta — ヘルプ生成用メタ情報

```moonbit
pub(all) struct OptMeta {
  kind : OptKind           // Flag | ValueOpt | Command | Positional | Rest
  name : String            // オプション名（"--" prefix なし）
  help : String            // ヘルプテキスト
  value_name : String      // 値のプレースホルダ（"PORT" 等）
  default_display : String // デフォルト値の表示文字列
  env_name : String        // 環境変数名（Phase 1: ヘルプ表示のみ）
  global : Bool            // true なら "Global Options" セクション
  shorts : Array[Char]     // ショートオプション
  aliases : Array[String]  // エイリアス名のリスト
  variation_names : Array[String]  // Variation 名のリスト
  hidden : Bool            // true ならヘルプに表示しない
}
```

**原則: ヘルプが従、コアが主。** choices は OptMeta に持たない。custom() 内で help 文字列に `[possible values: ...]` を付加する方式。OptMeta はヘルプ表示専用であり、パースロジックに影響する情報はコアに持たせない。

### ヘルプ生成

`generate_help()` は以下のセクションを出力:
1. Description
2. Usage 行（`[OPTIONS] [COMMAND] [ARGUMENTS]`）
3. Commands テーブル
4. Arguments セクション
5. Options / Global Options セクション

`inject_help_node()` が `--help` / `-h` を ExactNode として自動登録。ユーザーが `name="help"` や `shorts="h"` を登録済みの場合、衝突する built-in ノードをスキップ。

---

## register_option — 共通登録パイプライン（DR-025）

全コンビネータが使う統一的な登録パイプライン:

```
register_option[T](name, shorts, aliases, variations, global, hidden, ...):
  1. wrap_node_with_set — committed 追跡のラッパーを付与
  2. expand_and_register — 以下を展開:
     a. "--{name}" のメインノードを登録
     b. shorts 文字列の各文字を "-{c}" として登録
     c. aliases の各名前を "--{alias}" として登録
     d. variations の各パターンを "--{prefix}-{name}" として登録
     e. 名前重複を registered_names に記録（遅延検証用）
  3. OptMeta を metas に追加
  4. NodeTemplate を node_templates に登録（alias/clone 用）
  5. Opt[T] を生成して返却
```

custom[T : Show] がこのパイプラインの汎用入口。string_opt, int_opt は custom のシュガー。flag, count は consumed 値が異なるため register_option を直接使用。

---

## DX 層の実装構造（DR-042）

### Parseable trait

```moonbit
pub(open) trait Parseable {
  register(Self, FieldRegistry) -> Unit
}
```

### FieldRegistry

core の Parser をラップし、applier クロージャを蓄積:

```moonbit
struct FieldRegistry {
  parser : @core.Parser
  appliers : Array[() -> Unit]  // parse 成功後に実行
}
```

各メソッド（flag, string, int, count, append_*, custom, positional, rest, sub）は:
1. core の対応コンビネータを呼び出して `Opt[T]` を取得
2. `apply_fn` クロージャを appliers に蓄積: `fn() { apply_fn(opt.get().unwrap()) }`
3. `_ref` バリアントは `OptRef` を返し、constraints 登録に使用

### parse_into

```moonbit
pub fn parse_into[T : Parseable](args : Array[String], target : T) -> ...
  1. Parser::new() + FieldRegistry 構築
  2. target.register(registry) — オプション登録
  3. parser.parse(args) — パース実行
  4. appliers を順に実行 — 値注入（parse 失敗時はスキップ）
```

---

## WASM bridge の実装構造

### エントリポイント

`kuu_parse(input_json: String) -> String` — JSON in, JSON out。

### 入力スキーマ (version: 1)

```json
{
  "version": 1,
  "description": "My CLI",
  "opts": [
    {"kind": "flag", "name": "verbose", "shorts": "v", "global": true},
    {"kind": "string", "name": "host", "default": "localhost", "choices": ["a", "b"]},
    {"kind": "int", "name": "port", "default": 8080, "implicit_value": 3000},
    {"kind": "command", "name": "serve", "opts": [...], "require_cmd": false}
  ],
  "args": ["--verbose", "--host", "example.com"],
  "require_cmd": true,
  "exclusive": [["json", "csv"]],
  "required": ["output"]
}
```

### 出力スキーマ

成功: `{"ok": true, "values": {...}, "command": {"name": "...", "values": {...}}}`
ヘルプ: `{"ok": false, "help": true, "text": "..."}`
エラー: `{"ok": false, "error": "..."}`

### build_parser

JSON スキーマを再帰的に Parser に変換。OptEntry（name + extraction クロージャ）を蓄積し、extract_values で結果を JSON に変換。

対応 kind: flag, string, int, count, append_string, append_int, positional, rest, dashdash, append_dashdash, serial, command

対応フィルタ（JSON 表現）: "trim", "non_empty", {"in_range": [min, max]}

---

## テスト方針

TDD（t_wada 流）を実践:

1. 要件からテストを書く（RED）
2. 実装する（GREEN）
3. リファクタ
4. `moon test -u` でスナップショットテスト活用
5. `moon test` で全テスト通過確認

テスト配置:
- `src/core/parse_wbtest.mbt` — パーサテスト
- `src/core/filter_wbtest.mbt` — フィルタテスト
- `src/dx/dx_wbtest.mbt` — DX 層テスト
- `src/wasm/test.mjs` — WASM bridge テスト（Node.js）
