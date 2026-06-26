# DR-019: repeat を multiple に統合、構造プリミティブは4つ、可変長 positional の表現

## 決定

### 構造プリミティブは4つ

```
exact / or / seq / primitive
```

当初 `repeat` を5つ目の構造プリミティブとして導入しかけたが、**要素属性 `multiple` に統合**して消滅させた。

### repeat は要素属性として multiple に吸収

「同じ要素を不定回」という反復は、独立した構造要素ではなく **要素に付く属性**で表す:

```json
// 可変長 positional: rm path...
{"name": "path", "multiple": {"min": 1}}

// mv a b c dst
"positionals": [
  {"name": "path", "multiple": {"min": 1}},
  {"name": "dir"}
]
```

option の複数回累積 (DR-008) と positional の複数個は **どちらも「複数値属性 = multiple」** で対称に表現される。起動方式 (位置 vs name) は配置で既に決まっているので、属性側で区別しない。

- positional 文脈: 個数制約が主に効く
- option 文脈: 累積戦略が主に効く
- 効く要素が文脈で変わるだけで、属性名は1つ

### 値の伝搬表 (DR-015 + primitive 補完)

| type | 値の発生 | 親への伝搬 |
|---|---|---|
| primitive (string/number/...) | value 持つなら literal、無いなら CLI から1引数消費 | 自身の値 |
| exact | value 持つなら literal、無いなら値なし | 値があれば伝搬 |
| or | 選ばれた子の値 | 子の値をそのまま |
| seq | 子の値の配列 (単独要素なら単独) | 配列 or 単独 |

`multiple` を持つ要素は、上記の単一値が複数回畳まれる。

## 経緯

### repeat の発見

前回までのプリミティブ (exact/or/seq/primitive) では **`rm path...` すら定義できなかった**。seq は「決まった数の子を順次」、or は「1つ選ぶ」だけで、「同じ要素を不定回」が穴だった。

kawaz:
> リピート要素が前のだと定義できてなかったからね。rm path... すら定義できなかったと思う。

### repeat を独立要素にする誤り

Claude は当初 `{type: "repeat", child: ...}` という独立構造要素を提案。kawaz が却下:

> それはオプションの話じゃなくて? ポジショナルで定義するにはその path の定義を配列にする必要が出るのでは? ポジショナルにそれがいても意味がわからない。

positional 列の中に「repeat という名前の要素」がいても何を繰り返すのか不明。正しくは **positional 要素そのものが「繰り返す」性質を持つ** = 要素属性。

### multiple との統合

repeat (positional の個数) と multiple (option の累積) は**実質同じもの**——「同じ要素が複数回 → 値を畳む」。違いは起動方式だけで、それは配置で決まる。

kawaz:
> 確かにリピートとマルチプルは同じかもね。ポジショナルで使ったらリピートの意味になる感じか。

→ 属性を `multiple` 一本に統合。フィールドを安易に増やす反省パターンを回避。

## 効果

- 構造プリミティブが4つに確定 (repeat は属性に昇格 = 消滅)。
- `rm path...` / `mv a b c dst` / `cp src... dst` が書けるようになった (前回の穴を完全に塞いだ)。
- positional の個数と option の累積が対称に表現される。

## 関連

- DR-005 (type は要素単位の型)
- DR-008 (multiple フィールド) — 本 DR で個数概念を統合
- DR-015 (値の伝搬) — primitive 行を補完
- DR-027 (seq への改名、`serial` は廃止語、`seq` が canonical)
- DR-034 (multiple の内部構造再編成)
- DR-038 (bounded path-search による曖昧性解決)

## Superseded (歴史)

> 以下の記述は後続 DR で覆された。現役仕様の理解には不要、判断経緯としてのみ残す。

### multiple のフィールド一覧 (DR-034 で再構成)

> **更新: DR-034 により本 DR の「multiple が min/max/kind/on_repeat/item_separator/key_value_separator/key_from を直接持つ」設計は撤回。現役は DR-034 の `pieceProcessor` / `separator` / `mapper` / `collector` の4要素分解 + 個数制約を別軸に分離する形に再編成された。本 DR の「repeat を multiple に統合する」決定自体は引き続き有効。**

統合当初の multiple は以下のフィールドを直接持つ設計だった:

| フィールド | 主に効く文脈 | 役割 |
|---|---|---|
| `min` / `max` | positional | 個数 |
| `kind` | 両方 | list / set / map (値の構造) |
| `on_repeat` | option | append / override / ... |
| `item_separator` / `key_value_separator` | 両方 | 1引数内分割 |
| `key_from` | map | キー源 |

DR-034 でこれらは `pieceProcessor` / `separator` / `mapper` / `collector` の4要素に再構成され、個数制約 (`min` / `max`) は multiple 内部に同居させず**別軸として分離**する方針に変わった。

### 「最長一致」前提での ambiguous 解決 (DR-038 で更新)

> **更新: DR-038 により「最長一致」を成功条件とする規則は廃止。現役の契約は「完全経路の一意性 (bounded path-search で唯一の経路に確定すること)」。本 DR の `mv a b c dst` が解けるという結論自体は変わらないが、根拠は「最長一致だから」ではなく「全 positional 列を満たす経路が唯一だから」に置き換わる。**

`mv a b c dst` は `{path, multiple:{min:1}}` + `{dir}` で書ける。`dir` が multiple なし = ちょうど1個と確定しているので、`path` の取り分 (末尾1個を残す) が一意に決まる ——この帰結を当初は「最長一致で曖昧さなく解決できれば成功 (DR-021)」と表現していた。

帰結として残る性質は DR-038 の語彙で同様に表現される:

> 同一 positional 列に上限なしの multiple が複数あると、取り分の経路が一意に決まらず ambiguous になりうる。

これは定義として書けてしまうが実行時 ambiguous。静的バリデータが「上限なし multiple が列内に複数 → 潜在 ambiguous」を warn できる。
