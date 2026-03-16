> **Archive**: 2026-02-27 にアーカイブ。String ベース中間表現 + `Map[String, Array[String]]` の
> ParseResult 方式の旧設計。`&Trait` (trait object) による Opt ツリー直接保持方式に移行したため置き換え。

# Phase 4: Reducer 大統一設計

type: decision

## Context

Design Record セクション 9-18 で確立した Reducer パターンを MoonBit で実装する。
Phase 1-3 の PoC は「テストケース = 要件」として引き継ぐが、コードは全削除して完全作り直し。

核心: `Opt[T] { reduce: (ReduceContext, ReduceAction) -> Array[String] }` で
Flag/Single/Append/Count/OptionalValue を統一し、OptKind enum を廃止する。
ReduceContext に初期値・デフォルト値・明示設定フラグ等のコンテキストを持たせ、
反転（`--no-xxx`）のリセット戦略も Append の replace semantics も
**全て reducer の内部判断** に閉じ込める。パーサコアはコンテキストを渡すだけ。

### 検証済み事項

- MoonBit v0.1.20260209 で `&Trait` (trait object) はネイティブサポート
  - `Array[&Trait]` で heterogeneous collection 可能
  - object-safe 条件: Self がメソッドの第1引数のみに出現
- Design Record の「trait object なし」は古い情報。現在は使える

### 設計原則（Design Record より）

- `Opt[T]` は immutable で値を保持しない — 定義情報と変換ロジックのみ
- `apply_defaults` は純粋関数 — 入力を変更せず新しい配列を返す
- パーサコアは `Array[String]` を受け取り `ParseResult` を返す環境非依存の純粋関数

---

## 二層構造

```
[ユーザー API]  Opt[T] { initial, reduce, arity, meta, extract }
                ↓ to_erased() で型消去
[パーサコア]    Array[&ErasedOpt] → parse() → ParseResult (String ベース)
                ↑ Opt[T].get(result) で型安全に取り出し
```

---

## 型定義

### ReduceAction — reducer への入力

```moonbit
/// reducer に渡すアクション
pub(all) enum ReduceAction {
  /// 正方向: 値を消費（Flag/Count は None、Single/Append は Some(value)）
  Value(String?)
  /// 反転: --no-xxx が来た。リセット戦略は reducer の責務
  Negate
} derive(Eq, Show, Debug)
```

### ReduceContext — reducer へのコンテキスト

```moonbit
/// reducer に渡すコンテキスト（String ベース）
/// parse/apply_defaults がコンテキストを構築し、reducer はこれを参照して判断する
pub(all) struct ReduceContext {
  /// 現在の蓄積値
  value : Array[String]
  /// Opt 構築時の初期値（Negate リセット先、Append replace 判定基準）
  initial : Array[String]
  /// apply_defaults で畳み込まれたデフォルト値（parse 時のみ有効、apply_defaults 時は None）
  defaults : Array[String]?
  /// 今回の parse/apply_defaults でこのオプションに値が明示的に設定されたか
  explicitly_set : Bool
} derive(Eq, Show, Debug)
```

Design rationale: reducer の第1引数を単なる `Array[String]`（現在値のみ）から
`ReduceContext`（初期値・デフォルト・明示設定フラグ含む）に拡張することで、
**全ての戦略判断が reducer 内部に閉じ込められる**:

1. **Negate**: `ctx.initial` を返す（リセット先を知っている）
2. **Append replace semantics**: `!ctx.explicitly_set && ctx.defaults.is_some()` なら
   defaults を破棄して initial から再蓄積（reducer が自分で判断）
3. **apply_defaults の stacking**: `ctx.defaults` が None なので常に追加

これにより parse ループは完全にオプション種別に無知でいられる。
`is_accumulator` フラグも不要になる。

### 各 reducer の ReduceContext + ReduceAction 対応

| 種別 | Value(None) | Value(Some(s)) | Negate |
|------|------------|----------------|--------|
| Flag | `["true"]` | — | `ctx.initial` |
| Count | `[...ctx.value, "1"]` | — | `ctx.initial` |
| Single | — | `[s]` | `ctx.initial` |
| Append | — | 初回+defaults有→`[s]`, 他→`[...ctx.value, s]` | `ctx.initial` |
| OptionalValue | `[implicit]` | `[s]` | `ctx.initial` |

Append の初回判定: `!ctx.explicitly_set && ctx.defaults.is_some()`
→ true なら defaults を捨てて `[s]` で開始（replace semantics）
→ false なら `[...ctx.value, s]` で追加（stacking semantics / 2回目以降）

### InitialValue[T] — 初期値の即値/遅延評価

```moonbit
/// 初期値を即値またはサンクで保持する
pub(all) enum InitialValue[T] {
  Val(T)
  Thunk(() -> T)
}

pub fn resolve[T](self : InitialValue[T]) -> T {
  match self {
    Val(v) => v
    Thunk(f) => f()
  }
}
```

ユーザー API は `initial~` と `initial_fn~` の labeled argument で提供:

```moonbit
// 即値（大半のケース）
let port = int_opt(long="port", initial=8080)

// 遅延評価（ランタイム依存の値、重い計算等）
let port = int_opt(long="port", initial_fn=fn() { read_config_port() })
```

Design rationale: 初期値がランタイム依存（環境変数、設定ファイル等）の場合、
定義時ではなく必要になった時に評価したい。`Val(T) | Thunk(() -> T)` で
即値と遅延評価を統一的に扱い、ユーザー API は labeled argument で自然に切り替え可能にする。

`initial_raw : Array[String]` も同様に `InitialValue[Array[String]]` とし、
`ErasedOpt.initial_raw()` 呼び出し時に resolve する。

### ErasedOpt — 型消去インターフェース（trait object）

```moonbit
/// パーサコアが扱う型消去済みインターフェース
/// object-safe: Self は第1引数のみ
pub(open) trait ErasedOpt {
  meta(Self) -> OptMeta
  arity(Self) -> Int
  is_optional_value(Self) -> Bool
  /// 初期値（String ベース）
  initial_raw(Self) -> Array[String]
  /// reducer を適用し、新しい値を返す（純粋関数）
  /// ReduceContext にコンテキスト一式を渡し、全判断を reducer に委譲
  reduce_raw(Self, ReduceContext, ReduceAction) -> Array[String] raise ParseError
}
```

### 内部表現 — String ベース

```moonbit
/// パース結果の内部値（String ベース）
/// Map[String, Array[String]] で全種類を統一
/// - Flag: ["true"] or ["false"]
/// - Count: ["1", "1", "1"]（出現回数 = length）
/// - Single: ["value"]（後勝ち）
/// - Append: ["v1", "v2", ...]
/// - OptionalValue: Single と同じ
```

Design rationale: Design Record の「内部は String ベースを維持」に従う。
ParsedRaw enum を使わず、全て `Array[String]` に統一する。
`custom[T]` も問題なし — 内部は String のまま、extract が String → T に変換する。

### Opt[T] — 型付きオプション定義（immutable、値を保持しない）

**reduce は String ベースで動く。T は取り出し時のみ関係する。**

```moonbit
pub struct Opt[T] {
  /// 初期値（型安全なユーザー API 用、即値または遅延評価）
  initial : InitialValue[T]
  /// このオプションが消費するトークン数
  arity : Int
  /// OptionalValue フラグ
  optional_value : Bool
  /// メタ情報
  meta : OptMeta
  /// ParseResult から T を取り出す（custom は raise する可能性あり）
  extract : (ParseResult) -> T raise ParseError
  /// 初期値の String 表現（即値または遅延評価）
  initial_raw : InitialValue[Array[String]]
  /// String ベースの reducer（ReduceContext で全コンテキストを受け取る）
  reduce_raw : (ReduceContext, ReduceAction) -> Array[String] raise ParseError
}
```

Design rationale: `T` が登場するのは `initial` と `extract` のみ。
reducer は String ベースで直接動作するため:
1. `to_raw`/`from_raw` の往復が不要 → `custom[T]` の逆変換問題が消える
2. ErasedOpt impl は単純なデリゲーション
3. 全ての戦略判断は ReduceContext を参照して reducer 内部で完結

### OptMeta — メタ情報

```moonbit
pub(all) struct OptMeta {
  long : String
  help : String
  shorts : Array[ShortEntry]
  aliases : Array[AliasEntry]
  inversion : FlagInversion?
  env : String?
  choices : Array[String]
  value_name : String
  required : Bool
  visibility : Visibility
} derive(Eq, Show, Debug)
```

### ParseResult — パース結果（String ベース）

```moonbit
pub(all) struct ParseResult {
  /// 全オプションの値を String ベースで保持
  values : Map[String, Array[String]]
  positional : Array[String]
  rest : Array[String]
  /// Append(n>1) の chunk サイズ記録
  chunk_sizes : Map[String, Int]
} derive(Eq, Show, Debug)
```

### 補助型

FlagInversion, Visibility, AliasEntry, ShortEntry, HelpSection, ParseError は
Design Record の定義をそのまま使用。

### Opt[T] → &ErasedOpt への変換

```moonbit
impl[T] ErasedOpt for Opt[T] with meta(self) { self.meta }
impl[T] ErasedOpt for Opt[T] with arity(self) { self.arity }
impl[T] ErasedOpt for Opt[T] with is_optional_value(self) { self.optional_value }
impl[T] ErasedOpt for Opt[T] with initial_raw(self) { self.initial_raw }
impl[T] ErasedOpt for Opt[T] with reduce_raw(self, ctx, action) {
  (self.reduce_raw)(ctx, action)  // 単純なデリゲーション
}
```

使用:
```moonbit
let verbose : Opt[Bool] = flag(long="verbose", help="V")
let port : Opt[Int?] = int_opt(long="port", help="P")
let opts : Array[&ErasedOpt] = [verbose as &ErasedOpt, port as &ErasedOpt]
```

---

## コンビネータ関数群

### 各コンビネータのシグネチャ

```moonbit
pub fn flag(long~ : String, help~ : String, ...) -> Opt[Bool]
pub fn string_opt(long~ : String, help~ : String, ...) -> Opt[String?]
pub fn int_opt(long~ : String, help~ : String, ...) -> Opt[Int?]
pub fn count(long~ : String, help~ : String, ...) -> Opt[Int]
pub fn append(long~ : String, help~ : String, ...) -> Opt[Array[String]]
pub fn optional_value(long~ : String, help~ : String, implicit~ : String, ...) -> Opt[String?]
pub fn custom[T](long~ : String, help~ : String, parser~ : (String) -> T raise ParseError, ...) -> Opt[T?]
```

### reduce_raw の実装パターン（各コンビネータ共通）

各コンビネータは構築時に `reduce_raw: (ReduceContext, ReduceAction) -> Array[String]` を定義:

```moonbit
// Flag の reduce_raw
fn(ctx, action) {
  match action {
    Value(None) => ["true"]
    Negate => ctx.initial     // ["false"] — 初期値にリセット
    _ => ctx.value            // 不正アクションは現在値維持
  }
}

// Append の reduce_raw — replace semantics を自己判断
fn(ctx, action) {
  match action {
    Value(Some(s)) => {
      // CLI parse 時、defaults あり、初回設定 → replace（defaults 破棄）
      let base = if !ctx.explicitly_set && ctx.defaults.is_some() {
        []  // defaults を捨てて空から開始
      } else {
        ctx.value
      }
      Array::concat(base, [s])
    }
    Negate => ctx.initial     // [] — 初期値にリセット
    _ => ctx.value
  }
}
```

### Opt[T].get — 型安全な取り出し

```moonbit
pub fn[T] Opt::get(self : Opt[T], result : ParseResult) -> T raise ParseError {
  (self.extract)(result)
}
```

extract は各コンビネータが構築時に定義。
内部 `Array[String]` → `T` の変換を行う:
- flag: `["true"]` → `true`, `["false"]` → `false`
- string_opt: `[s]` → `Some(s)`, `[]` → `None`
- int_opt: `[s]` → `Some(parse_int(s))`（ここで raise 可能）
- count: `arr` → `arr.length()`
- append: `arr` → `arr`（そのまま）
- custom: `[s]` → `Some(parser(s))`（ここで raise 可能）

---

## 名前解決 (resolve)

```moonbit
pub(all) enum ResolveDirection { Normal; Inverted } derive(Eq, Show, Debug)
pub(all) struct ResolveResult { index : Int; direction : ResolveDirection } derive(Eq, Show, Debug)

pub fn resolve_long(opts : Array[&ErasedOpt], name : String) -> ResolveResult raise ParseError
pub fn resolve_short(opts : Array[&ErasedOpt], char : Char) -> ResolveResult raise ParseError
```

ロジック: opts.meta().long → エイリアス → 反転パターン の順にマッチ。旧実装と同じアルゴリズム。

---

## parse（コアロジック）

### OptKind match の廃止 → arity + ReduceContext + reduce_raw による統一処理

```moonbit
/// defaults を指定可能な parse（apply_defaults との接続口）
/// defaults が None の場合は各 opt の initial_raw() を使用
pub fn parse(
  opts : Array[&ErasedOpt],
  args : Array[String],
  defaults~ : Map[String, Array[String]]? = None,
) -> ParseResult raise ParseError
```

内部フロー:
1. `tokenize(args)` で字句解析
2. 初期化:
   - `values : Map[String, Array[String]]` — defaults or initial_raw() で初期化
   - `explicitly_set : Map[String, Bool]` — 全て false
3. トークン列を順に処理。**各 reduce_raw 呼び出しで ReduceContext を構築**:

```
resolve で名前解決 → (index, direction) を取得

// ReduceContext を構築（全オプション共通）
let ctx = ReduceContext {
  value: values[long],
  initial: opt.initial_raw(),
  defaults: defaults.and_then(fn(d) { d.get(long) }),  // parse 時のみ有効
  explicitly_set: explicitly_set[long],
}

// アクション判定と reduce_raw 呼び出し
//
// トークン種別と arity の組み合わせで処理分岐:
//
// LongOptWithValue("key", "val"):
//   direction==Inverted → Negate（=value は無視 — DR仕様）
//   arity==0 && !optional → Flag: Value(Some("val"))
//     ※ Flag reducer は Value(Some("true"/"false")) を処理、それ以外は choices エラー
//   arity==0 && optional → OptionalValue: Value(Some("val"))
//   arity>=1 → Single/Append: Value(Some("val"))（=形式で1個目の値を取得）
//
// LongOpt("key"):
//   direction==Inverted → Negate
//   arity==0 && !optional → Flag/Count: Value(None)
//   arity==0 && optional → OptionalValue: Value(None)（暗黙値使用）
//   arity>=1 → 次トークンを consume
//
// ShortOpts: 別途 ShortOpts 処理セクション参照

if direction == Inverted:
  values[long] = opt.reduce_raw(ctx, Negate)

else:
  match token {
    LongOptWithValue(_, v) =>
      // =value 形式: arity に関わらず v を値として渡す
      values[long] = opt.reduce_raw(ctx, Value(Some(v)))

    LongOpt(_) =>
      if arity == 0:
        // Flag/Count/OptionalValue: 値を消費しない
        values[long] = opt.reduce_raw(ctx, Value(None))
      else:
        // Single/Append: arity 個のトークンを消費
        for j in 0..<arity:
          let v = consume_next(tokens, i)
          let ctx_j = { ...ctx, value: values[long], explicitly_set: explicitly_set[long] }
          values[long] = opt.reduce_raw(ctx_j, Value(Some(v)))
          explicitly_set[long] = true

    // ShortOpts は別セクションで処理
  }

explicitly_set[long] = true
```

**parse ループは完全にオプション種別に無知**:
- arity でトークン消費数を決定
- ReduceContext にコンテキスト一式を渡す
- reduce_raw に全判断を委譲
- Append の replace semantics も reducer 内部で ReduceContext を見て判断

4. required チェック / choices チェック
5. `--help` / `--version` 特殊処理
6. ParseResult を構築して返す

Design rationale: parse は純粋関数。ReduceContext がコンテキストを運び、
全ての戦略判断は reduce_raw 内で完結する。parse は種別を知らない。

### ShortOpts の処理

旧実装と同じアルゴリズム。arity で分岐:
- arity=0: Flag/Count として処理、次の文字へ
- arity>0: 残りの文字列を値として消費、または次トークンを消費

---

## validate

`Array[&ErasedOpt]` を受け取り、メタ情報ベースでバリデーション。

検証項目:
- 空 long 名、long 名重複、short 文字重複
- エイリアス / 反転パターン名の衝突
- choices 制約（choices と初期値の整合性）

OptKind 固有だったルール（Count+choices 禁止 等）は
コンビネータの構築時に構造的に防止。

---

## apply_defaults（純粋関数）

```moonbit
/// 各 opt の initial_raw() でデフォルト値マップを生成
pub fn init_defaults(opts : Array[&ErasedOpt]) -> Map[String, Array[String]]

/// 引数レイヤを defaults に吸収する（純粋関数）
/// 入力の defaults マップを変更せず、新しいマップを返す
/// エラーを raise しない（不正値は無視）
pub fn apply_defaults(
  opts : Array[&ErasedOpt],
  defaults : Map[String, Array[String]],
  args : Array[String],
) -> Map[String, Array[String]]
```

- tokenize → resolve → reduce_raw で各 opt のデフォルト値を更新
- 未知オプション・位置引数は無視（エラーにしない）
- 入力の defaults マップを変更せず、新しいマップを返す

### apply_defaults での ReduceContext 構築

```moonbit
let ctx = ReduceContext {
  value: defaults[long],
  initial: opt.initial_raw(),
  defaults: None,            // ← parse と異なり None（stacking mode の目印）
  explicitly_set: ...,
}
```

**defaults フィールドが None なので Append の reducer は常に stacking で動作する。**
parse 時は defaults フィールドが Some なので replace semantics が発動する。
この ReduceContext の1フィールドの違いだけで parse/apply_defaults のセマンティクス差が表現される。

### parse との接続

```moonbit
let d0 = init_defaults(opts)               // 各 opt の initial_raw()
let d1 = apply_defaults(opts, d0, config_args)
let d2 = apply_defaults(opts, d1, env_args)
let result = parse(opts, cli_args, defaults=d2)  // defaults を注入
```

Design rationale: Opt[T] は immutable なので値の書き換えができない。
`Map[String, Array[String]]` を中間表現として使い、parse の defaults~ に注入。
apply_defaults（stacking）と parse（replace）のセマンティクス差は
ReduceContext.defaults フィールドの有無で reducer が自己判断する。

---

## CmdDef + サブコマンド

```moonbit
pub(all) struct CmdDef {
  name : String
  description : String
  version : String
  opts : Array[&ErasedOpt]
  global_opts : Array[&ErasedOpt]
  subcommands : Array[CmdDef]
  aliases : Array[AliasEntry]
  help_on_empty : Bool
}

pub(all) struct CommandResult {
  command : Array[String]
  result : ParseResult
}

pub fn parse_command(cmd : CmdDef, args : Array[String]) -> CommandResult raise ParseError
```

find_command / scan_for_subcommand のアルゴリズムは旧実装と同じ。
arity() + is_optional_value() でトークン消費量を計算。

---

## Group（後続フェーズ）

基本パーサが安定してから着手。Design Record セクション 17.1 の namedGroup 構想をベースに。

---

## 実装計画

### Step 0: 準備

- `src/lib/` を `src/lib-old/` にリネーム（テストケース参照用に保持）
- `src/lib/` をゼロから作り直す
- `moon.pkg` は新規作成

### Step 1: Token + tokenize

**ファイル**: `src/lib/token.mbt`, `src/lib/token_test.mbt`

tokenize は言語の字句解析。旧実装からそのまま移植可能。

```moonbit
pub(all) enum Token {
  LongOpt(String)
  LongOptWithValue(String, String)
  ShortOpts(String)
  Positional(String)
  DoubleDash
} derive(Eq, Show, Debug)

pub fn tokenize(args : Array[String]) -> Array[Token]
```

テスト: 旧 12 件をそのまま移植。

### Step 2: 型定義

**ファイル**: `src/lib/types.mbt`

上記「型定義」セクションの全型を定義。

### Step 3: コンビネータ関数群

**ファイル**: `src/lib/combinators.mbt`, `src/lib/combinators_test.mbt`

上記「コンビネータ関数群」セクションの全関数を実装。

### Step 4: 名前解決 (resolve)

**ファイル**: `src/lib/resolve.mbt`, `src/lib/resolve_test.mbt`

上記「名前解決」セクションの関数を実装。

### Step 5: parse（コアロジック）

**ファイル**: `src/lib/parse.mbt`, `src/lib/parse_test.mbt`

上記「parse」セクションのロジックを実装。

### Step 6: validate

**ファイル**: `src/lib/validate.mbt`, `src/lib/validate_test.mbt`

上記「validate」セクションの検証ロジックを実装。

### Step 7: apply_defaults（純粋関数）

**ファイル**: `src/lib/apply_defaults.mbt`, `src/lib/apply_defaults_test.mbt`

上記「apply_defaults」セクションの関数を実装。

### Step 8: CmdDef + サブコマンド

**ファイル**: `src/lib/command.mbt`, `src/lib/command_test.mbt`

上記「CmdDef + サブコマンド」セクションの構造体と関数を実装。

### Step 9: Group（後続フェーズ）

基本パーサが安定してから着手。Design Record セクション 17.1 の namedGroup 構想をベースに。

### Step 10: テスト完全移行

旧 399 件のテストケースが検証する「要件」を全て新 API で書き直す。

### 実装順序

```
Step 0 (準備)
  ↓
Step 1 (Token/tokenize) ← 依存なし
  ↓
Step 2 (型定義) ← 依存なし
  ↓
Step 3 (コンビネータ) ← Step 2
  ↓
Step 4 (resolve) ← Step 2
  ↓
Step 5 (parse) ← Step 1, 2, 3, 4
  ↓
Step 6 (validate) ← Step 2
  ↓
Step 7 (apply_defaults) ← Step 1, 2, 4
  ↓
Step 8 (CmdDef) ← Step 5, 6
```

### 検証方法

各 Step で TDD:
1. 旧テストケースから要件を抽出
2. 新 API でテストを書く（RED）
3. 実装する（GREEN）
4. `moon test` で全 pass 確認
5. `just release-check` (fmt + info + check + test) で品質確認
