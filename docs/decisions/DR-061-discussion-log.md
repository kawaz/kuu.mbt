# DR-061 設計議論ログ (2026-03-21)

DR-061 の核心に至る設計議論の記録。ニュアンスを失わないよう、設計者の発言を中心に残す。

## 1. append 系の問題提起

> `append_string` 等がまだ残っているのはなぜか。`append` を汎用コンビネータにする話をしたはず。そうしないと型ごとに append が必要になる。`string_opt` → `string` のリファクタと同じ話が残っている。

→ `custom_append` → `append` のリネーム漏れが発覚。

## 2. dashdash は合成シュガー

> `dashdash` は特別なものではない。`serial([exact("--"), rest(string)])` に分解できるはず。

greedy の位置について修正:

> dashdash はグループを作る。バラバラの exact + rest ではなく、必ず serial で囲む。greedy を付けるのは rest ではなく exact（またはserial）。

```
serial([exact('--', greedy=true), rest(string())])
```

## 3. append は adjust の特殊ケース

> link/clone/adjust の設計時に全部解決されるはずだった。append も含めて全て adjust の話。

> pre と post と accum のそれぞれに対して insert{before/after} を足すのが adjust という話だったはず。なぜ勝手に変わっているのか。

→ DR-037 の元設計（6パラメータ）が DR-044 で after_post のみに縮小されていた。

## 4. split は pre の仕事

> split は pre でやればよい。`--fields` は pre が終わった時点で `Array[String]` になっている。当然 `Opt[Array[T]]` だろう。

→ split は accum ではなく pre。型変換は pre の責務。accum は同型の結合。

## 5. append の型変換

> `append(Opt[T])` は `Opt[T]` を `Opt[Array[T]]` にするもの。

→ `append(Opt[T])` → `Opt[Array[T]]`。これが append の定義。

## 6. concat の命名

> merge は意味が広すぎる。concat のほうが動作が明確。

## 7. option() の合成構造

```
numbers = option(
  T=Array(number)  // concat からくる型
  name="number",
  variation_reset="no",
  concat(split(number(), sep=","))
)
```

## 8. 3レイヤモデル — core は直接触るものではない

> 内部で徹底的に分解するのはあくまで内部実装の話。DX 層がそれらを上手く束ねる。core は純粋関数を保つのが責務。バラバラのパーツを手書きするのは苦行だが、core を直接使う想定ではない。

> 現在 core にある option や long は、本来 core ではなく低レイヤ API。他言語では「各言語 DX → 各言語低レイヤ API → FFI → MoonBit Core」という構成になるが、全部が MoonBit なので境界が見えず混同しやすい。

```
MoonBit DX API
↓
MoonBit 低レイヤ API（option, long, short, dashdash, append, ...）
↓
FFI（なし）
↓
MoonBit Core（string/int/double/number/bool, clone/link/adjust, or, serial, sub_parser...）
```

> 3レイヤを3パッケージに分けてもよいが、実際には core と低レイヤ API は併用するので、内部で2つに分けつつ `@kuu` = (`@core` + `@低レイヤAPI`) を re-export するだけのパッケージとし、ユーザーは両方を意識せず使えるのがちょうどよい。

## 9. flag は core プリミティブではない

> flag は特殊なものではなく、便利なコンビネータ。実態は `bool(initial=false)` でしかない。そこに short や long のマッチング条件が adjust で付与されただけ。

> `string()`, `int()`, `bool()` はオプション的なマッチング条件をまだ持っていない状態の `Opt[T]`。それに対して `option`（`exact("--name")` の後ろに `string()` が配置される）や `positional`（何番目の引数として `string()` が配置される）のように、マッチ条件は他のコンビネータが文脈として与える。

## 10. value() が真のプリミティブ

> `string()` や `int()` は実はまだプリミティブではない。真のプリミティブは `value(initial~=Lazy[T]?)`。これが値の入れ物の原初形。`int()` = `adjust(value(initial~=Lazy[T]?), pre=parse_int)` で表現できる。

> 「型変換の pre を持っているだけ」は正しい。「マッチ条件を何も持っていない」は不正確で、型変換の pre がそのままマッチ条件として機能している。

## 11. exact は値を持たない

> `exact` は値を持たず引数を消費するだけのプリミティブ。`Opt[Unit]` のような存在で、引数消費能力だけを持つ。`option` や `flag` で value descriptor とセットで並べられることで「オプション」に見えるだけで、本来は値と紐づいていない。

## 12. clone/link/adjust は値を増やさない

> `clone`, `link`, `adjust` は基本的に「値」を増やさない。既存の値の振る舞いを変えるだけ。値の入れ物が増えるのはグループ形成時。例えば `rest(string())` では `string()` を雛形にした clone が動的に生成される。

## 13. group は serial + append

> 特別な group コンビネータが必要かどうか自体疑問。serial + append の入れ子で十分。

```
append(serial(
  exact('--upstream'),
  simple(name="upstream", string()),
  append(serial(
    exact('--socket'),
    simple(name="socket", string()),
    rest(name="filters", string())
  ))
))
```

> これだけで2段入れ子のグループが表現できる。

## 14. append/rest の内部構造と parallel

> append は、clone された accessor に値が入った後に getter で取り出し、`Opt[Array[T]]` に append する構造ではないか。

> `parallel(t: Opt[T]) -> Opt[Array[T]]` のようなプリミティブがあり、マッチするたびに accessor を clone して値をセットし、getter で取り出すという流れ。

## 15. accum フェーズはペンディング

> 少なくとも append では accum フェーズは不要そう。ただし他のユースケースで必要になる可能性を排除できない。今すぐ判断できないので accum 削除はペンディング。

## 16. parallel の命名

> このプリミティブはユーザーが直接使うことはほぼなく、append と rest を介してしか使われないと思われる。

→ 命名は実装時に決定。ユーザーが直接使うケースはほぼないと思われるので急がない。

## 17. greedy は option のための仕組み

> greedy は本質的に option のためにある。option がなければ全て positional で1フェーズ処理できる。option を先に拾う必要があるから greedy で2フェーズに分けている。dashdash が greedy を使うのは option の特殊な動作に対する対抗策。

## 18. TS DX 層との関係

> TypeScript の DX 層なら型制約が緩いので、この合成モデルがほぼそのまま API 定義として使えるはず。
