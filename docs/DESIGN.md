# kuu 設計書

## kuu とは何か

投機実行と最適解釈で曖昧さを構造的に解決する CLI パーサエンジン。MoonBit 製。

各コンビネータが消費可能な範囲を投機的に試し、最も妥当な解釈を採用する。全 OptKind を `initial + ReduceCtx reducer` で統一し、消費ループは型を知らず、名前解決も持たない。全ての複雑さはコンビネータ層で事前展開される。

### 他の CLI パーサとの比較

| 観点 | 一般的パーサ（clap, cobra 等） | kuu |
|------|------|-----|
| パースモデル | 名前を引いてから値を処理（2ステップ） | 各ノードが自己判定（投機実行 + 最長一致） |
| `-abc` 結合分解 | 専用の分解ロジック | install ノードで ExactNode に変換。メインループに特殊分岐なし |
| `--color` / `--color=always` 共存 | num_args 等の個別対応 | make_or_node の最長一致で自然に解決 |
| choices バリデーション | パース後の検証ステップ | ExactNode 内で Accept/Reject として即判定 |
| 曖昧さ | 定義順で優先度が決まる or 検出しない | 同率候補を検出して ambiguous エラー |

### PEG（ordered choice）との違い

PEG は最初にマッチした候補を採用する。kuu は全候補を投機実行して最適な解釈を選ぶ。順序非依存であり、曖昧さ（同率候補）も検出できる。

---

## 設計原則

1. **全 OptKind を initial + reducer で統一** — Flag, Count, Single, Append, choices, implicit_value の全てが同じ構造
2. **ExactNode のフラットリストを投機実行 + 最長一致で走査** — 消費ループは型を知らず、名前解決も持たない。複雑さはコンビネータ層に押し出す
3. **コア内部4層で複雑さを分離** — Core → Pattern → Convention → Sugar。各層は ExactNode の生成と登録という単一操作に統一
4. **Opt[T] は薄い参照型** — id + name + accessor + parsed。値の格納は ValCell + Accessor のクロージャ束に隠蔽
5. **ヘルプが従、コアが主** — 表示用メタデータ（OptMeta）のためにコア設計を歪めない
6. **既存パーツの組み合わせで考えよ** — 新フィールドや型を追加する前に、既存の型・クロージャの組み合わせで解決できないか検討
7. **try_reduce は TryResult を返す** — Accept/Reject/Error の3値。名前解決前後でRejectとErrorの意味が変わる
8. **FilterChain で String→T の前処理を型安全に合成** — map/validate/parse + then で Kleisli 合成。フィルタは純粋関数
9. **スペース形式は維持する** — `--name value` を基本とし、`--name=value` は install ノードで透過的に対応
10. **dx → core 一方向依存** — dx が core に要求して core の設計を歪めることはしない。core は dx を知らない

---

## コンビネータと API

### Sugar 層 — ユーザー向けコンビネータ

型特化のコンビネータ。`name~` は `--name` や `<NAME>` の生成に直結するため必須パラメータ（デフォルトなし）:

- `flag()`, `string()`, `int()`, `float()`, `boolean()`, `count()` — 基本型
- `file()` — ファイルパス特化。`default` + `default_path` + `implicit_value` で3値パターン（未指定/フラグのみ/値指定）
- `append_string()`, `append_int()`, `append_float()` — 配列蓄積
- `custom[T : Show]()`, `custom_append[T]()` — 汎用型。string/int/float/boolean は custom のシュガー（DR-025）
- `cmd()`, `sub()` — サブコマンド
- `positional()`, `rest()` — 位置引数（name はヘルプ `<NAME>` 表示に使用）
- `serial()`, `never()` — name パラメータなし

### 統一: 全 OptKind = initial + reducer

フラグも値オプションもカウンタも配列蓄積も、内部的には同じ構造に統一される:

| 種別 | initial | reducer の振る舞い |
|------|---------|-------------------|
| flag | `false` | `_ => true`（名前だけで値確定） |
| count | `0` | `current + 1`（出現ごとにインクリメント） |
| string | `default` | `Value(Some(s)) => s`（次の引数を値として取得） |
| append | `[]` | `Value(Some(s)) => acc + [s]`（配列に追加） |
| choices | `default` | 値が選択肢に含まれれば Accept、含まれなければ Reject |
| implicit_value | `default` | 値なし→implicit、値あり→その値（make_or_node で最長一致） |

reducer のシグネチャは `(ReduceCtx[T]) -> T?!ParseError`。3値の戻り:
- `Some(T)`: 消費成功。Ref[T] に書き込む
- `None`: マッチしない。消費ループの候補選定で脱落
- `raise ParseError`: 名前は一致したが値が不正。即エラー

ReduceCtx は struct ラッパー。MoonBit のクロージャにはラベル付き/オプション引数が使えないため、将来の拡張（フィールド追加）を壊さずに行うための設計判断（DR-008）。

### サブコマンド

```moonbit
let p = Parser::new()
let verbose = p.flag(name="verbose", global=true)  // 全スコープで有効

// sub(): 子パーサ直接返却（DR-026）
let serve = p.sub(name="serve", description="Start server")
let port = serve.int(name="port", default=8080)

// cmd(): setup コールバック方式
let deploy_cmd = p.cmd(name="deploy", setup=fn(child) {
  let target = child.string(name="target", default="")
})

let result = try? p.parse(args)
verbose.get()              // T? — global なのでどのスコープでも有効
result.child("serve")      // ParseResult? — サブコマンド結果
port.get()                 // T? — cobra-style アクセス
```

- 同一階層のサブコマンドは消費ループで常に1つに決まる（排他の仕組み不要）
- `global=true` のノードは子パーサに伝播。宣言順序非依存（遅延同期）

### 位置引数

```moonbit
let file = p.positional(name="FILE")                     // 固定長
let paths = p.rest(name="PATHS", stop_before=["--"])     // 可変長
let extras = p.dashdash()                                 // -- 以降を収集
```

positionals 配列の順番消費で serial を実現。`is_rest=true` なら同じハンドラを繰り返し使用。positional のハンドラは `--` prefix の引数を Reject する。

### 制約（post_hooks ベース）

```moonbit
p.exclusive([json_opt, csv_opt, yaml_opt])  // 排他: 最大1つ
p.at_least_one([json_opt, csv_opt])         // 最低1つ必須
p.required(output_opt)                      // 単一必須
p.require_cmd()                             // サブコマンド必須
p.requires(target_opt, source~=dep_opt)     // 依存: target 使用時に source 必須
```

全て post_hooks として実装。専用のフックパイプライン基盤は YAGNI。

### 環境変数連携（DR-041）

各コンビネータの `env~` パラメータで環境変数名を指定し、`Parser::parse(args, env~)` で環境変数マップを渡す。優先順位は CLI > 環境変数 > default:

```moonbit
let p = Parser::new()
p.env_prefix("MYAPP")  // プレフィックス設定
let port = p.int(name="port", default=8080, env="PORT")

// env_prefix により MYAPP_PORT を参照
let result = try? p.parse(args, env={"MYAPP_PORT": "3000"})
port.get()  // Some(3000)
```

- `Parser::env_prefix(prefix)` — 環境変数名にプレフィックスを付加。`env="PORT"` → `MYAPP_PORT` として参照
- サブコマンドの自動ネスト — `MYAPP` → `MYAPP_SERVE` → `MYAPP_SERVE_DB`（サブコマンド名を大文字化して連結）
- ヘルプ表示に `[env: MYAPP_PORT]` 形式で反映（プレフィックス付き）
- `Parser::auto_env(enabled)` — opt の name からハイフン→アンダースコア変換 + 大文字化で自動バインド（例: `--port` → `PORT`）。hidden opt は対象外。explicit `env~` が優先。`env_prefix` と組み合わせ可能。サブコマンドに継承

### 値の取得

```moonbit
opt.get()              // T? — cobra-style。推奨
parser.get(opt)        // T? — parse 前は None、parse 後は Some(T)
result.get(opt)        // T? — parser.get(opt) に委譲
result.child("serve")  // ParseResult? — サブコマンドナビゲーション
result.at(0)           // ParseResult? — ポジショナルナビゲーション
```

### FilterChain — Kleisli 合成による型安全な変換パイプライン（DR-016）

reducer に渡す前の `String → T` 変換を、型安全に合成可能なパーツとして分離する仕組み。

```moonbit
struct FilterChain[A, B] {
  run : (A) -> B!ParseError
}

// Kleisli 合成: A→B と B→C を繋いで A→C
fn then[A, B, C](self : FilterChain[A, B], next : FilterChain[B, C]) -> FilterChain[A, C]
```

3つのコンストラクタ:

```moonbit
Filter::map(f)       // 純粋変換: A → B（失敗しない）
Filter::validate(f)  // 検証: A → A（失敗時 ParseError。型を変えない）
Filter::parse(f)     // 変換 + 失敗: A → B（失敗時 ParseError）
```

**Accumulator** — 変換と蓄積の分離:

```moonbit
type Accumulator[T, U] = (T, U) -> T

fn make_reducer[T, U](
  pre   : FilterChain[String, U],  // String → U の変換
  accum : Accumulator[T, U],       // T に U をマージ
) -> (ReduceCtx[T]) -> T?!ParseError
```

この分離により、既存の append では表現できなかった「片が配列で累積もその結合」パターンが実現する:

| 種別 | pre (String → U) | accum (T, U) → T |
|------|-------------------|-------------------|
| single | `parse_int` 等 | `(_, u) => u`（上書き） |
| append | `parse_int` 等 | `(acc, u) => acc + [u]`（追加） |
| join 系 | `split(",").then(each(parse_int))` | `(acc, xs) => acc + xs`（結合） |

組み込みフィルタ（32個）:
- 文字列変換: `trim`, `to_lower`, `to_upper`, `trim_start`, `trim_end`, `replace(from, to)`, `replace_all(from, to)`
- 文字列検証: `non_empty`, `starts_with(prefix)`, `ends_with(suffix)`, `contains(substr)`, `min_length(n)`, `max_length(n)`, `min_codepoints(n)`, `max_codepoints(n)`, `min_graphemes(n)`, `max_graphemes(n)`
- 数値パース: `parse_int`, `parse_float`, `parse_bool`
- 数値検証: `in_range(min, max)`, `float_in_range(min, max)`, `positive`, `non_negative`
- 数値変換: `clamp(min, max)`
- 選択: `one_of(allowed)`
- 配列: `each(inner_filter)`, `split(sep)`, `mergeable_list(base, separator)` — `+/-/...` 修飾子でベース相対変更（DR-023）
- 正規表現: `regex_match(pattern)`, `regex_replace(pattern, replacement)`, `regex_split(pattern)`

**純粋性制約（DR-037）**: フィルタ（pre/post/accum）は純粋関数であること。値の状態管理は `Ref[T]` で行い、フィルタは入力から出力への変換のみを担う。この制約により、clone 時にフィルタのクロージャ参照を安全に共有できる（直交プリミティブの前提条件）。

### 合成パターン — 直交プリミティブ（DR-037）

3つの直交プリミティブで alias / variation / proxy が全て合成可能:

| プリミティブ | 関心事 | 役割 |
|-------------|--------|------|
| `clone(opt, name)` | アイデンティティ | 構造コピー（独立した cell、NodeTemplate のファクトリ共有） |
| `link(target, source~)` | 値 | post_hook による値転送（`propagate_set~` で committed 伝搬を制御） |
| `adjust(opt, ...)` | 振る舞い | post_hook でフィルタチェーンを適用 |

合成パターン:

| パターン | 式 | アイデンティティ | 値 | 振る舞い |
|---------|-----|:---:|:---:|:---:|
| alias | `link(clone(opt, name), opt)` | 新 | 転送 | 同じ |
| variation | `adjust(alias(opt, name), ...)` | 新 | 転送 | 変更 |
| derived | `adjust(clone(opt, name), ...)` | 新 | 独立 | 変更 |
| stricter | `adjust(opt, after_post=...)` | 同一 | 同一 | 変更 |

> **注**: 実装上の alias は `link(clone(...), ...)` の合成ではなく、Accessor 共有 + is_set 独立の専用実装。link は post_hook で source → target への値転送を行う。概念的な直交分解として上記パターンが成立する。

#### Variation — 反転・リセットパターン

全て `--{prefix}-{name}` 形式の ExactNode を生成する:

| Variation | 意味 | 用途 |
|-----------|------|------|
| `Toggle(p)` | `!current` | `--no-verbose`: Bool の反転 |
| `True(p)` | 常に `true` | 冪等な有効化 |
| `False(p)` | 常に `false` | 冪等な無効化 |
| `Reset(p)` | `cell=default, committed=true` | デフォルト値に戻す（明示指定扱い） |
| `Unset(p)` | `cell=default, committed=false` | 完全に未指定状態に戻す |

全コンビネータで `variations=[]` がデフォルト（自動で --no- を生やさない）。Sugar パラメータ（`variation_toggle?` 等）で明示指定する。

#### 実装済みの合成コンビネータ

- **alias** — `p.make_alias(name, target)`: 値共有 + is_set 独立の別名。チェーン alias 対応（alias の alias が root の committed まで伝搬）。global alias は子パーサに伝播
- **deprecated** — `p.deprecated(name, target, msg)`: alias + post_hook 方式。パース後に `deprecated_warnings()` で `Array[(name, msg)]` を取得。サブコマンド→親への再帰的伝搬対応
- **clone** — `p.clone(name, target)`: 構造コピー。独立した ValCell を持つが、NodeTemplate のファクトリを共有。save/restore パターンで target の cell に影響せず独立した値を保持
- **link** — `p.link(target, source~)`: 値転送。パース後に source の値を target にコピー。`propagate_set~` で committed の伝搬を制御
- **adjust** — `p.adjust(target, after_post~)`: 値変換。パース後に target の値を FilterChain で変換。target が set されている場合のみ適用

---

## 多言語エンジン基盤（構想）

> 以下は設計構想であり、確定事項ではない。詳細は各 DR を参照。

core は純粋関数ベースの薄いパースエンジンに留め、言語固有の型安全アクセスは各言語の DX 層で提供する。依存方向は `dx → core` の一方向。core は dx を知らない。

### 多言語基盤の4層アーキテクチャ（DR-036 構想）

```
DX API (各言語)  ← 言語イディオムに沿った型安全 API
  ↓
KuuCore (各言語) ← JSON 力学を隠蔽。コールバック仲介。バックエンド抽象化
  ↓
Bridge           ← core との接続層（方式は言語ごとに異なる、下記参照）
  ↓
Core (MoonBit)   ← 純粋パースエンジン
```

### 各言語への提供形式（検討中）

core を各言語から利用する方式は未確定。言語ごとに最適な方式が異なり、ランタイムの成熟度にも依存する（DR-033, DR-046, DR-047）:

| 方式 | 概要 | 現状 |
|------|------|------|
| V8 WASM-GC | JS/TS から直接ロード | PoC 実装あり（src/wasm/）。JSON schema → core → JSON result |
| wasmtime 埋め込み | Rust, Python から WASM-GC バイナリをロード | wasmtime v27+ で WASM-GC 対応。PoC 未着手 |
| Node.js サブプロセス | Go, Swift 等。JSON ブリッジ | PoC 実装あり。プロセス起動オーバーヘッドあり |
| MoonBit native → C FFI | 全言語から C FFI で接続 | MoonBit native バックエンド成熟待ち |
| core 再実装 | 各言語でネイティブ実装 | テストケース共有で品質保証する構想 |

### MoonBit DX 層（DR-042、実装済み）

struct-first 方式。Parseable trait + FieldRegistry + parse_into の2フェーズ:

1. **register フェーズ**: ユーザーの struct が `Parseable` trait を実装し、`register(self, registry)` で各フィールドを登録。registry は core の Parser にオプションを登録しつつ、apply_fn クロージャを蓄積
2. **apply フェーズ**: parse 成功後、蓄積した apply_fn を順に実行してユーザーの struct に値を注入。parse 失敗時は apply されない（トランザクショナル）

apply_fn パターンにより、core 側の Ref[T] が DX 層に漏洩しない。

### TypeScript DX 層（pkg/ts/、PoC）

WASM-GC ラッパー + Schema DSL + 型推論の PoC 実装。`kuu()` で宣言的にスキーマを定義し、`InferResult<O>` でパース結果の型を自動導出する:

- **Schema DSL**: `flag()`, `stringOpt()`, `intOpt()`, `count()`, `sub()`, `positional()`, `rest()`, `dashdash()` 等のコンビネータファクトリ
- **InferResult 型推論**: required → non-optional、choices `as const` → リテラルユニオン型、サブコマンド → discriminated union
- **WASM-GC 直接ロード**: V8 の WASM-GC builtins + js-string を利用。JSON protocol 経由で kuu core を呼び出す
- 30 テスト通過。npm publish は未実施

### Opt 定義の AST 可搬性（DR-029, DR-030 構想）

Opt 定義は純粋データ（定義レベルではクロージャなし）。JSON にシリアライズして他言語に転送可能な構想:
- 静的定義（flag, string, int, count, append, choices, implicit_value, variations, aliases）: JSON で完全表現
- 動的部分（custom[T], post フィルタ）: ターゲット言語側で実装する未定義スロットとして表現。型システムが補完をガイド

---

## 投機実行 + 最長一致パースモデル

### パースエンジン内部の4層構造

```
Sugar:       flag(), string(), custom[T](), cmd(), ...
Convention:  expand_and_register — name + aliases + shorts + variations 展開
Pattern:     make_or_node — 最長一致で複合ノード統合
Core:        ExactNode (try_reduce) + OC/P 消費ループ + 直交プリミティブ（clone, link, adjust）
```

各層が **ExactNode の生成と Parser への登録** という単一操作に統一されている。

#### Core 層

**ExactNode** — 完全一致名 + 投機実行関数のペア:

```moonbit
pub(all) struct ExactNode {
  name : String                          // 完全一致名（"--verbose", "--no-verbose", "serve"）
  needs_value : Bool                     // true なら次の引数を値として消費
  try_reduce : (Array[String], Int) -> TryResult  // 投機実行
  reset : () -> Unit                     // initial 値にリセット
}
```

**TryResult** — 投機実行の3値判定:

```moonbit
pub(all) enum TryResult {
  Accept(consumed~ : Int, commit~ : () -> Unit)  // 消費可能。commit() で値を確定
  Reject                                          // マッチしない（他の候補を試す）
  Error(ParseError)                               // 名前一致だが値不正（即エラー）
}
```

**重要**: Accept は consumed 数と commit クロージャを返すが、**commit は呼ばれるまで値を書き込まない**。これが投機実行の核心——「食えるか試す」と「実際に食う」が分離されている。最長一致で勝者が確定してから初めて commit() が呼ばれる。

**Reject と Error の使い分け**は名前解決の前後で意味が変わる（DR-015）:
- 名前解決前（positional の候補選定等）: 型が合わない → `Reject`（他の候補を試す）
- 名前解決後（`--port abc` で port 確定済み）: 値の型変換失敗 → `Error`（握り潰さない）

#### Pattern 層

**make_or_node** — 複数の子 ExactNode を最長一致で統合するコンポジットノード。クロージャで子ノードをキャプチャするため、ExactNode の構造変更なし:

```
make_or_node([
  make_soft_value_node("--color", ...),     // consumed=2（値付き）
  make_implicit_flag_node("--color", ...),  // consumed=1（暗黙値）
])
→ 全子ノードに try_reduce → 最長 consumed の候補を選択
→ 同率なら ambiguous エラー
```

choices + implicit_value の共存が、make_or_node の最長一致で自然に解決される。

#### Convention 層

**expand_and_register** — 1つのコンビネータ宣言から複数の ExactNode を展開・登録:

```
flag(name="verbose", shorts="v", variation_toggle="no")
→ expand_and_register が以下を生成:
  - "--verbose" (flag_node)
  - "--no-verbose" (toggle_node: !current)
  - "-v" (short alias)
→ 3つの独立した ExactNode が Parser.nodes に push
```

Convention 層が展開を完了した時点で、**消費ループは名前解決のロジックを一切持たなくて済む**。`--no-verbose` は独立した ExactNode であり、prefix stripping のような実行時解析は不要。

### Tokenizer（横断的前処理）— install ノード

消費ループの前に、特殊な引数形式を通常の ExactNode に変換する install ノードが parse_raw 冒頭で構築される（DR-017）。これにより **parse_raw のメインループから特殊分岐が完全に排除**される:

| install ノード | 変換内容 | 詳細 |
|---------------|---------|------|
| `install_eq_split_node` | `--name=value` → 分解して既存ノードに委譲 | consumed≥2 gate で implicit_value の誤マッチを防止 |
| `install_short_combine_node` | `-abc` → 各文字をノードに委譲 | value trial → flag trial のフォールバック。型情報で `-vA1B1` も分解可能 |
| `install_separator_node` | `--` → 以降を positional に転送 | 初期化時に自動登録（`dashdash=true` がデフォルト） |

**核心**: 各 ExactNode が「自分の消費可能性を自己判定できる」ため、ショートオプション結合の分解も install ノード内での再帰的 try_reduce 呼び出しとして表現される（DR-015, DR-039）。型情報（needs_value, consumed 数）がバックトラッキング判断に直接使われる。

### OC/P 2フェーズパース（DR-034）

消費ループは2フェーズで構成される:

**OC Phase (Option/Command)** — ExactNode 走査 + 最長一致:

```
while pos < args.length:
  全 ExactNode に try_reduce(args, pos) を呼ぶ
  → Accept 候補の consumed が最大のものを選ぶ
    → 最大が複数: raise ParseError(ambiguous)
    → 最大が1つ: commit() + pos += consumed
    → Accept が0:
      → greedy positional があれば消費試行
      → 消費できなければ unclaimed に蓄積
```

**P Phase (Positional)** — unclaimed 引数を positional に割り当て:

```
force_unclaimed（-- 以降）+ unclaimed を結合
greedy positionals をスキップ（OC Phase で消費済み）
non-greedy positionals で前から順に消費:
  → is_rest=false: 1つ消費して次の positional へ
  → is_rest=true: 同じハンドラを繰り返し消費
余りがあれば raise ParseError("unexpected argument")
```

**なぜ2フェーズか**: positional はデフォルト non-greedy（P Phase のみ）。これにより「typo した引数名が positional に吸い込まれる」問題を構造的に防止する。`greedy=true` を明示した positional のみ OC Phase で消費される。has_prefix("--") のようなヒューリスティクスに依存しない。

### スコープ遷移（サブコマンド）

Command がマッチしたら:
- 子パーサの parse を残り args で再帰呼び出し（スコープ置換）
- `global=true` のノードは子パーサの nodes/global_nodes に伝播（遅延同期: cmd 定義後に追加された global も try_reduce 時に同期）
- cmd の ExactNode は `Accept(consumed=args.length()-pos)` を返し、残り全てを子が消費

---

## 値の保持と型安全性

### 型消去の問題と解法

CLI パーサは `Opt[Bool]`、`Opt[Int]`、`Opt[String]`、`Opt[Array[String]]` など、異なる型のオプションを1つの配列で管理し、型を知らずに走査する必要がある。MoonBit には Rust の `dyn Trait` のような動的ディスパッチがなく、Java の `Object` のようなルート型もない。

**解法: クロージャによる型消去 + ValCell/Accessor 共有**

各コンビネータ内で `ValCell[T]` を生成し、そこから `Accessor[T]`（クロージャ束）を取得する。**ExactNode と Opt[T] が同じ ValCell を操作する**:

```
コンビネータ（例: string）内部:
  let valcell : ValCell[String] = ValCell::new(default)
  let acc : Accessor[String] = valcell.accessor()

  ExactNode.try_reduce クロージャ ─→ acc.set(v) で書き込み（型消去ビュー: T を知らない）
  Opt[T].accessor ────────────────→ acc.get() で読み出し（型ありビュー: T として返す）
```

- **型消去ビュー**: ExactNode の `try_reduce : (Array[String], Int) -> TryResult` は型パラメータを持たない。commit クロージャが `acc.set(parsed_value)` を行うが、`ValCell[String]` であることを ExactNode 自体は知らない
- **型ありビュー**: `Opt[String].accessor.get : () -> String` が同じ `ValCell` から `String` として読み出す

ダウンキャスト不要。ResultMap のような中間データ構造も不要。型安全性はコンパイル時に保証される。

### Opt[T] — 薄い参照型

```moonbit
pub(all) struct Opt[T] {
  id : Int                    // 一意 ID（Parser.next_id で採番）
  name : String               // オプション名（"--verbose" 等）
  priv accessor : Accessor[T] // 値の読み書き・状態管理の統一インターフェース
  parsed : Ref[Bool]          // Parser.parsed への参照（パース完了で true）
  priv used : () -> Bool      // この Opt 名が使われたか（通常=committed、alias/clone=独立）
}
```

ユーザーは `opt.get() -> T?` で値を取得。パース前なら `None`、パース後なら `Some(T)`。`opt.is_set() -> Bool` で明示指定されたかを確認できる。

Opt は薄い参照型。initial / reducer / meta はコンビネータ内のクロージャにキャプチャされ、Opt 自体には含まれない。内部の `Accessor[T]` は ValCell から生成されたクロージャ束で、get/set/set_value/set_commit/reset の5操作を提供する（DR-048 で is_set を Opt.used に分離）。ExactNode の try_reduce/commit と同じ ValCell を共有するため、型安全性は静的に保証される。

### ParseResult — 階層ナビゲーション

```moonbit
pub(all) struct ParseResult {
  kind : ParseResultKind      // One | Map_(children) | List_(positionals)
  parser : Parser             // このスコープの Parser
}
```

`child(key)` でサブコマンド結果、`at(i)` でポジショナル結果にアクセス。いずれもプリミティブ（`as_map` / `as_list`）のシュガー。

### Lazy[T] — 遅延評価可能な値

```moonbit
pub(all) enum Lazy[T] {
  Val(T)         // 即値
  Thunk(() -> T) // 遅延評価（ランタイム依存の初期値）
}
```

implicit_value のデフォルト値や choices + implicit の組み合わせで、パース時に初めて評価される値を表現する。

### ValCell/Accessor 分離（DR-045）

ValCell[T] が値（cell）と状態（committed）とデフォルト値（default_val）を内包し、Accessor[T] がその操作インターフェースをクロージャ束として提供する:

- **Accessor[T]**: get/set/set_value/set_commit/reset の5操作（値操作に純化、DR-048）
  - `set(v)` = `set_value(v)` + `set_commit()`: 値と committed の両方を更新
  - `set_value(v)`: 値のみセット。committed は変更しない
  - `set_commit()`: committed マークのみセット。値は変更しない
  - `reset()`: value も committed もリセット（value = default, committed = false）
- **Opt.used**: この Opt 名が使われたかを示すクロージャ（DR-048）。通常は `vc.committed` と同値、alias/clone では独立した `opt_used` フラグ

この分離により、clone は独立した ValCell + 独自の Accessor を持ち、alias は target の Accessor を共有しつつ used のみ独立させる、という構成が自然に表現される。

### Visibility — 表示制御

```moonbit
pub(all) enum Visibility {
  Visible      // デフォルト。ヘルプ表示 ✓、補完候補 ✓
  Advanced     // ヘルプ表示 ✗、補完候補 ✓（パワーユーザー向け）
  Hidden       // ヘルプ表示 ✗、補完候補 ✗
}
```

OptMeta の `visibility` フィールドとして全コンビネータの `visibility~` パラメータで指定。旧 `hidden: Bool` を置換し、3段階の表示制御を提供する。`auto_env` は `Hidden` を対象外とする（従来の hidden 互換）。

### 補完候補生成

```moonbit
pub(all) struct CompletionCandidate {
  value : String        // 補完候補文字列（"--verbose", "-v", "serve" 等）
  description : String  // 説明文（OptMeta.help から取得）
  group : String        // グループ（"Options", "Global Options", "Commands"）
}
```

- `Parser::generate_completions()` — 全候補を `Array[CompletionCandidate]` として返す。`Hidden` は除外、`Advanced` は含む
- `Parser::generate_completion_script(shell~, command_name~)` — bash/zsh/fish のシェル補完スクリプトを生成。内部で `generate_completions()` を呼び、シェル固有の形式に変換する

---

## パッケージ構成

```
src/
  core/              # 全パース機能
    types.mbt         #   型定義（Opt, Parser, ExactNode, TryResult, OptMeta, Visibility, CompletionCandidate, Variation, Lazy, ReduceCtx, FilterChain 等）
    parser.mbt        #   Parser::new, register_option, make_alias, deprecated, clone, link, adjust, expand_and_register, env_prefix
    options.mbt       #   custom, custom_append, flag, string, int, float, boolean, count, file, append_string, append_int, append_float
    nodes.mbt         #   make_flag_node, make_value_node, make_or_node, make_soft_custom_value_node 等
    commands.mbt      #   cmd, sub
    positionals.mbt   #   positional, rest, serial, never
    dashdash.mbt      #   dashdash, append_dashdash
    constraints.mbt   #   exclusive, required, require_cmd, at_least_one, requires
    access.mbt        #   Opt::get, Parser::get, deprecated_warnings, ParseResult アクセサ
    parse.mbt         #   parse_raw（OC/P 2フェーズ）, install_* ノード, validate_no_duplicate_names
    help.mbt          #   generate_help, inject_help_node, help_header, help_footer, generate_completions, generate_completion_script
    filter.mbt        #   FilterChain, Filter::*, make_reducer, Accumulator, 組み込みフィルタ
  dx/                # struct-first DX 層（Parseable trait + FieldRegistry + parse_into）
  wasm/              # WASM bridge PoC（JSON schema → kuu core → JSON result）
  contrib/
    timespec/        # kawaz/timespec 連携フィルタ（parse_duration, parse_timespec, parse_timespec_optional）
pkg/
  ts/                # TypeScript DX PoC（WASM-GC ラッパー + Schema DSL + InferResult 型推論）
```

---

## 関連ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| [DESIGN-internals.md](DESIGN-internals.md) | 詳細実装仕様（Parser struct 全フィールド、ExactNode 種類一覧、install ノードアルゴリズム、ヘルプ生成） |
| [DESIGN-roadmap.md](DESIGN-roadmap.md) | 将来計画・未実装設計（エラー構造化、group、defaults マルチソース、多言語展開等） |
| [valcell-lifecycle.md](valcell-lifecycle.md) | ValCell/Accessor ライフサイクル詳細 |
| [kuu-essence.md](kuu-essence.md) | プロジェクトの本質・ポジショニング |
| [kuu-showcase.md](kuu-showcase.md) | ユースケース事例集（作成中） |
| `docs/decisions/` | 個別の設計判断記録（DR-001 以降） |
