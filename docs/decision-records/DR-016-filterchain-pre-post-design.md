# DR-016: FilterChain による pre/post フィルタ設計

type: decision

reducer の前処理・後処理を型安全に合成可能なパーツとして分離する設計の記録。

## 議論ログ

### FilterChain 設計の発端

既存コンビネータが `String → T` の直接変換をハードコードしており、「片が配列で累積もその結合」（`--nums 1,2,3`）のようなケースを表現できない問題が浮上。

#### ユーザー発言

> 016-filterchain-pre-post-design.md追加してDESIGN更新したので見てみて。既存でスタブやモックに頼ってテスト誤魔化したりしてないか全チェックしといて。あと元々入機能だったのに勝手に難しいからとかでスキップしてないか再確認しててください。

ユーザーが DR-016 の設計ドキュメントを直接作成し、DESIGN.md を更新。AI に対して既存実装の品質チェックと機能スキップの検出を指示。

### parse() の Result 化

FilterChain 設計の議論と同時期に、公開 API の ergonomics 改善が議論された。

#### ユーザー発言

> MoonBitでは宣言的エラーは全てのエラーの対応を書かない限りエラーになるという強制的にエラー処理を書かせる仕組みになっている。なので p.parse() は raise する仕様にしないほうが良いですね。使い勝手が悪すぎです。これは Result を使うべきですね。

> さっき渡した設計追加と今の Result パターンを基本とする件。この修正と実装対応をお願いします。

この議論により `Parser::parse()` が `Result[ParseResult, ParseError]` を返す設計に変更された。内部の `parse_raw` は `raise` のまま維持し、公開境界でのみ Result にラップする方針。

### FilterChain と parse_raw の関係整理

FilterChain の型 `(A) -> B raise ParseError` が parse_raw のシグネチャと同じであることから、役割の混同リスクが議論された。

#### 整理結果

- **parse_raw**: トークン列全体を消費するエンジン。入力=`Array[String]`、出力=`ParseResult`
- **FilterChain**: 1つのオプション値を変換するパーツ。入力=`String`、出力=`Int` 等
- **parse**: 公開 API ラッパー。parse_raw のエラーに help_text を付与

FilterChain は parse の代替ではなく、parse の内部（reducer 内）で使われるパーツ。レイヤーが異なる。

## 背景・動機

既存の `append` コンビネータは `String → T の要素型` という変換を前提としており、
`--nums 1,2,3 --nums 5,5,5 → [1,2,3,5,5,5]` のような「片が配列で、累積もその結合」
というケースを表現できない。

```
既存 append:  String → Int,   (Array[Int], Int)     → Array[Int]
欲しいもの:   String → Array[Int],   (Array[Int], Array[Int]) → Array[Int]
```

「片の型 U」と「累積型 T」を分離し、`String → U` の変換チェーンを型安全に組み立てる
仕組みが必要になった。

あわせて、バリデーション（値を変えず ParseError だけ投げる）と変換（型を変える）を
同じインターフェースで並べて再利用パーツとして組み合わせたい、という要件も生じた。

## 核心：FilterChain[A, B]

```moonbit
///| A → B の変換ステップ（ParseError を伝搬できる）
struct FilterChain[A, B] {
  run : (A) -> B!ParseError
}

///| 関数合成。A→B と B→C を繋いで A→C
fn FilterChain::then[A, B, C](
  self : FilterChain[A, B],
  next : FilterChain[B, C],
) -> FilterChain[A, C] {
  { run: fn(a) { next.run(self.run(a)!) } }
}
```

`then` は ErrorMonad の Kleisli 合成（`>=>`）に対応する:

```
(A → B!Err) >=> (B → C!Err) = (A → C!Err)
```

チェーンの各ステップを `!` で伝搬させることで、途中のどのステップで発生した
ParseError も自動的に呼び出し元まで伝搬される。

## 3つのコンストラクタ

```moonbit
// 純粋変換（失敗しない）
fn Filter::map[A, B](f : (A) -> B) -> FilterChain[A, B] {
  { run: fn(a) { f(a) } }
}

// 検証（値を変えない。失敗したら ParseError）
fn Filter::validate[A](f : (A) -> Unit!ParseError) -> FilterChain[A, A] {
  { run: fn(a) { f(a)!; a } }
}

// パース変換（変換 + 失敗あり）
fn Filter::parse[A, B](f : (A) -> B!ParseError) -> FilterChain[A, B] {
  { run: f }
}
```

`map` と `validate` は `parse` の特殊化だが、意図を明示するために3つに分けた:
- `map`: 変換の意図（失敗しないことが型で分かる）
- `validate`: 検証の意図（型を変えないことが型で分かる）
- `parse`: 変換 + 失敗の両方あり

## Accumulator との分離

```moonbit
///| 片 U を現在の累積値 T にマージする関数
type Accumulator[T, U] = (T, U) -> T

///| FilterChain + Accumulator → reducer の自動生成
fn make_reducer[T, U](
  pre     : FilterChain[String, U],
  accum   : Accumulator[T, U],
  initial : T,
) -> (ReduceCtx[T]) -> T?!ParseError {
  fn(ctx) {
    match ctx.action {
      Value(Some(s)) => {
        let piece = pre.run(s)!
        Some(accum(ctx.current, piece))
      }
      Negate => Some(initial)
      _      => None
    }
  }
}
```

「String をどう変換するか（pre）」と「変換結果をどう累積するか（accum）」を分離することで、
それぞれを独立して再利用できる。

## 既存コンビネータとの統一

既存の `single` / `append` も同じ枠組みで表現できる:

| 種別       | pre (String → U)  | accum (T, U) → T         |
|------------|-------------------|--------------------------|
| `single`   | `parse_int` 等    | `(_, u) => u`（上書き）  |
| `append`   | `parse_int` 等    | `(acc, u) => acc + [u]`  |
| join 系    | `split.then(each(parse_int))` | `(acc, xs) => acc + xs` |

`single` と `append` は `accum` の違いだけで、`pre` は共通化できる。

## 組み込みパーツのカタログ（combinators/ に実装）

```moonbit
// --- String 系 ---
let trim        : FilterChain[String, String]        = Filter::map(String::trim)
let non_empty   : FilterChain[String, String]        = Filter::validate(fn(s) {
                    if s.is_empty() { raise ParseError::invalid("empty string") }
                  })
let to_lower    : FilterChain[String, String]        = Filter::map(String::to_lower)
let to_upper    : FilterChain[String, String]        = Filter::map(String::to_upper)

fn split(sep : String) -> FilterChain[String, Array[String]] {
  Filter::map(fn(s) { s.split(sep) })
}

// --- パース系 ---
let parse_int    : FilterChain[String, Int]    = Filter::parse(fn(s) { Int::parse(s)! })
let parse_float  : FilterChain[String, Double] = Filter::parse(fn(s) { Double::parse(s)! })
let parse_bool   : FilterChain[String, Bool]   = Filter::parse(fn(s) {
                     match s {
                       "true" | "1" | "yes" => true
                       "false" | "0" | "no" => false
                       _ => raise ParseError::invalid("expected bool: \{s}")
                     }
                   })

// --- 数値バリデーション ---
fn positive[N : Compare + Show]() -> FilterChain[N, N] {
  Filter::validate(fn(n) {
    if n <= 0 { raise ParseError::invalid("\{n} must be positive") }
  })
}
fn in_range[N : Compare + Show](lo : N, hi : N) -> FilterChain[N, N] {
  Filter::validate(fn(n) {
    if n < lo || n > hi {
      raise ParseError::invalid("\{n} out of range [\{lo}, \{hi}]")
    }
  })
}
fn one_of(choices : Array[String]) -> FilterChain[String, String] {
  Filter::validate(fn(s) {
    if !choices.contains(s) {
      raise ParseError::invalid("expected one of \{choices}: got \{s}")
    }
  })
}

// --- Array 系 ---
fn each[A, B](f : FilterChain[A, B]) -> FilterChain[Array[A], Array[B]] {
  Filter::parse(fn(xs) { xs.map(fn(x) { f.run(x)! }) })
}
fn non_empty_arr[A]() -> FilterChain[Array[A], Array[A]] {
  Filter::validate(fn(xs) {
    if xs.is_empty() { raise ParseError::invalid("empty list") }
  })
}
```

## 使用例

```moonbit
// --port 8080（変換 + バリデーション）
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

// --ratio 0.5（float + range）
let ratio = opt::single(
  name = "ratio",
  pre  = trim.then(parse_float).then(in_range(0.0, 1.0)),
)
```

## 型安全性の保証

```
trim                         : FilterChain[String, String]
  .then(split(","))          : FilterChain[String, Array[String]]
  .then(each(parse_int))     : FilterChain[String, Array[Int]]   ← コンパイル時確定
```

チェーンの途中で型が合わない場合はコンパイルエラーになる。
「最終的に `String → T` になっている」という保証が型レベルで得られるため、
`Array[Any]` でフィルタを保持する方式より安全。

## 既存設計へのインパクト

- **ExactNode / reducer のシグネチャは変わらない** — `make_reducer` がブリッジ
- **ReduceCtx のシグネチャは変わらない** — `pre` の適用は reducer 内部で完結
- **combinators/ に FilterChain 型 + 組み込みパーツを追加** — Step 2 の実装スコープ拡大
- **opt::custom_append を新設** — `pre` + `accum` を受け取る汎用 append コンビネータ

不採用案: `Array[(Any) -> Any]` でフィルタをランタイム配列として保持する方式。
型安全性が失われ、チェーンの型整合性がコンパイル時に検証できないため不採用。
