# DR-019: repeat を multiple に統合、構造プリミティブは4つ、可変長 positional の表現

## 決定

### 構造プリミティブは4つ

```
exact / or / serial / primitive
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

- positional 文脈: `min` / `max` が主に効く (個数)
- option 文脈: `on_repeat` が主に効く (散在の累積戦略)
- 効くフィールドが文脈で変わるだけで、属性名は1つ

### 値の伝搬表 (DR-015 + primitive 補完)

| type | 値の発生 | 親への伝搬 |
|---|---|---|
| primitive (string/number/...) | value 持つなら literal、無いなら CLI から1引数消費 | 自身の値 |
| exact | value 持つなら literal、無いなら値なし | 値があれば伝搬 |
| or | 選ばれた子の値 | 子の値をそのまま |
| serial | 子の値の配列 (単独要素なら単独) | 配列 or 単独 |

`multiple` を持つ要素は、上記の単一値が **配列 (list) / 集合 (set) / map** に畳まれる (kind に従う)。

## 経緯

### repeat の発見

前回までのプリミティブ (exact/or/serial/primitive) では **`rm path...` すら定義できなかった**。serial は「決まった数の子を順次」、or は「1つ選ぶ」だけで、「同じ要素を不定回」が穴だった。

kawaz:
> リピート要素が前のだと定義できてなかったからね。rm path... すら定義できなかったと思う。

### repeat を独立要素にする誤り

Claude は当初 `{type: "repeat", child: ...}` という独立構造要素を提案。kawaz が却下:

> それはオプションの話じゃなくて? ポジショナルで定義するにはその path の定義を配列にする必要が出るのでは? ポジショナルにそれがいても意味がわからない。

positional 列の中に「repeat という名前の要素」がいても何を繰り返すのか不明。正しくは **positional 要素そのものが「繰り返す」性質を持つ** = 要素属性。

### multiple との統合

repeat (positional の個数) と multiple (option の累積) は**実質同じもの**——「同じ要素が複数回 → 値を配列に集める」。違いは起動方式だけで、それは配置で決まる。

kawaz:
> 確かにリピートとマルチプルは同じかもね。ポジショナルで使ったらリピートの意味になる感じか。

→ 属性を `multiple` 一本に統合。CONTEXT.md の反省パターン (フィールドを安易に増やす) を回避。

## mv の取り分と ambiguous

`mv a b c dst` は `{path, multiple:{min:1}}` + `{dir}` で書ける。`dir` が multiple なし = ちょうど1個と確定しているので、`path` の取り分 (末尾1個を残す) が一意に決まる = **「最長一致で曖昧さなく解決できれば成功」** (DR-021) が効く。

ただし帰結として:

> 同一 positional 列に上限なしの multiple が複数あると、取り分が一意に決まらず ambiguous になりうる。

これは定義として書けてしまうが実行時 ambiguous。静的バリデータが「上限なし multiple が列内に複数 → 潜在 ambiguous」を warn できる (DR-021)。

## multiple のフィールド (統合形)

| フィールド | 主に効く文脈 | 役割 |
|---|---|---|
| `min` / `max` | positional | 個数 |
| `kind` | 両方 | list / set / map (値の構造) |
| `on_repeat` | option | append / override / ... |
| `item_separator` / `key_value_separator` | 両方 | 1引数内分割 |
| `key_from` | map | キー源 |

DR-008 の multiple に `min` / `max` が加わっただけ。フィールド数は実質増えていない。

## 効果

- 構造プリミティブが4つに確定 (repeat は属性に昇格 = 消滅)。
- `rm path...` / `mv a b c dst` / `cp src... dst` が書けるようになった (前回の穴を完全に塞いだ)。
- positional の個数と option の累積が対称に表現される。

## 関連

- DR-005 (type は要素単位の型)
- DR-008 (multiple フィールド) — min/max を追加して統合
- DR-015 (値の伝搬) — primitive 行を補完
- DR-021 (最長一致パースと ambiguous)
