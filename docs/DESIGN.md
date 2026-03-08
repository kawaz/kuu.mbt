# CLI 引数パーサ設計書

## Context

- Phase 1-3 の PoC は「テストケース = 要件」として引き継ぐ。コードは全削除して完全作り直し
- 核心: 全 OptKind を `initial + ReduceCtx reducer` で統一
- heterogeneous collection は ExactNode struct（完全一致名マッチ + reducer クロージャ）で実現（trait object 不使用）
- String ベースの中間表現は不要。T ベースで直接動作
- 4層レイヤー構造: Core（ExactNode）→ Pattern（make_or_node）→ Convention（expand_and_register）→ Sugar（flag 等）

Design rationale (DR-012): 旧設計では ErasedNode struct（クロージャ束）と Opts enum（Node/Array）でツリー構造を表現していたが、
ExactNode ベースの4層レイヤーアーキテクチャに転換。消費ループの責務を最小化し、名前解決の複雑さをコンビネータ層に押し出す設計。
プレフィックスマッチは MVP 後に追加レイヤーとして実装可能。詳細は DR-012 参照。

---

## 設計原則

- **Opt[T] は薄い参照型** — id + name + getter + parsed + is_set を保持。値の格納はクロージャ内の Ref[T] に隠蔽
- **parse は ExactNode のフラットリストを走査** — 完全一致名マッチ + 最長一致で候補選択。型を知らずに操作
- **4層レイヤーで複雑さを分離** — Core（ExactNode + 消費ループ）→ Pattern（make_or_node）→ Convention（expand_and_register）→ Sugar（flag 等）
- **ユーザーは `result.get(opt)` で型付きの値を取得** — Opt[T] がレンズ/キーとして機能。戻り値は `T?`（スコープ外なら `None`）
- **ParseResult は階層ナビゲーション可能** — `child(key)` でサブコマンド結果、`at(i)` でポジショナル結果にアクセス（DR-013）
- **ヘルプが従、コアが主** — 表示用メタデータのためにコア設計を歪めない。OptMeta はヘルプ生成専用
- **既存パーツの組み合わせで考えよ** — 新フィールドや型を追加する前に、既存の型・クロージャの組み合わせで解決できないか検討する
- **try_reduce は TryResult を返す** — Accept（consumed + commit クロージャ）/ Reject（名前不一致）/ Error（名前一致だが値不正）。名前確定後の型変換失敗は即エラー
- **FilterChain[A, B] で String→T の前処理を型安全に合成** — map / validate / parse の3コンストラクタ + `then` で Kleisli 合成（DR-016）
- **スペース形式は維持する** — `--name value` のスペース区切り形式を基本とし、`--name=value` は install_eq_split_node で透過的に対応

---

## Opt ツリー構造

### Opt[T] — 薄い参照型

Opt[T] はパース結果への型付きハンドル。値の格納・取り出しは getter クロージャに隠蔽される。
parsed フラグで「パース済みかどうか」を判定し、`opt.get() -> T?` を実現する。

```moonbit
pub(all) struct Opt[T] {
  id : Int                    // 一意 ID（Parser.next_id で採番）
  name : String               // オプション名（"--verbose" 等）
  getter : () -> T            // クロージャ内の Ref[T] から値を取得
  parsed : Ref[Bool]          // Parser.parsed への参照（パース完了で true）
  is_set : () -> Bool         // 明示指定されたかどうか
}
```

Design rationale: Opt は薄い参照型。initial/reducer/meta はコンビネータ内のクロージャにキャプチャされ、
Opt 自体には含まれない。name と is_set はユーザー側の利便性のために追加されたが、
Opt のフィールドは最小限に保たれ、ユーザーが保持しても負担にならない。
getter がキャプチャする Ref[T] とコンビネータ内の ExactNode が同じ Ref[T] を共有するため、型安全性は静的に保証される。

**値の取得**:

```moonbit
pub fn[T] Opt::get(self : Opt[T]) -> T? {
  if self.parsed.val { Some((self.getter)()) } else { None }
}
```

### Lazy[T] — 遅延評価可能な値

```moonbit
pub(all) enum Lazy[T] {
  Val(T)        // 即値
  Thunk(() -> T) // 遅延評価（ランタイム依存の初期値）
}

pub fn[T] Lazy::resolve(self : Lazy[T]) -> T {
  match self { Val(v) => v; Thunk(f) => f() }
}
```

Design rationale: `Lazy[T]` は即値と遅延評価を統一的に扱う。implicit_value のデフォルト値や
choices + implicit の組み合わせで、パース時に初めて評価される値を表現するために使用される。

### ExactNode フラットリスト + Positional 管理

パーサは2種類のノードリストを保持する:

- **nodes: Array[ExactNode]** — 名前付きオプション（`--verbose`, `--no-verbose` 等は個別の ExactNode）
- **positionals: Array[(handler, is_rest)]** — 位置パラメータハンドラ。順番消費を `current_positional` インデックスで制御

各コンビネータ（flag, string_opt 等）は ExactNode を生成して `parser.nodes` に直接 push する。
`opts([...])` ヘルパーは不要（各コンビネータが Parser メソッドとして直接登録するため）。

- **名前付きオプション** — ExactNode として nodes に登録。`--verbose`, `--no-verbose`, エイリアス等は個別の ExactNode
- **Positional** — positionals 配列のハンドラとして登録。`is_rest=false` なら消費後に次へ進む
- **rest** — `is_rest=true` の Positional。同じハンドラが繰り返し消費される
- **global** — global_nodes にも登録され、子パーサに伝播

Design rationale (DR-012): ExactNode が完全一致名を持つためツリー走査が不要。`--no-verbose` 等の Variation パターンは
コンビネータ層（Convention レイヤー: expand_and_register）で独立した ExactNode に展開されるため、消費ループは名前解決ロジックを持たなくて済む。

### 合成パターン

- **make_or_node** — 複数の子 ExactNode を最長一致で統合するコンポジットノード（Pattern レイヤー）【実装済み】。choices + implicit_value の組み合わせで使用。クロージャで子ノードをキャプチャするため、ExactNode の構造変更なし
- **rest** — 可変長消費。positionals に `is_rest=true` で登録【実装済み】
- **stop_before** — rest/dashdash のトークン境界指定【実装済み】

#### その他の合成パターン

- **serial** — positionals 配列の順番消費で実現【実装済み】
- **never** — 常に ParseError を投げるセンチネルノード【実装済み】
- **group** — 繰り返し出現するオプション群。雛形を clone して各出現の値を保持（未実装）

#### 4層レイヤー構造

```
flag(name="verbose")                   # Sugar: Bool特化
  → expand_and_register(...)           # Convention: --name + variations 展開
    → make_or_node([                   # Pattern: 複数 ExactNode を最長一致で統合
        make_soft_value_node(...),     # Core: 値マッチ（Reject でフォールバック可）
        make_implicit_flag_node(...),  # Core: 名前のみマッチ（implicit value）
      ])
```

| レイヤー | 責務 | 実装ファイル |
|---------|------|------------|
| Core | ExactNode（完全一致名マッチ + try_reduce）+ 消費ループ | parse.mbt, nodes.mbt |
| Pattern | make_or_node — 複数 ExactNode を最長一致で統合 | nodes.mbt |
| Convention | expand_and_register — --name + aliases + shorts + variations 展開 | parser.mbt |
| Sugar | flag(), string_opt(), int_opt(), count(), append_string(), append_int(), custom(), positional(), rest(), cmd() | options.mbt, commands.mbt, positionals.mbt, dashdash.mbt |

Design rationale (DR-012): 旧設計のツリー構造は廃止。各レイヤーが ExactNode の生成と Parser への登録という
単純な操作に統一された。make_or_node は最長一致ロジックを内包し、choices + implicit_value のような
複合パターンを単一の ExactNode に見せる。

### ReduceAction

```moonbit
///|
pub(all) enum ReduceAction {
  /// 正方向: Flag/Count は None、Single/Append は Some(value)
  Value(String?)
} derive(Show, Eq)
```

### Variation — 反転・リセットパターン【実装済み】

各コンビネータが生成する「メインオプションの変形」を定義する。全て `--{prefix}-{name}` 形式の flag ノードを生成する。

```moonbit
pub(all) enum Variation {
  Toggle(String)    // --{p}-{name}: !current（トグル）。Bool 専用。偶数回で元に戻る
  True(String)      // --{p}-{name}: 常に true（Bool 専用、冪等）
  False(String)     // --{p}-{name}: 常に false（Bool 専用、冪等）
  Reset(String)     // --{p}-{name}: cell=default, was_set=true
  Unset(String)     // --{p}-{name}: cell=default, was_set=false
}
```

全コンビネータで `variations=[]` がデフォルト（自動で --no- を生やさない）。

Sugar パラメータ: `variation_toggle?`, `variation_true?`, `variation_false?`, `variation_reset?`, `variation_unset?` — variations に append される。

詳細は DR-024 参照。

### ReduceCtx[T] と reducer パターン【実装済み】

```moonbit
pub(all) struct ReduceCtx[T] {
  current : T              // 現在の累積値
  action : ReduceAction    // 今回のアクション
}
```

reducer のシグネチャ: `(ReduceCtx[T]) -> T? raise ParseError`

`make_reducer` が FilterChain + Accumulator から自動生成する（実装済み）:

```moonbit
pub fn[T, U] make_reducer(
  pre : FilterChain[String, U],
  accum : Accumulator[T, U],
) -> (ReduceCtx[T]) -> T? raise ParseError {
  fn(ctx) {
    match ctx.action {
      Value(Some(s)) => Some(accum(ctx.current, (pre.run)(s)))
      _ => None
    }
  }
}
```

Design rationale (DR-008): ReduceCtx に新しいメソッドを追加しても既存 reducer は壊れない。
MoonBit ではクロージャにラベル付き/オプション引数が使えないため、struct ラッパーが最適解。

| 種別 | コンビネータ | reducer の実装方式 |
|------|------------|------------------|
| Flag | `flag()` | make_flag_node 直接構築（ReduceCtx 不使用） |
| Count | `count()` | make_flag_node + pending で直接構築 |
| Single(String) | `string_opt()` | custom 経由: make_reducer(identity, replace, initial) |
| Single(Int) | `int_opt()` | custom 経由: make_reducer(parse_int, replace, initial) |
| Append | `append_string()` | make_value_node で直接構築 |
| choices | `string_opt(choices=[...])` | make_reducer(one_of, replace, initial) |
| implicit_value | `string_opt(implicit_value=...)` | make_or_node で composite 構築 |

Design rationale: Flag/Count は単純すぎるため ReduceCtx を経由せず ExactNode を直接構築する。
値オプション（string_opt, int_opt の通常ケース）は make_reducer 経由で FilterChain の恩恵を受ける。

---

## FilterChain — pre フィルタの型安全な合成（DR-016）【実装完了】

reducer に渡す前の `String → T` 変換を、型安全に合成可能なパーツとして分離する仕組み。

**実装状況**: FilterChain[A, B] の基盤と組み込みパーツは実装完了（`src/core/filter.mbt`）。
- `FilterChain::then`（Kleisli 合成）、3コンストラクタ（`Filter::map`, `Filter::validate`, `Filter::parse`）
- 9組み込みパーツ: `trim`, `to_lower`, `non_empty`, `split`, `parse_int`, `parse_float`, `in_range`, `one_of`, `each`
- `Accumulator[T, U]` 型、`Filter` 空struct（名前空間用）
- テスト: 667/667 passed
- `make_reducer` — FilterChain + Accumulator → reducer の自動生成【実装完了】

```moonbit
///| A → B の変換ステップ（ParseError を伝搬できる）
struct FilterChain[A, B] {
  run : (A) -> B!ParseError
}

///| Kleisli 合成。A→B と B→C を繋いで A→C
fn FilterChain::then[A, B, C](
  self : FilterChain[A, B],
  next : FilterChain[B, C],
) -> FilterChain[A, C] {
  { run: fn(a) { next.run(self.run(a)!) } }
}
```

### 3つのコンストラクタ

```moonbit
fn Filter::map[A, B](f : (A) -> B) -> FilterChain[A, B]                    // 純粋変換
fn Filter::validate[A](f : (A) -> Unit!ParseError) -> FilterChain[A, A]    // 検証（型を変えない）
fn Filter::parse[A, B](f : (A) -> B!ParseError) -> FilterChain[A, B]       // 変換 + 失敗あり
```

### Accumulator との組み合わせ

「片の型 U」と「累積型 T」を分離することで、既存の append では表現できなかった
「片が配列で累積もその結合」パターンを実現する。

```moonbit
///| 片 U を現在の累積値 T にマージする関数
type Accumulator[T, U] = (T, U) -> T

///| FilterChain + Accumulator → reducer の自動生成【実装完了】
fn make_reducer[T, U](
  pre     : FilterChain[String, U],
  accum   : Accumulator[T, U],
) -> (ReduceCtx[T]) -> T?!ParseError {
  fn(ctx) {
    match ctx.action {
      Value(Some(s)) => Some(accum(ctx.current, pre.run(s)!))
      _              => None
    }
  }
}
```

### 既存コンビネータとの統一

| 種別      | pre (String → U)                          | accum (T, U) → T          |
|-----------|-------------------------------------------|---------------------------|
| `single`  | `parse_int` 等                            | `(_, u) => u`（上書き）   |
| `append`  | `parse_int` 等                            | `(acc, u) => acc + [u]`   |
| join 系   | `split(",").then(each(parse_int))`        | `(acc, xs) => acc + xs`   |

### 使用例

```moonbit
// --port 8080
let port = opt::single(
  name = "port",
  pre  = trim.then(parse_int).then(in_range(1, 65535)),
)

// --nums 1,2,3 --nums 5,5,5 → [1,2,3,5,5,5]
let nums = opt::custom_append(
  name  = "nums",
  pre   = trim.then(split(",")).then(each(trim.then(parse_int))),
  accum = fn(acc, xs) { acc + xs },
)

// --format json（choices バリデーション）
let format = opt::single(
  name = "format",
  pre  = trim.then(to_lower).then(one_of(["json", "csv", "tsv"])),
)
```

### 型安全性の保証

チェーンの途中で型が合わない場合はコンパイルエラーになる。
`Array[Any]` でフィルタをランタイム保持する方式と異なり、
「最終的に `String → T` になっている」ことをコンパイル時に保証できる。

組み込みパーツの詳細は DR-016 参照。

Design rationale: reducer のシグネチャを `(ReduceCtx[T]) -> T?!ParseError` の1引数に統一する。
旧設計の `(T, ReduceAction)` 2引数、その後の `(T, ReduceAction, ParseContext)` 3引数を経て、
**後方互換性**を重視した最終形。ReduceCtx に新しいメソッドを追加しても既存 reducer は壊れない。
MoonBit ではクロージャにラベル付き/オプション引数が使えない（言語制約）ため、struct ラッパーが最適解。
エラーパスは MoonBit の raise 構文で伝搬する。`parse!(s)` が失敗した場合、reducer から ParseError が raise される。
reducer の戻り値は3値: `None`（マッチしない = 候補脱落）、`Some(T)`（消費成功）、raise `ParseError`（エラー）。
消費ループの候補選別で各候補の reducer に引数を渡し、None を返すものを除去する仕組みの根幹。
例: flag は常に Some(true)、since に "1h3m" → Some(Duration)。

reducer の3値の設計根拠:
- None: 「この引数を食えない」= 消費ループの候補選定で使用。他の候補を試す
- Some(T): 「この引数を消費した」= Ref[T] に書き込む
- ParseError: 「マッチしたがバリデーション失敗」= 即座にエラー

重要: None と ParseError の使い分けは**名前解決の前後で異なる**:
- 名前解決前（positional の候補選定等）: 型が合わない → None（他の候補を試す）
- 名前解決後（`--port abc` で port が確定済み）: 値の型変換失敗 → ParseError（エラーを握り潰さない）

例: `--port 123` → 名前解決で port 確定 → int parse "123" → Some(123)。
例: `--port abc` → 名前解決で port 確定 → int parse "abc" → raise ParseError（None にすると別候補に流れて誤動作）。
例: positional の候補選定で "abc" を int と file が競合 → int は None、file が Some → file が消費。

---

## 値の保持 — Ref[T] クロージャキャプチャ方式

値は ResultMap ではなく、各コンビネータ内の `Ref[T]` に直接保持される。Opt[T] の getter クロージャがその Ref[T] をキャプチャし、型安全に値を返す。

```moonbit
// コンビネータ内部（例: flag）
let cell : Ref[Bool] = { val: default }           // 値の実体
let node = make_flag_node("--" + name, ...)       // cell をクロージャでキャプチャ
let opt = { id, getter: fn() { cell.val }, parsed: self.parsed }
```

同じ `Ref[T]` に対して2つのビューが共存する:
1. **型消去ビュー** — ExactNode の try_reduce/commit クロージャが Ref[T] をキャプチャし、T を知らずに操作
2. **型ありビュー** — Opt[T].getter クロージャ経由で直接 T として取り出す

Design rationale: 最初から T を知っている Opt[T] と、T を閉じ込めたクロージャが同じ Ref[T] を共有するため、
型安全性は静的に保証される。ダウンキャスト不要。ResultMap のような中間データ構造も不要。

---

## 型付き結果の取り出し

### ParseResult ベースのアクセス（DR-013）【実装済み】

parse 後の結果は `ParseResult raise ParseError` として返される。ユーザー側で `try?` を使えば `Result` に変換可能。3つのアクセス方法がある:

#### 1. cobra-style: `opt.get() -> T?`

```moonbit
let p = Parser::new()
let port = p.int_opt(name="port", default=8080)
let verbose = p.flag(name="verbose")
let result = try? p.parse(args)

port.get()     // T? — パース済みなら Some(T)、未パースなら None
verbose.get()  // T?
```

内部的には Parser.parsed（Ref[Bool]）を参照し、パース完了後なら getter で値を返す。

#### 2. ParseResult からのアクセス

```moonbit
let result = try! p.parse(args)

result.get(port)     // T? — parser.get(opt) に委譲
result.get(verbose)  // T?

// 階層ナビゲーション
result.child("serve")                    // ParseResult? — サブコマンド結果
result.child("serve").unwrap().get(port) // T?
```

#### ParseResult の型構造【実装済み】

```moonbit
pub(all) enum ParseResultKind {
  One                                // 単一値（このスコープの opt 群の結果）
  Map_(Map[String, ParseResult])     // サブコマンド名 → 子の ParseResult
  List_(Array[ParseResult])          // serial/rest の位置別 ParseResult
}

pub(all) struct ParseResult {
  kind : ParseResultKind
  parser : Parser    // このスコープの Parser（get(opt) で使う）
}
```

#### アクセスメソッド【実装済み】

| メソッド | 戻り値 | 説明 |
|---------|--------|------|
| `Opt[T]::get()` | `T?` | cobra-style。Parser.parsed 経由 |
| `Opt[T]::is_set()` | `Bool` | 明示指定されたかどうか |
| `Opt[T]::name` | `String` | オプション名（"--verbose" 等） |
| `Parser::get(Opt[T])` | `T?` | parse 前は None、parse 後は Some(T) |
| `ParseResult::get(Opt[T])` | `T?` | parser.get(opt) に委譲 |
| `ParseResult::as_map()` | `Map[String, ParseResult]?` | Map 表現（プリミティブ） |
| `ParseResult::as_list()` | `Array[ParseResult]?` | List 表現（プリミティブ） |
| `ParseResult::child(key)` | `ParseResult?` | `as_map()?.get(key)` のシュガー |
| `ParseResult::at(index)` | `ParseResult?` | `as_list()?[index]` のシュガー |

Design rationale (DR-013): 結果アクセスは3つの口を提供（全て `T?`）: `parser.get(opt)`、
`opt.get()`（cobra-style）、`result.get(opt)`（ParseResult 経由）。
`result.get(opt)` は内部的に `result.parser.get(opt)` に委譲する。
`child`/`at` はプリミティブ（`as_map`/`as_list`）のシュガー。

### Parser::get — 直接アクセス【実装済み】

`Parser::get(opt) -> T?` は parse 前なら `None`、parse 後は `Some(T)`。

```moonbit
pub fn[T] Parser::get(self : Parser, opt : Opt[T]) -> T? {
  if not(self.parsed.val) { None } else { Some((opt.getter)()) }
}
```

構築時に変数バインドし、parse 後に取得する:

```moonbit
let p = Parser::new()
let port = p.int_opt(name="port", default=8080)
let verbose = p.flag(name="verbose")
let result = try! p.parse(args)
p.get(port)       // T?
p.get(verbose)    // T?
```

### グループ Opt — 雛形 + clone 方式【将来検討】

> **注意**: group は未実装。以下は設計案であり、実装時に変更される可能性がある。

繰り返し出現するオプション群を扱う。雛形を clone して各出現の値を保持する:

```moonbit
let upstream_host = opt::str(name="host")
let upstream_timeout = opt::int(name="timeout")
let upstream = opt::group(name="upstream", [upstream_host, upstream_timeout])

let result = parse(args, ...)
let groups = result.get_groups(upstream)  // Array[ParseResult]
let host : String = groups[0].get(upstream_host).unwrap()
```

---

## ExactNode — 完全一致名マッチ + try_reduce【実装済み】

消費ループが走査するコアデータ構造。各 ExactNode は1つの完全一致名を持ち、名前がマッチしたら try_reduce を実行する。

```moonbit
pub(all) struct ExactNode {
  name : String                          // 完全一致名（例: "--verbose", "--no-verbose", "serve"）
  needs_value : Bool                     // true なら次の引数を値として消費
  try_reduce : (Array[String], Int) -> TryResult
  // 投機実行: args と現在位置を受け取り、マッチ判定 + 値検証を行う
  // Accept なら consumed 数と commit クロージャを返す
  reset : () -> Unit                     // initial 値にリセット（install_separator_node 等で使用）
}

pub(all) enum TryResult {
  Accept(consumed~ : Int, commit~ : () -> Unit)
  // 消費成功。commit() を呼ぶとクロージャ内の Ref[T] に書き込む
  Reject
  // 名前不一致、または値不一致（他の候補を試す）
  Error(ParseError)
  // 名前一致だが値不正（例: --port abc）。即座にエラー
}
```

### ExactNode の種類（コンビネータが生成する）

| 生成関数 | consumed | 用途 |
|---------|----------|------|
| `make_flag_node` | 1 | フラグ（名前のみマッチ） |
| `make_value_node` | 2 | 値オプション（名前 + 次の引数） |
| `make_choice_value_node` | 2 | choices の各候補（名前 + 値一致） |
| `make_implicit_flag_node` | 1 | implicit_value（名前のみで暗黙値） |
| `make_soft_value_node` | 2 or Reject | implicit 共存時の値ノード（値なしなら Reject） |
| `make_or_node` | 最大 | コンポジット（子ノードの最長一致） |
| `make_reduced_value_node` | 2 | reducer 経由の値ノード |

Design rationale (DR-012): ExactNode は完全一致名を持つフラットな構造。消費ループは単純な名前比較だけで済み、
--no-xxx やエイリアスはコンビネータ層で独立した ExactNode に展開される。
needs_value は install_eq_split_node と install_short_combine_node が参照し、
値を取る/取らないノードの区別に使用する。

---

## OptKind — ヘルプ生成用の種別区分【実装済み】

OptMeta.kind で区別される。消費ループの動作には影響しない（ExactNode と positionals の登録先で決まる）。ヘルプ生成時のセクション分けに使用。

```moonbit
pub(all) enum OptKind {
  Flag        // Bool フラグ / カウンタ
  ValueOpt    // 値を取るオプション（string_opt, int_opt, append_* 等）
  Command     // サブコマンド
  Positional  // 位置パラメータ
  Rest        // 可変長位置パラメータ
} derive(Show, Eq)
```

Design rationale: 旧設計の `Kind { Option, Command, Positional }` を拡張し、Flag/ValueOpt/Rest を追加。
ExactNode レベルでは kind は不要（try_reduce のクロージャが振る舞いを決定する）。
OptMeta.kind はヘルプ表示のセクション分け（Commands / Options / Global Options）にのみ使用される。
「ヘルプが従、コアが主」の原則に基づき、kind はコアの消費ロジックに影響しない。

---

## 引数消費ループ — parse コアアルゴリズム【実装済み】

### 概要

parse のコアは引数消費ループ（parse_raw）。ExactNode のフラットリストに対して最長一致マッチを行う。
OC/P のモード概念はなく、ExactNode 優先 + positional フォールバックの単純ループ。

### 遅延構築 — install ノード

特殊構文を通常の ExactNode に変換する install メソッドが、初期化時と parse_raw 冒頭の2段階で呼ばれる:

**初期化時（Parser::new / cmd）**:
1. **inject_help_node**: `--help` / `-h` を ExactNode として登録。HelpRequested エラーを返す。ユーザーが `name="help"` や `shorts="h"` を登録済みの場合、対応する built-in ノードをスキップ（衝突回避）
2. **install_separator_node**: `--` を ExactNode 化。残り args を positionals で serial 消費。`dashdash=true`（デフォルト）の場合に登録される

**parse_raw の冒頭**:
3. **validate_no_duplicate_names**: `expand_and_register` でバッチ間の名前重複を記録し、parse_raw 冒頭で重複名を検出してエラー
4. **install_eq_split_node**: `--name=value` 形式を分解する ExactNode を追加。consumed>=2 gate で implicit_value の誤マッチを防止
5. **install_short_combine_node**: `-abc` 等のショートオプション結合を分解する ExactNode を追加。value trial (needs_value=true, consumed>=2) → flag trial のフォールバック

これにより parse_raw のメインループから特殊分岐が完全に排除される（DR-017）。

### アルゴリズム — ExactNode 最長一致マッチ

```
0. parse_raw 冒頭:
   parsed ガード — 同一 Parser での2回呼び出しを禁止（DR-026）
   validate_no_duplicate_names() — 重複名を検出して ParseError を raise
   install_eq_split_node() — needs_value=true かつ "--" prefix のノードを収集し eq_node を構築
   install_short_combine_node() — "-X" 形式のショートノードを収集し combine_node を構築

1. メインループ（while pos < args.length）:
   全 ExactNode に対して try_reduce(args, pos) を呼ぶ:
   - Accept(consumed, commit) → 候補残留
   - Reject → 候補脱落
   - Error(e) → 即座に raise ParseError

2. Accept した候補のうち consumed が最大のものを選ぶ:
   2a. 最大 consumed が複数（ambiguous） → raise ParseError
   2b. 最大 consumed が1つ → 勝者確定 → commit() + pos += consumed
   2c. Accept した候補が0 → Positional フォールバック

3. Positional フォールバック（候補0の場合）:
   current_positional のインデックスでハンドラを呼ぶ
   is_rest=false なら消費後に次の positional に進む
   is_rest=true なら同じハンドラを繰り返し使用
   全 positional 消費済みなら raise ParseError("unexpected argument")

4. parsed フラグを true に設定

5. post_hooks を順に実行（値変換・遅延バリデーション）
```

### install_eq_split_node の詳細

`--name=value` を分解し、既存の value ノードに委譲する。

- needs_value=true かつ name が `--` で始まるノードを収集
- `=` の位置で name/value を分割し、`[name, value]` で各ノードの try_reduce を呼ぶ
- **consumed>=2 gate**: composite ノードが implicit (consumed=1) を返した場合は無視。値が消費されていないため
- 最長一致で勝者を選び、Accept(consumed=1) で返す（元の `--name=value` は1トークン）

### install_short_combine_node の詳細

`-abc` 等の結合ショートオプションを分解する。

1. `-X` 形式（長さ2、`-` prefix、`--` 非prefix）のノードを収集
2. 結合文字列を左から1文字ずつ走査
3. 各文字に対して:
   - **remaining がある場合**: まず value trial（needs_value=true のノードのみ、consumed>=2）→ 失敗なら flag trial（全ノード）
   - **remaining がない場合**: flag trial → 失敗なら外引数（args[pos+1]）で value trial
4. 全文字が消費できたら Accept(consumed=total)

Design rationale: 各 ExactNode が自分の消費可能性を自己判定できるため、ショートオプション結合の分解も
「各文字について matching ノードに try_reduce を呼ぶ」という均一なロジックで実現できる。

### スコープ遷移（cmd）

Command がマッチしたら:
- 子パーサの parse を残り args で再帰呼び出し（スコープ置換）
- `global=true` のノードは子パーサの nodes/global_nodes に伝播済み
- cmd の ExactNode は Accept(consumed=args.length()-pos) を返し、残り全てを子が消費

### 投機実行モデルの対応力（DR-015）

try_reduce の投機実行 + 最長一致モデルにより、他の汎用パーサでは対応困難なパターンも自然に処理できる:

- **ショートオプション結合の型情報分解**: `-vvv` → verbose=3(count)。install_short_combine_node が各文字を順に try_reduce
- **choices + implicit_value**: `--color` → "auto"(implicit), `--color=always` → "always"(choice)。make_or_node の最長一致で自然に解決
- **曖昧さ処理**: 最長一致で同 consumed なら ParseError(ambiguous)

核心: **各 ExactNode が自分の消費可能性を自己判定できる**ため、ショートオプション結合の分解も install ノード内での再帰適用として表現可能。詳細は DR-015 参照。

---

## サブコマンド・位置パラメータの具体的表現【実装済み】

### サブコマンドの表現

```moonbit
let p = Parser::new()
let verbose = p.flag(name="verbose", global=true)  // スコープ付きグローバル

let serve_cmd = p.cmd(name="serve", setup=fn(child) {
  let port = child.int_opt(name="port", default=8080)
  let host = child.string_opt(name="host", default="localhost")
  let dir = child.positional(name="DIR")
})

let deploy_cmd = p.cmd(name="deploy", setup=fn(child) {
  let target = child.string_opt(name="target", default="")
  let force = child.flag(name="force")
})

let result = try! p.parse(args)
verbose.get()                 // T? — global なのでどのスコープでも有効
result.child("serve")         // ParseResult? — サブコマンド結果
```

- 同一階層のサブコマンドは引数消費ループで常に1つに決まる。排他の仕組みは不要
- cmd の setup コールバックで子パーサを構築。子パーサは親の global_nodes を継承

**sub() — cmd のシュガー（DR-026）**:

```moonbit
// sub() は子 Parser を直接返す。Ref ラッパー不要
let clone = p.sub(name="clone", description="Clone a repo")
let url = clone.positional(name="url")
let depth = clone.int_opt(name="depth", default=0)
// parse 後: url.get(), depth.get()
```

**結果アクセスの3つの口（DR-013）**:
- `parser.get(opt) -> T?`: parse 前は `None`、parse 後は `Some(T)`
- `opt.get() -> T?`: cobra-style。Parser.parsed 経由
- `result.get(opt) -> T?`: parser.get(opt) に委譲
- `result.child("serve") -> ParseResult?`: サブコマンドの結果にナビゲーション
- `global=true` のノードは子パーサの nodes/global_nodes に伝播

### 位置パラメータの表現【実装済み】

```moonbit
let p = Parser::new()
// 固定長 positional
let file = p.positional(name="FILE")

// 可変長 rest（stop_before でトークン境界指定可）
let paths = p.rest(name="PATHS", stop_before=["--"])

// 組み合わせ: positional + rest（登録順で消費）
let src = p.positional(name="SRC")
let files = p.rest(name="FILES")
// → 最初の positional が SRC を消費、以降は FILES が繰り返し消費
```

positionals 配列の順番消費で実現。`is_rest=false` なら消費後に current_positional を進める。
`is_rest=true` なら同じハンドラを繰り返し使用。positional のハンドラは `--` prefix の引数を Reject する。

Design rationale: serial コンビネータは不要。positionals 配列の順番消費で同等の機能を実現。
中間 rest（rest の後に固定パラメータ）は将来検討。

### `--` (double dash) の表現【実装済み】

`--` は ExactNode として表現される（DR-017）。

**初期化時の自動登録**: `Parser::new(dashdash=true)` / `cmd(dashdash=true)` の初期化時に install_separator_node が `--` を ExactNode として自動登録（デフォルト ON）。`--` を検出したら残りの args を positionals で serial に消費する。

**コンビネータ（DR-018、実装済み）**:
- `p.dashdash(separator?="--", stop_before?=[])` → `Opt[Array[String]]`: セパレータ以降の全 args を収集
- `p.append_dashdash(separator?="--", stop_before?=[])` → `Opt[Array[Array[String]]]`: セパレータで区切った複数グループを収集
- カスタムセパレータ対応、append_dashdash の self-stop（自身のセパレータで自動グループ分割）
- stop_before パラメータで収集の終端トークンを指定可能
- ユーザーが dashdash()/append_dashdash() で Opt を取りたい場合は `dashdash=false` にして自分で呼ぶ

---

## defaults（置き換え方式）【未実装・設計のみ】

> **注意**: defaults のマルチソースマージは未実装。以下は設計案であり、実装時に変更される可能性がある。

各デフォルトソースは独立。各ソースごとに新しい Parser で parse し、最後に**明示指定のみ後勝ちマージ**する。

```
source1 (config):  --port 3000 --tags a --tags b
source2 (env):     --port 8080
CLI:               --tags c

→ merge（明示指定のみ後勝ち）:
→ port: 8080, tags: [c]
```

Design rationale: defaults は単純な「後勝ち」方式。各ソースごとに独立した結果を後勝ちで合成する。
現在の実装では各コンビネータの `default` パラメータで初期値を指定する方式と、
`default_fn` パラメータで動的デフォルト値を指定する方式がある。
`default_fn` 指定時は `default` より優先される。環境変数やランタイム検出等の動的デフォルト値に使用。

---

## OptMeta — ヘルプ生成用メタ情報【実装済み】

```moonbit
pub(all) struct OptMeta {
  kind : OptKind           // Flag | ValueOpt | Command | Positional | Rest
  name : String            // オプション名（"--" prefix なし）
  help : String            // ヘルプテキスト
  value_name : String      // 値のプレースホルダ（"PORT" 等）。空なら name の大文字化
  default_display : String // デフォルト値の表示文字列。空なら表示しない（custom[T : Show] では T.to_string() で自動導出）
  global : Bool            // global=true ならヘルプで "Global Options" セクションに表示
  shorts : Array[Char]     // ショートオプション（複数対応。例: ['v', 'V']）
  aliases : Array[String]  // エイリアス名のリスト
  hidden : Bool            // true ならヘルプに表示しない
}
```

Design rationale (DR-020): choices は OptMeta に持たない。コンビネータのパラメータとして受け取り、
ExactNode の生成時にクロージャにキャプチャされる。ヘルプ表示には custom() 内で help 文字列に
`[possible values: ...]` を付加する方式で対応（OptMeta.help に埋め込み）。OptMeta はヘルプ表示専用であり、
パースロジックに影響する情報（choices, implicit_value 等）はコアに持たせない。
visibility は `hidden: Bool` で十分。greedy フラグは不要（最長一致で自然解決）。
ShortEntry, AliasEntry は廃止し、`Array[Char]` と `Array[String]` に簡素化。

---

## 未解決・要検討事項

1. ~~**ユーザー API のインターフェース設計**~~ → **解決済み**: Parser メソッド方式を採用。`opts([...])` は不要
2. ~~**kind の区別のユーザー API 表現**~~ → **解決済み**: コンビネータ（flag, string_opt, int_opt, cmd 等）で暗黙決定
3. **completion の詳細設計** — 3段階カスタマイズ + CompleteCtx + CompletionCandidate は設計済み。シェル別出力形式の詳細は未着手
4. **ヘルプ生成の拡張** — 基本的なヘルプ生成は実装済み（Commands / Options / Global Options セクション）。3段階カスタマイズは未実装
5. **中間 rest 対応** — `mv file... dir` パターン。実装時期・優先度は未定
6. **パース後のリソース解放** — Parser/ParseResult/Opt がクロージャで相互参照を持つため、ユーザーが長期保持すると GC 回収されない。他のパーサライブラリでも共通の課題
7. ~~**choices のヘルプ表示**~~ → **解決済み**: custom() 内で help 文字列に `[possible values: ...]` を付加する方式で実装。OptMeta に choices フィールドを持たない設計を維持

### 設計原則（追加）

- **ヘルプが従、コアが主** — 表示用メタデータのためにコア設計を歪めない
- **既存パーツの組み合わせで考えよ** — 新フィールドや型を追加する前に、既存の型・クロージャの組み合わせで解決できないか検討する

### コア設計: Parser struct + getter 方式【実装済み】

**概要**: Parser struct がノード管理と状態を一元管理。Opt[T] は薄い参照型で getter クロージャで型消去を解決。

```moonbit
pub(all) struct Parser {
  next_id : () -> Int                    // ID 採番クロージャ（子パーサと共有）
  nodes : Array[ExactNode]              // ExactNode フラットリスト（名前付きオプション）
  global_nodes : Array[ExactNode]       // global=true のノード（子パーサに伝播）
  positionals : Array[((Array[String], Int) -> TryResult, Bool)]
                                         // 位置パラメータハンドラ + is_rest フラグ
  current_positional : Ref[Int]          // 次に消費する positional のインデックス
  parsed : Ref[Bool]                     // パース済みフラグ（opt.get() で参照）
  children : Map[String, ParseResult]    // サブコマンド名 → 子 ParseResult
  metas : Array[OptMeta]                // ヘルプ生成用メタ情報
  description : Ref[String]             // パーサの説明文（ヘルプ表示用）
  post_hooks : Array[() -> Unit raise ParseError]  // パース後フック
  registered_names : Map[String, Bool]   // 重複検出用
  duplicate_errors : Array[String]       // 遅延エラーメッセージ
}
```

**子パーサ方式（DR-012、実装済み）**:

サブコマンドのスコープ切替は子パーサの再帰呼び出しで実現する。

```moonbit
// cmd コンビネータ内部
let child = Parser::{
  next_id: self.next_id,           // ID 空間を共有
  nodes: [...self.global_nodes],   // 親の global ノードを継承
  global_nodes: [...self.global_nodes],
  // ... 他は新規作成
}
setup(child)  // ユーザーのセットアップコールバック
// コマンドマッチ時の try_reduce 内:
child.parse(remaining_args)
```

**API（実装済み）**:
```moonbit
let p = Parser::new()
let port = p.int_opt(name="port", default=8080)
let result = try! p.parse(args)
p.get(port)                          // T? — parse 後なら Some
port.get()                           // T? — cobra-style
result.get(port)                     // T? — parser.get(opt) に委譲
result.child("serve")                // ParseResult? — サブコマンドナビゲーション
```

**メリット**:
- Opt[T] は id + name + getter + parsed + is_set の5フィールド（薄い参照型）
- 値の格納は getter クロージャ内の Ref[T] に隠蔽
- Parser ローカル seq（next_id クロージャ）でテスト分離
- 子パーサが next_id を共有することで ID 空間が統一
- post_hooks でパース後の値変換・バリデーションを拡張可能

### 将来実装（優先度はその時の気分）

> **注意**: 以下は設計案であり、実装時に変更される可能性がある。

- **did you mean? サジェスト** — Levenshtein 距離によるスペルミス候補提示
- **エラーメッセージ品質** — 4層構造。既存最高峰以上を目指す（設計済み）
- **中間 rest 対応** — `mv file... dir` パターン
- **dependent options** — post_hooks ベースの制約チェック
- **リザルト取得サポート** — シンプル JSON 出力等
- **ヘルプ生成の拡張** — 3段階カスタマイズ（調査レポート: 2026-03-02-help-format-survey.md）
- **補完生成** — 3段階カスタマイズ + CompleteCtx + CompletionCandidate
- **@file 展開** — 引数前処理フック。gcc/javac 方式
- **環境変数連携** — 個別env / プレフィックス / auto-env の3方式（設計済み）
- **Visibility** — Visible/Advanced/Deprecated/Hidden の4段階（設計済み）
- **group** — 繰り返しオプション群。clone 方式（設計済み）
- ~~**custom** — ユーザー定義 reducer~~ → **実装済み**: `custom[T : Show]` — Show 制約により default_display を `T.to_string()` で自動導出。string_opt, int_opt は custom のシュガー
- **`get_or(T) -> T`** — `get().unwrap_or(default)` の糖衣。core の小さな DX 改善
- **多言語 DX レイヤー** — core は純粋関数ベースの薄いパースエンジンに留め、言語固有の型安全アクセスは各言語のイディオムで別レイヤー提供（DR-027）
  - MoonBit/Go: codegen で struct + 純粋関数を生成
  - TypeScript: union/infer/conditional types で型レベル解決
  - Rust: derive マクロ / Swift: property wrapper 等

---

## パースライフサイクル

### 現在の実装

```
引数入力 → [parsed ガード] → [validate_no_duplicate_names] → [install ノード構築] → [消費ループ] → [post_hooks]
```

| フェーズ | 責務 | 実装状況 |
|---------|------|---------|
| **parsed ガード** | 同一 Parser での2回呼び出し禁止（DR-026） | 実装済み（parse_raw 冒頭） |
| **validate** | 名前重複検証（validate_no_duplicate_names） | 実装済み（parse_raw 冒頭） |
| **install** | eq_split / short_combine ノードの構築 | 実装済み（parse_raw 冒頭） |
| **消費ループ** | ExactNode 最長一致マッチ + positional フォールバック | 実装済み |
| **post_hooks** | 値変換・遅延バリデーション（FilterChain の post 適用等） | 実装済み |

post_hooks は `Parser.post_hooks: Array[() -> Unit raise ParseError]` として実装されており、
string_opt の `post` パラメータで FilterChain を post_hooks に登録する仕組み。
将来の Validate/Finalize フェーズの実質基盤として機能する。

### 将来のパイプライン構想【未実装】

> **注意**: 以下は設計案であり、post_hooks ベースで段階的に実現可能。

```
引数入力 → [PreProcess] → [Reduce] → [Validate] → [Finalize] → [Output]
```

- **PreProcess**: `@file` 展開等の引数前処理
- **Reduce**: 消費ループ（現在の実装の中核）
- **Validate**: exclusive, requires 等の制約チェック → post_hooks で実装可能
- **Finalize**: デフォルト適用・環境変数連携 → post_hooks で実装可能
- **Output**: ヘルプ・補完・エラー表示

### CompletionCandidate【将来検討】

```moonbit
struct CompletionCandidate {
  value : String
  description : String?       // zsh/fish の説明表示
  group : String?             // zsh のグループ分け
  style : CompletionStyle?    // 警告色等
}
```

---

## 大統一設計の概念一覧

| 概念 | 表現 | 実装状況 |
|---|---|---|
| フラグ | `p.flag(name=...)` → `Opt[Bool]` | 実装済み |
| 値オプション | `p.string_opt(name=...)` / `p.int_opt(name=...)` → `Opt[T]` | 実装済み |
| カウンタ | `p.count(name=...)` → `Opt[Int]` | 実装済み |
| 配列蓄積 | `p.append_string(name=...)` / `p.append_int(name=...)` → `Opt[Array[T]]` | 実装済み |
| サブコマンド | `p.cmd(name=..., setup=fn)` → `Opt[Bool]` / `p.sub(name=...)` → `Parser`（子パーサ直接返却） | 実装済み |
| 位置パラメータ | `p.positional(name=...)` → `Opt[String]` | 実装済み |
| 可変長引数 | `p.rest(name=..., stop_before?=[])` → `Opt[Array[String]]` | 実装済み |
| `--` (double dash) | `p.dashdash()` / `p.append_dashdash()` | 実装済み |
| choices | `p.string_opt(choices=[...])` / `p.int_opt(choices=[...])` | 実装済み |
| implicit_value | `p.string_opt(implicit_value=...)` / `p.int_opt(implicit_value=...)` | 実装済み |
| コンポジットノード | `make_or_node` — 最長一致で統合 | 実装済み |
| スコープグローバル | `global=true` パラメータ | 実装済み |
| ショートオプション | `shorts="pP"` パラメータ（複数 short 対応） | 実装済み |
| エイリアス | `aliases=["alias"]` パラメータ | 実装済み |
| `--name=value` 分解 | `install_eq_split_node` | 実装済み |
| `-abc` 結合分解 | `install_short_combine_node` | 実装済み |
| `--` separator | `install_separator_node` | 実装済み |
| stop_before | rest/dashdash のトークン境界指定 | 実装済み |
| cobra-style アクセス | `opt.get() -> T?`（Parser.parsed 経由） | 実装済み |
| TryResult | Accept(consumed, commit) / Reject / Error | 実装済み |
| 先食い最長一致 | 全候補に try_reduce → consumed 最大を選択 → commit で確定 | 実装済み |
| 名前重複検証 | `validate_no_duplicate_names` — parse_raw 冒頭で重複名を検出してエラー | 実装済み |
| post_hooks | パース後の値変換・バリデーション | 実装済み |
| FilterChain | `FilterChain[A, B]` — `then` で Kleisli 合成 | 実装済み |
| Accumulator | `(T, U) -> T` — `make_reducer` で reducer に接続 | 実装済み |
| Lazy[T] | `Val(T)` / `Thunk(() -> T)` — 遅延評価可能な値 | 実装済み |
| ヘルプ生成 | `generate_help()` — Commands / Options / Global Options（shorts/aliases 表示対応） | 実装済み |
| hidden | `hidden=true` — ヘルプ非表示 | 実装済み |
| 結果保持 | `ParseResult`（階層ナビゲーション可能。child/at/get） | 実装済み |
| Variation | `Variation` enum — Toggle/True/False/Reset/Unset パターン | 実装済み |
| default_fn | 動的デフォルト値（環境変数、ランタイム検出等）。`default` より優先 | 実装済み |
| custom[T : Show] | `p.custom(name=..., pre=..., default=...)` — 汎用値オプション。Show 制約で default_display 自動導出 | 実装済み |
| sub() | `p.sub(name=...)` → `Parser` — cmd のシュガー（子パーサ直接返却、DR-026） | 実装済み |
| Opt::is_set() | 明示指定されたかどうかを判定 | 実装済み |
| Opt::name | オプション名フィールド（"--verbose" 等） | 実装済み |
| 排他オプション | `parser.exclusive(opts)` + `parser.at_least_one(opts)` | 実装済み |
| require_cmd | `parser.require_cmd()` — サブコマンド必須制約（DR-026） | 実装済み |
| 繰り返しグループ | `group(name, tmpl)` — 雛形 clone | 未実装 |
| 条件付きオプション | `requires=[...]` | 未実装 |
| 環境変数連携 | `env`, `env_prefix`, `auto_env` | 未実装 |
| 値のソース | `ValueSource` (Initial/Default/Environment/CommandLine) | 未実装 |
| Visibility | Visible/Advanced/Deprecated/Hidden | 未実装（hidden のみ実装） |
| 補完候補 | `CompletionCandidate` struct | 未実装 |

---

## 実装計画

### パッケージ構成（現在）

```
src/
  core/           # 全機能を統合（型定義 + コンビネータ + パースロジック + ヘルプ + フィルタ）
    types.mbt      # Opt[T], Parser, ExactNode, TryResult, OptMeta, Variation, Lazy[T] 等
    parser.mbt     # Parser::new, expand_and_register, wrap_node_with_set
    options.mbt    # flag, string_opt, int_opt, count, append_string, append_int
    nodes.mbt      # make_flag_node, make_value_node, make_or_node 等
    commands.mbt   # cmd, sub
    positionals.mbt # positional, rest
    dashdash.mbt   # dashdash, append_dashdash
    constraints.mbt # exclusive, required, require_cmd
    access.mbt     # Opt::get, ParseResult::get/child/at
    parse.mbt      # parse_raw, install_* ノード, validate_no_duplicate_names
    help.mbt       # generate_help, inject_help_node
    filter.mbt     # FilterChain, Filter::*, make_reducer, Accumulator
  wasm/            # WASM bridge（JSON schema → kuu core → JSON result）
    main.mbt        # kuu_parse エントリポイント、build_parser、extract_values
    test.mjs        # Node.js テスト（17ケース）
```

初期構想ではフェーズごとにパッケージ分割する予定だったが、MoonBit のパッケージ間依存制約により
`src/core/` に全機能を統合した。ファイル分割で責務を分離している。

---

### MVP フェーズ【実装完了】

#### Step 0-3: 基本パーサ【実装完了】

以下の全機能が `src/core/` に実装済み:

- **型定義**: Opt[T], Parser, ExactNode, TryResult, OptMeta, ParseResult, ParseResultKind, OptKind, Lazy[T], Variation, ReduceCtx[T], ReduceAction, FilterChain[A, B], Accumulator[T, U], ParseError, ParseErrorInfo
- **コンビネータ**: flag, string_opt, int_opt, count, append_string, append_int, custom[T : Show], custom_append[T], positional, rest, cmd, sub, dashdash, append_dashdash
- **パースロジック**: parse_raw（validate_no_duplicate_names + メインループ + post_hooks）、install_eq_split_node, install_short_combine_node, install_separator_node
- **ヘルプ生成**: generate_help（Commands / Options / Global Options セクション）、inject_help_node（--help / -h 自動登録）
- **フィルタ**: FilterChain::then, Filter::map/validate/parse, trim/to_lower/non_empty/split/parse_int/parse_float/in_range/one_of/each, make_reducer
- **テスト**: 730/730 passed

#### 計画外の追加実装（MVP 完了後）

- **choices**: string_opt に choices パラメータ追加。make_choice_value_node + one_of バリデーション
- **implicit_value**: string_opt/int_opt に implicit_value パラメータ追加。make_or_node による composite ノード構築
- **stop_before**: rest/dashdash に stop_before パラメータ追加
- **short option**: flag/string_opt/int_opt/count/append_string/append_int に shorts パラメータ追加（`shorts="vV"` で複数 short 対応。OptMeta.shorts : Array[Char]）
- **aliases**: flag/string_opt/int_opt/count/append_string/append_int に aliases パラメータ追加
- **global**: flag/string_opt/int_opt/count/append_string/append_int に global パラメータ追加
- **hidden**: 全コンビネータに hidden パラメータ追加
- **post hooks**: string_opt/int_opt に post パラメータ（FilterChain）追加
- **make_reducer**: FilterChain + Accumulator → reducer の自動生成
- **sub()**: cmd のシュガー。`p.sub(name=...)` で子 Parser を直接返却（Ref ラッパー不要、DR-026）
- **Variation**: Toggle/True/False/Reset/Unset パターン。expand_and_register で展開
- **default_fn**: flag/string_opt/int_opt に動的デフォルト値パラメータ追加。default より優先
- **名前重複検証**: validate_no_duplicate_names + expand_and_register での記録
- **Opt::is_set()**: 明示指定されたかどうかを判定
- **Opt::name**: オプション名フィールド
- **exclusive/at_least_one**: 排他オプション制約（post_hooks ベース）
- **require_cmd**: サブコマンド必須制約（post_hooks ベース）
- **custom[T : Show]**: 汎用値オプションコンビネータ。Show 制約で default_display を `T.to_string()` で自動導出。string_opt, int_opt は custom のシュガー
- **default_display 自動導出**: `default_display? : String? = None` → None 時は Show 制約で自動導出。int_opt の「default=0 なら非表示」特殊処理は廃止
- **shorts 複数対応**: `short? : Char` → `shorts? : String = ""` に変更。`shorts="vV"` で `-v` と `-V` の両方が動作。OptMeta.shorts : Array[Char]
- **int_opt に post/choices 追加**: string_opt と同等の機能を custom へのパススルーで提供
- **help に aliases/shorts 表示**: ヘルプ出力に aliases と複数 shorts を表示（例: `-v, -V, --verbose, --verb`）
- **choices のヘルプ表示**: custom() 内で help 文字列に `[possible values: ...]` を付加。OptMeta に choices フィールドを持たない設計を維持
- **inject_help_node 衝突回避**: ユーザーが `name="help"` や `shorts="h"` を登録済みの場合、対応する built-in の `--help` / `-h` ノードをスキップ
- **shorts バリデーション**: parser.mbt の expand_and_register で `-`、空白（スペース/タブ/改行/CR）、NUL 文字を拒否
- **WASM bridge**: `src/wasm/` に実装。JSON schema + args → kuu core (WASM) → JSON result。スキーマバージョニング (`version: 1`)、入力バリデーション（不正JSON、非Object、非配列等をエラー）。テスト17ケース

---

### 拡張フェーズ（今後の実装予定）

> **注意**: 以下は設計案である。post_hooks ベースで段階的に実現可能。

#### Step 4: 制約チェック（post_hooks ベース）【実装済み】

- `parser.exclusive(opts)` — 排他オプション【実装済み】
- `parser.at_least_one(opts)` — 最低1つ必須【実装済み】
- `parser.require_cmd()` — サブコマンド必須制約【実装済み】

Design rationale: 専用のフックパイプライン基盤は YAGNI。post_hooks で十分実現可能。

#### Step 5: defaults マルチソース

- 環境変数連携: `env`, `env_prefix`, `auto_env`
- ValueSource トラッキング
- 各ソースごとに独立パース → 後勝ちマージ

#### Step 6: エラーメッセージ品質

- 4層構造（error / Help 行 / tip / Usage）
- did you mean? サジェスト
- ParseError の構造化（ErrorKind enum）

#### Step 7: ヘルプ生成の拡張

- 3段階カスタマイズ（Level 0: 自動 / Level 1: 部分フック / Level 2: 全面差し替え）
- ~~choices のヘルプ表示~~ **実装済み**: custom() 内で help 文字列に `[possible values: ...]` を付加

#### Step 8: 補完生成

- シェル別出力形式（bash/zsh/fish）
- CompletionCandidate
- 3段階カスタマイズ

#### Step 9: 拡張コンビネータ

- `group(name, tmpl)` — 繰り返しグループ
- `custom(fn)` — ユーザー定義 reducer
- ~~`never()` — センチネルノード~~ **実装済み**
- ~~`serial` — positionals 配列の順番消費~~ **実装済み**

### テスト方針

TDD（t_wada 流）を実践:

1. 要件からテストを書く（RED）
2. 実装する（GREEN）
3. リファクタ
4. `moon test -u` でスナップショットテスト活用
5. `moon test` で全テスト通過確認

---

## エラーメッセージ設計【将来検討】

> **注意**: 現在は `ParseErrorInfo { message, help_text }` の簡易実装のみ。以下は目標設計案。

### 出力構造

clap の4層構造を採用し、Swift ArgumentParser の Help 行を追加:

```
error: unknown option '--prot'
  Help: --port <PORT>    ポート番号を指定 [default: 8080]
  tip: a similar option exists: '--port'
Usage: myapp serve [OPTIONS] <DIR>
For more information, try '--help'.
```

### サジェスト

- Levenshtein 距離ベースの did-you-mean（オプション名・サブコマンド名の両方）
- bpaf 式のコンテキスト認識: "not expected in this context"（スコープ外のオプション検出）

### セマンティックスタイリング

5カテゴリで出力を装飾（ターミナル対応時）:

| カテゴリ | 用途 | 例 |
|---------|------|-----|
| error | エラーラベル | `error:` |
| valid | 正しい部分 | `myapp serve` |
| invalid | 問題の部分 | `--prot` |
| literal | リテラル値 | `'--port'` |
| hint | 提案・補足 | `tip:`, `Help:` |

### ParseError 設計

```moonbit
enum ParseError {
  Usage(ErrorKind, String, ErrorContext)  // ユーザー起因エラー
  Internal(String)                        // パーサ内部エラー
}

enum ErrorKind {
  UnknownOption; UnexpectedArgument; MissingRequired; InvalidValue
  ArgumentConflict; AmbiguousMatch; MissingValue; TooManyValues
  MissingSubcommand; PositionalAsFlag; MultipleUse
}
```

### 実装優先度

1. **初期**: 基本エラー + 1行メッセージ（ErrorKind + メッセージ）
2. **中期**: 4層構造 + Help 行 + did-you-mean サジェスト
3. **後期**: セマンティックスタイリング + カスタマイズ API

---

## リザルト取得・構造化出力【将来検討】

> **注意**: 以下は未実装の設計案。

### ValueSource

パース結果の値がどのソースから来たかを追跡:

```moonbit
enum ValueSource {
  Initial         // Opt 定義時の initial 値（未指定）
  Default(String) // default ソース名（"config", "profile" 等）
  Environment     // 環境変数から
  CommandLine     // CLI 引数から
}
```

### API

```moonbit
parser.get(opt)         // -> T?       parse 前は None、parse 後はスコープ内なら Some
opt.get()               // -> T?       cobra-style（Parser.parsed 経由）
result.get(opt)         // -> T?       ParseResult からアクセス
result.child("serve")   // -> ParseResult?  サブコマンドナビゲーション
result.at(0)            // -> ParseResult?  ポジショナルナビゲーション
result.source(opt)      // -> ValueSource  値のソースを取得
result.is_explicit(opt) // -> Bool     Initial/Default 以外なら true
```

### 構造化出力

```moonbit
// 全パース結果をフラット列挙（JSON 等のシリアライズはユーザー側）
result.to_entries()  // -> Array[(String, String, ValueSource)]
                     //    (name, value_str, source)
```

### サブコマンドディスパッチ

- **プライマリ**: callback 方式（cmd 定義時にハンドラ登録）
- **セカンダリ**: `result.command()` で手動分岐

### defaults 優先順位（viper 参考）

```
CLI > 環境変数 > 設定ファイル > initial
```

各ソースごとに独立した Parser で parse し、後勝ちマージ（前述の defaults 設計と整合）。

---

## Mutual Exclusion（排他オプション）【実装済み】

基本的な排他制約は `parser.exclusive(opts)` と `parser.at_least_one(opts)` で実装済み。
以下は当初の設計案と追加検討事項。

同時に使えないオプション群を宣言する。

```moonbit
let json = opt::flag(name="json")
let csv = opt::flag(name="csv")
let yaml = opt::flag(name="yaml")

// 最大1つ（どれも指定しなくてもOK）
let format = exclusive([json, csv, yaml])

// ちょうど1つ（必須）
let format = exclusive([json, csv, yaml], required=true)
```

### バリデーションタイミング

- **消費時**: 同グループの別オプションが既に消費済みなら即 `ParseError(Exclusive)`（早期確定）
- エラー: `error: --csv cannot be used with --json`

### exclusive の戻り値

`exclusive()` はバリデーション制約を Parser に登録するだけ。各 Opt の値は個別に `parser.get(json)` 等で取得する。

---

## Dependent Options（条件付きオプション）【将来検討】

> **注意**: 以下は未実装の設計案。post_hooks ベースで実現可能。

あるオプションが別のオプションの存在・値に依存する関係を宣言する。

```moonbit
let ssl = opt::flag(name="ssl")
let ssl_cert = opt::string(name="ssl-cert", requires=[ssl])

let format = opt::string(name="format", choices=["json", "csv", "tsv"])
// 簡易: 文字列一致
let delimiter = opt::string(name="delimiter", requires=[Require(format, value="csv")])
// カスタム述語: T が String とは限らないケースにも対応
let delimiter = opt::string(name="delimiter", requires=[RequireWhen(format, fn(v) { v != "json" })])
```

### バリデーションタイミング

- **基本は finalize 時**: まだ入力途中かもしれないので、全引数消費後にチェック
- **早期確定可能なケース**: 消費時点で依存先の値が確定済みなら早期エラーも可
- エラー: `error: --delimiter requires --format=csv`

### 補完連携

- `--delimiter` 補完時に依存元 `--format csv` が未指定なら description に警告表示
- 依存元が一意（`--format csv` のみ）なら自動展開も検討

### ReduceCtx 経由の途中参照

dependent options の reducer 内で依存先の値を参照可能:

```moonbit
let delimiter = opt::custom(
  name="delimiter",
  initial=",",
  reducer=fn(ctx) {
    // format の現在値を参照して挙動を変える
    let fmt = ctx.get(format)
    match (ctx.action, fmt) {
      (Value(Some(s)), Some("csv")) => Some(s)
      (Value(_), _) => raise ParseError::DependencyNotMet("--delimiter requires --format=csv")
      _ => None
    }
  },
)
```

---

## 環境変数連携【将来検討】

> **注意**: 以下は未実装の設計案。

### 3つの方式

**1. 個別指定**: 特定のオプションに環境変数を明示バインド

```moonbit
let port = opt::int(name="port", env="PORT")
// PORT=8080 → port の値が 8080 に
```

**2. プレフィックス連結**: コマンドのプレフィックスと個別 env を結合

```moonbit
let app = cmd("myapp", env_prefix="MYAPP")
let port = opt::int(name="port", env="PORT")  // → MYAPP_PORT を参照
```

**3. auto-env**: 全フラグを自動バインド（デフォルト無効）

```moonbit
let app = cmd("myapp", env_prefix="MYAPP", auto_env=true)
let port = opt::int(name="port")      // → MYAPP_PORT を自動参照
let verbose = opt::flag(name="verbose") // → MYAPP_VERBOSE を自動参照
```

### サブコマンドのプレフィックスネスト

```
myapp serve --port 8080
→ MYAPP_SERVE_PORT
```

### オーバーライド

env でフルパス指定すればプレフィックスを無視:

```moonbit
let port = opt::int(name="port", env="CUSTOM_PORT")
// env_prefix="MYAPP" でも MYAPP_PORT ではなく CUSTOM_PORT を参照
```

### Opt レベルの auto-env 制御

auto-env は Parser/Cmd レベルだけでなく、各 Opt で `auto_env : Bool?` により個別に制御可能:

```moonbit
let app = cmd("myapp", env_prefix="MYAPP", auto_env=true)
let port = opt::int(name="port")                           // None → 親に従う（MYAPP_PORT）
let secret = opt::int(name="secret-key", auto_env=false)   // false → auto-env 無効
let debug = opt::flag(name="debug", auto_env=true)         // true → 親が auto_env=false でも有効
```

- `None`（デフォルト）: 親 Cmd の設定を継承
- `Some(true)`: この Opt は auto-env 有効（親が無効でも）
- `Some(false)`: この Opt は auto-env 無効（親が有効でも）

オプションスコープが明確に管理されるため、Opt 単位での粒度制御が自然に実現できる。

### 安全性

- auto-env はデフォルト無効（Cmd で明示的に `auto_env=true` が必要）
- Opt レベルの `auto_env=false` で内部フラグの環境変数への漏洩を個別に防止
- `visibility` 属性との連動: help/補完で非表示のオプションは auto-env も自動 Off（明示 `true` で上書き可）

---

## Visibility — ヘルプ・補完の表示制御【将来検討】

> **注意**: 現在は `hidden: Bool` のみ実装。以下の4段階 Visibility は未実装の設計案。

Opt / Cmd に設定する表示レベル。手入力すれば全て動作する（visibility はあくまで発見性の制御）。

```
enum Visibility {
  Visible      // デフォルト
  Advanced     // help ✗, 補完 ✓（パワーユーザー向け）
  Deprecated   // help ✓（deprecated 注記）, 補完 ✗
  Hidden       // help ✗, 補完 ✗
}
```

| | help | help-all | 補完 | 手入力 |
|--|------|----------|------|--------|
| Visible | ✓ | ✓ | ✓ | ✓ |
| Advanced | ✗ | ✓ | ✓ | ✓ |
| Deprecated | ✓ (注記) | ✓ (注記) | ✗ | ✓ (警告) |
| Hidden | ✗ | ✓ | ✗ | ✓ |

### help-all

Parser レベルで `help_all=true` を有効にすると `--help-all` フラグが自動追加される。
指定時は Hidden/Advanced を含む全エントリをヘルプに表示（git の全サブコマンド表示と同パターン）。

### ショート別名の扱い

ショート別名（`-p` 等）は独立した Opt ではなく、ロングオプションのヘルプ行に `-p, --port` と併記される。
補完に出さないのは標準的な挙動であり、visibility 設定の対象外。

### deprecated 別名の扱い

`aliases` に `deprecated=true` を付けた別名はヘルプに deprecated 注記付きで表示、補完には出さない。
手入力時は動作するが「`--old-name` is deprecated, use `--new-name`」の警告を出す。

### auto-env との連動

- `Hidden` / `Advanced` → auto-env デフォルト Off（`auto_env=true` で明示上書き可）
- `Visible` / `Deprecated` → 親 Cmd の auto-env 設定に従う

---

## プロジェクト構成

現在は `src/core/` に全機能を統合。ファイル分割で責務を分離。`src/wasm/` に WASM bridge:

```
src/core/
  types.mbt            # 型定義（Opt, Parser, ExactNode, TryResult, OptMeta, Variation, Lazy[T] 等）
  parser.mbt           # Parser::new, expand_and_register, wrap_node_with_set
  options.mbt          # flag, string_opt, int_opt, count, append_string, append_int
  nodes.mbt            # make_flag_node, make_value_node, make_or_node 等
  commands.mbt         # cmd, sub
  positionals.mbt      # positional, rest
  dashdash.mbt         # dashdash, append_dashdash
  constraints.mbt      # exclusive, required, require_cmd
  access.mbt           # Opt::get, ParseResult::get/child/at
  parse.mbt            # parse_raw, install_* ノード, validate_no_duplicate_names
  help.mbt             # generate_help, inject_help_node
  filter.mbt           # FilterChain + make_reducer
  filter_wbtest.mbt    # フィルタテスト
  parse_wbtest.mbt     # パーサテスト（730件）
src/wasm/
  main.mbt             # WASM bridge: kuu_parse（JSON schema + args → JSON result）
  test.mjs             # Node.js テスト（17ケース）
examples/
  mygit/               # 初期版 git CLI モック
  20260307-mygit/      # 旧 API 保存版
  20260308-mygit/      # 最新 API 版 git CLI モック（全機能網羅）
  20260308-mydocker/   # Docker CLI モック
  20260309-kubectl/    # kubectl CLI モック（DR-031）
```

### サンプル一覧

| サンプル | モデル | 主な検証対象 |
|---|---|---|
| 20260308-mygit | git | 全機能網羅: serial, append_*, variation_*, hidden, default_fn 等 |
| 20260308-mydocker | docker | 深いネスト (docker compose up 等) |
| 20260309-kubectl | kubectl | `-f` のサブコマンド別バインド, dashdash, choices, default=true フラグ |
