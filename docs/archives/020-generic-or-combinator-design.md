# DR-020: 汎用 or コンビネータ + Initial[T] — choices/implicit_value の再設計

## 背景

DR-019 で optional value option（choices + implicit_value）を実装したが、`choices: Array[String]` が String 固定で汎用性がないことが判明。実装は撤回し、設計からやり直す。

## DR-019 の問題点

### choices: Array[String] は退化形

```moonbit
// DR-019 の実装（撤回済み）
p.string_opt(name="color", choices=["always", "none", "auto"], implicit_value="always")
```

これは全候補が `exact(s) → s` の単純マッチ。しかし実際のユースケースでは:

```
enum Color { Red, Green, Blue, RGB(Int, Int, Int) }
```

のように、候補ごとに異なるパーサ（consumed 数も型変換も異なる）が必要になる:

```
or([
  exact("red", initial=Red),
  exact("green", initial=Green),
  exact("blue", initial=Blue),
  serial("rgb", int("R"), int("G"), int("B"))  // consumed=4, → RGB(r,g,b)
], implicit=Red)
```

`choices: Array[String]` はこのパターンの退化形に過ぎず、汎用設計としては筋が悪い。

### 値の受け口はコンビネータの組み合わせであるべき

kuu の強みは ExactNode の組み合わせと parse_raw の最長一致。choices もこの仕組みの上に乗るべきで、String 配列のような別レイヤーの仕組みを持ち込むべきではない。

## 設計方針

### 汎用 or コンビネータ

値の選択肢は「sub-parser の配列」として表現:

```moonbit
// 概念的な API
let color : Opt[Color] = p.value_opt(
  name="color",
  value=or([
    exact("red", initial=Red),
    exact("green", initial=Green),
    exact("blue", initial=Blue),
    serial("rgb", int("R"), int("G"), int("B"), map=fn(r,g,b) { RGB(r,g,b) }),
  ]),
  default=Auto,
  implicit=Red,  // --color だけ指定時
)
```

各 sub-parser は ExactNode と同じ `(Array[String], Int) -> TryResult` シグネチャ。parse_raw の最長一致がそのまま適用される。

### Accept(consumed=0) — ε-マッチによるデフォルト表現

「何も消費しないが値を持つ」sub-parser。or 内の最低優先度 fallback として機能する:

```
or([
  serial(exact("--color"), value_parser),  // consumed=2: --color <value>
  exact("--color", commit=implicit),       // consumed=1: --color alone
  always(default),                         // consumed=0: オプション未指定時
])
```

これにより default が「cell の初期化」という別メカニズムではなく、同じ TryResult の言語で表現できる。or の最長一致で consumed=2 > consumed=1 > consumed=0 の優先順位が自然に決まる。

#### トップレベルでの意味論

consumed=0 は or 内部に限らず、トップレベル ExactNode としても有効:

- parse_raw の最長一致で consumed>0 のノードに常に負ける（`0 > 0` は false）
- 全ノードが Reject のとき、consumed=0 の Accept が fallback になる
- consumed=0 が複数 → ambiguous エラー（consumed>0 と同じルール）
- commit されたかどうかで「この opt が使われたか」を判定可能

parse_raw のメインループは `pos += consumed` で進むため、consumed=0 で pos が進まないが、commit で状態が変わるため次のイテレーションでは同じノードが Reject を返す（or 通常のノードと同じ）。無限ループにはならない。

ただし現行の parse_raw は consumed=0 を拾うロジックがないため、対応するには best_consumed の初期値やフォールバック処理の変更が必要。

### Initial[T]（Val / Thunk）

DR-019 で言及済みだが未実装:

```moonbit
pub(all) enum Initial[T] {
  Val(T)
  Thunk(() -> T)
}
```

- `default`: オプション未指定時の値
- `implicit`: オプション指定だが値省略時の値（Thunk なら tty 判定等の遅延評価が可能）

### ヘルプ表示は従

ヘルプの都合に合わせてコア側に制約を作るのは本末転倒。コアが主、ヘルプが従。

- ヘルプ表示形式は各種アイデアを残すだけで、コア設計が固まってから追従
- `=` マーカー表記等のアイデアは DR-019 に記録済み

## 残留した実装

### post_hooks

`post_hooks: Array[() -> Unit raise ParseError]` は choices/implicit_value とは独立した仕組みとして残留:

- Parser struct に `post_hooks` フィールド
- parse_raw 末尾で全 hooks 実行
- string_opt の `post? : FilterChain[String, String]?` パラメータ
- parse 後の値変換（auto → always/none 丸め等）や遅延バリデーション（required チェック等）に使用

## 実装順序（今後）

1. `Initial[T]` 型追加
2. 汎用 or コンビネータの Core 層設計（sub-parser の TryResult ベース）
3. Convention 層: `string_opt` + choices を or 展開で再実装
4. implicit_value を or(value_sub_parser, flag_node) パターンで再実装
5. ヘルプ表示の追従

## 撤回したコミット

- `uwptxwyy` feat: choices バリデーション + implicit_value (optional value option) 実装 (DR-019)
- `xmqslovn` feat: implicit_value 全コンビネータ展開 + post フィルタ + = マーカーヘルプ (DR-019)
- `lropsuzo` revert: choices/implicit_value 実装を撤回（post_hooks は残留）
