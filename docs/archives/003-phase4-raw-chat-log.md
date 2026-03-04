# Phase 4 設計議論 — 生チャットログ（2026-02-27）

設計書 `docs/DESIGN.md` と要約版 `docs/archives/002-phase4-design-discussion-log.md` の元になった議論。
無機質な設計書にまとめる際に失われがちな思考プロセス・意図・発想の連鎖を保存する目的で、生のまま記録する。

---

## 議論開始: 型安全なアクセスの模索

> そうですね、Ref[T] は struct Ref[T] { mut val : T } で、まさに案3の Opt[T] と同じ構造です。

```moonbit
// Ref[T] のパターンと同じ
struct Opt[T] {
  def : OptDef        // 型消去された定義（Array に入る用）
  mut value : T?      // パース結果を書き込む
}
```

パース後に opt.value で型付きの値が直接取れる。ParseResult の Map を経由しない。

ただ1つ気になるのは、parse() が Opt[T] の value に書き込むには、parse() 側が各 Opt[T] の参照を知っている必要があること。Array[OptDef]（型消去済み）からは Opt[T] に戻れないので、書き込みのコールバックを OptDef に持たせる必要があります:

```moonbit
struct OptDef {
  long : String
  // ...
  // パース結果を書き戻すコールバック（型消去されたクロージャ）
  on_parsed : (ParsedValue) -> Unit
}
```

Opt[T]::new 時にクロージャでキャプチャ:
```moonbit
fn Opt::new[T : FromParsed](long~ : String, ...) -> Opt[T] {
  let opt = Opt { def: ..., value: None }
  opt.def.on_parsed = fn(v) { opt.value = Some(T::from_parsed(v)) }
  opt
}
```

---

## 転換点: 「書き込む必要はあるの？」

**User:** 書き込む必要はあるの？ parserを常に必要とするならどう

---

## Opt[T] は値を保持せず、型付きアクセサ（レンズ）に

```moonbit
struct Opt[T] {
  def : OptDef
  parser : (String) -> T raise ParseError
}

fn get[T](self : Opt[T], result : ParseResult) -> T? raise ParseError {
  match result.get_string(self.def.long) {
    Some(s) => Some(self.parser(s))
    None => None
  }
}
```

これなら:
- Opt[T] は immutable、mut 不要
- ParseResult は今のまま String ベース
- パース処理も今のまま変更不要
- on_parsed コールバックも不要
- 型安全性は opt.get(result) で保証

```moonbit
let port = Opt[Int]::single(long="port", parser=int_parser)
let name = Opt[String]::single(long="name", parser=string_parser)

let cmd = CmdDef::new(opts=[port.def, name.def])
let result = parse(cmd, args)

let p : Int? = port.get(result)     // "42" → 42
let n : String? = name.get(result)  // そのまま
```

シンプルですね。パーサ本体に手を入れずに、上に薄い型付きレイヤーを被せるだけ。

---

## parser 必須なら String 型でも明示する

```moonbit
let port = Opt::single(long="port", parser=parse_int)
let name = Opt::single(long="name", parser=parse_string) // identity 的
let verbose = Opt::flag(long="verbose")  // Flag は Bool 固定なので parser 不要
```

使用:
```moonbit
let result = parse(cmd, args)  // 今のまま String ベース

let p : Int? = port.get(result)      // "42" → 42
let n : String? = name.get(result)   // "foo" → "foo"
let v : Bool = verbose.get_flag(result) // true/false
```

- ParseResult も parse() も今のまま変更不要
- Opt[T] は immutable な薄いラッパー
- choices チェックも parser 内で統合可能
- completion ヒントも Opt[T] に持たせられる

---

## コンビネータ合成の着想

**User:**
singleもsingleをやめて、
```
port=opt::int(long=port)
name=opt::string() #single
vervose=opt::bool() #flag
filters=opt::append(opt::string)
kv=opt::tuple(opt:string, opt::int) #value(n=2)
rgb=opt::tuple(opt:int,opt::int, opt:int) #value(n=3)
colors=opt::append(rgb)
```

---

面白い。OptKind を enum ではなくコンビネータで合成する設計ですね。bpaf に近い。

```moonbit
// プリミティブ
let port = opt::int(long="port")           // Opt[Int]
let name = opt::string(long="name")        // Opt[String]
let verbose = opt::bool(long="verbose")    // Opt[Bool]

// 合成
let filters = opt::append(opt::string)     // Opt[Array[String]]
let kv = opt::tuple(opt::string, opt::int) // Opt[(String, Int)]
let rgb = opt::tuple(opt::int, opt::int, opt::int) // Opt[(Int, Int, Int)]
let colors = opt::append(rgb)              // Opt[Array[(Int, Int, Int)]]
```

型が合成で自然に決まるのが良い。OptKind の enum が不要になり、parser が全て担う。

MoonBit での課題は tuple の可変長:
- `tuple(a, b) → (A, B)`
- `tuple(a, b, c) → (A, B, C)`

variadic generics がないので、固定アリティで提供:
```moonbit
fn tuple2[A, B](a : Opt[A], b : Opt[B]) -> Opt[(A, B)]
fn tuple3[A, B, C](a : Opt[A], b : Opt[B], c : Opt[C]) -> Opt[(A, B, C)]
fn tuple4[A, B, C, D](...) -> Opt[(A, B, C, D)]
// 実用上 4〜5 で十分
```

append は:
```moonbit
fn append[T](inner : Opt[T]) -> Opt[Array[T]]
```

---

**User:** いや今は良い方法を模索してる段階だからコレがコレまでの要件を全て満たせる形に昇華できるなら筋良さそうかなと。ちなみにtupleは要は単なる可変長引数で良いのではないかと。またorを用意すると `or(rgb, csscolorstring)` みたいなこともできそう、値を受けるオプションは数固定制約を設けているが、先頭の可変じゃない部分だけでの部分マッチングな曖昧さがない限りは許容可能の可能性もある。

---

tuple = 可変長引数 なら、型安全性の段階がある:
```moonbit
// A) 全要素同型なら素直
opt::values(opt::int, n=3)  // 3つの Int を消費 → Array[Int]

// B) 異型なら Array[String] で受けて parser 内で変換
opt::values(n=3, parser=rgb_parser)  // "255" "128" "64" → RGB struct
```

or は parser combinator の choice:
```moonbit
// --color 255 128 64  → RGB
// --color red         → CSS color string
let color = opt::or(rgb, css_color_string)  // Opt[Color]
```

曖昧さ判定は「先頭トークンで区別できるか」で、例えば:
- rgb: 3つ消費、先頭が数値
- css_color: 1つ消費、先頭が文字列
- → 先頭が数値か文字列かで区別可能 → OK

### 既存要件との対応表

| 現在の機能 | コンビネータ設計 | 課題 |
|---|---|---|
| Flag | opt::bool() | OK |
| Single | opt::int(), opt::string() 等 | OK |
| Append | opt::append(inner) | OK |
| Count | opt::count() ? | 特殊（出現回数を数える） |
| OptionalValue | opt::optional(implicit="true") ? | 値あり/なし両対応 |
| Group | opt::group(...) ? | 子スコープ + positional |
| --no-xxx inversion | メタ情報として付与？ | parser ではなく定義側 |
| env | メタ情報 | parser 外 |
| choices | parser 内でチェック | OK |
| required | メタ情報 | parser 外 |
| value_name | メタ情報 | ヘルプ表示用 |
| completion hint | メタ情報 | 補完用 |

parser で表現できるもの: 型変換、choices、バリデーション、or、tuple
parser 外のメタ情報: long/short/env/required/inversion/help/visibility/completion hint

つまりコンビネータが担うのは「値をどうパースするか」の部分で、オプション自体の振る舞い（inversion, env, required 等）は別レイヤーに残る。完全に OptKind を消せるわけではなく、OptKind の一部（値の受け取り方+型変換）をコンビネータに置き換える形になりそうです。

---

**User:** 元々optkindが完全に良いとは思ってなかったけど、議論をすすめる為と僕の希望する要件を満たせられるかの検証のためのpocとして進めていたつもりなので。

---

了解です。つまり:
- Phase 1-3 の PoC → 要件（Group, inversion, positional, apply_defaults 等）が実現可能か検証済み。399テストで動作保証
- 次のフェーズ → PoC で確認した要件を満たしつつ、API 設計を再考する

PoC は「何ができなければいけないか」を洗い出す役割を果たしていて、コンビネータ設計はそれを「どう表現するか」の話ですね。

---

## 内部型としてのtuple

**User:** あー内部の実装上の型としてかなだとしたらtuple2345くらい作れば良いかなとか思う。

---

そうですね。実用上 5 あれば十分。ユーザー API 側は labeled argument で自然にできそう:
```moonbit
// n=1 は単なる opt::int() 等なので tuple 不要
// n=2〜5 は tuple{n}
let kv = opt::tuple2(opt::string, opt::int)         // (String, Int)
let rgb = opt::tuple3(opt::int, opt::int, opt::int)  // (Int, Int, Int)
```

append との合成も型が自然に決まる:
```moonbit
let colors = opt::append(opt::tuple3(opt::int, opt::int, opt::int))
// Opt[Array[(Int, Int, Int)]]
```

---

## 左畳み込みの発見

**User:** というかtuple(tuple(o1,o2),o3)で表現しても良いのか？ というかtuple(o1,None) で1個も表せるし内部的にはsingleとマルチの区別も要らなそう?

---

cons cell / HList の発想ですね。内部的には tuple2 だけで:
```
1個: tuple(int, nil)              → Int
2個: tuple(int, tuple(int, nil))  → (Int, Int)
3個: tuple(int, tuple(int, tuple(int, nil))) → (Int, (Int, Int))
```

single と multi の区別が消えるのは美しい。内部表現が統一される。

ユーザー API 側は平坦に見せる:
```moonbit
// ユーザーからは
let rgb = opt::tuple(opt::int, opt::int, opt::int)  // 表面上は3引数
// 内部: OptPair[Int, OptPair[Int, OptPair[Int, OptNil]]]

// 取り出し時は平坦な tuple で返す
let (r, g, b) = rgb.get(result)  // (Int, Int, Int)
```

ただし平坦化の変換（(A, (B, (C, ()))) → (A, B, C)）をユーザー API の tuple3/4/5 が担う形になります。内部 1 種類 + 表面 N 種類、という責務分離。

---

## Reducer パターンの発見（核心）

**User:** あと組み込みはintとかプリミティブの他にpathとかregexとかもあって良いし。opt::custom(parser:String→T) があれば何でもできる？ なんならintの中身はcustom(parse_int)か？ さらに言えばこのparserだがstring→Tじゃなくて(pre:T,cur:string)→T ならカウンタやflagも集約できるのでは？

---

これは鋭い。`(pre: T, cur: String) -> T` は reducer / fold パターンで、全 OptKind が統一される:

```moonbit
struct Opt[T] {
  initial : T
  reducer : (T, String?) -> T raise ParseError
  // + メタ情報 (long, env, help, ...)
}
```

| 現 OptKind | initial | reducer |
|---|---|---|
| Flag | `false` | `(_, None) -> true` |
| Count | `0` | `(n, None) -> n + 1` |
| Single(Int) | `None` | `(_, Some(s)) -> Some(parse_int(s))` |
| Append | `[]` | `(arr, Some(s)) -> arr + [s]` |
| OptionalValue | `None` | 値あり: `(_, Some(s)) -> Some(s)`, 値なし: `(_, None) -> Some(implicit)` |

`cur: String?` で値を取らない Flag/Count も統一。int は custom(parse_int) のシュガー。

```moonbit
// 全部同じ仕組み
let verbose = opt::flag(long="verbose")       // reducer: (_, _) -> true
let count = opt::count(long="verbose")        // reducer: (n, _) -> n + 1
let port = opt::int(long="port")              // reducer: (_, Some(s)) -> parse_int(s)
let names = opt::append(opt::string, long="name") // reducer: (arr, Some(s)) -> arr + [s]

// 全てはこれのシュガー
let x = opt::custom(initial=0, reducer=fn(n, _) { n + 1 }, long="verbose")
```

OptKind enum が完全に消えて、initial + reducer だけになる。

---

## 未解決課題への回答

### Group について

**User:**
```
namedGroup("upstream",
  path(path,required),
  int(timeout),
  namedGroup("socket",
    path(path,required)
    rest("filters", string)
  )
)
```
こんなでいけそうじゃね? で namedGroup は append で行けそうでグループ化は meta 側に group フラグを持てば表現できそう。append の中身も合成 Opt で表現できるなら名前付きか名前なしかも reducer で上手く表現出来そうな気がして来た。

### --no-パターン

**User:** reducer の pre リセットで良いでしょ。

### PoC からの移行

**User:** 移行不要。全部削除(split でコミット切り出して横にどけとけば良い、しばらくは振り返れるよう bookmark やタグか何かつけて残しとく)する。で全ガラで完全作り直しでよい。別にまだ誰も使ってないただの poc なんだから捨てて構わない。でも無駄ではなく新設計の礎としてとても役立ってくれた。ただし要件定義の具現化であるテストケースだけは漏れなく再利用。詳細なエッジケースを網羅したテストケース集こそ宝物。コレがあるからこそ大きな判断ができる。

---

## 左畳み込みへの転換

**User:** tupleの積み上げは t(t(t(o,none),o),o) のほうが良くないか?

---

パースがトークンを左→右に消費するので、左畳み込みなら消費順と構造が一致して自然。右畳み込み t(o,t(o,t(o,none))) だと末端まで展開してから戻る形になる。構造と処理順が一致する方を選ぶ、ケースバイケース。

---

## 大統一: Command / Option / Positional

**User:** 実はサブコマンドの消費自体もオプションと同じく reducer で統一出来そうなのと。位置パラメータも reducer で型やら補完やらいけるよねっていう。その場合 long は -- のオプション名ではなく、位置パラメータのプレースホルダ名になるイメージかな。これは rgb=(int(R),int(G),int(B)) も同じパターンで引数ありオプションをhelp表示するときの位置パラメータのプレースホルダ名に使われる。
その辺考えると meta に (command/option/位置パラメータ) を区別するのがあれば、サブコマンドとオプションと位置パラメータの定義まで全部 reducer パターンで大統一できそう。

---

全部同じ構造:

| 種別 | マッチ条件 | long の意味 | reducer |
|---|---|---|---|
| Command | 名前でマッチ | サブコマンド名 `serve` | 子スコープの結果を返す |
| Option | `--long` でマッチ | オプション名 `port` | 値を変換・蓄積 |
| Positional | 位置でマッチ | プレースホルダ名 `FILE` | 値を変換・蓄積 |

meta に `kind: Command | Option | Positional` があれば区別できる。

RGB の例:
```
--color int("R") int("G") int("B")
         ↑        ↑        ↑
         位置パラメータのプレースホルダ名
         help: --color <R> <G> <B>
```
