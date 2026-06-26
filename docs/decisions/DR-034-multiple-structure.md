# DR-034: multiple の構造モデル (peaceProcessor / separator / mapper / collector)

## 決定

multiple 関連の処理を以下の4要素で構成する:

```
入力: raw_string (1引数 or 複数回起動の各回)
  ↓ separator (String → String[]、任意)
[piece1, piece2, ...] (single なら長さ1)

各 piece に対して peaceProcessor を適用:
  piece: String
    ↓ pre  (FilterChain[String, String])
    ↓ parse (String → T、types registry の value_parser)
    ↓ post  (FilterChain[T, T]、各 piece に対する検証)
  T

mapper で累積:
  (piece: String, processor: String→T, prevs: T[]) → T[]
       ↑ +/- 等の修飾子はここで剥がして合成可能 (mergeable 等)

collector で最終形へ:
  T[] → U
```

### multiple 無しは「縮退」として統一モデルに収まる

multiple を書かないノードは、上記モデルの特殊ケース:

- separator: なし (常に長さ1の `[piece]`)
- mapper: override (prevs を無視して `[processor(piece)]` を返す)
- collector: unwrap_single (`[t] → t`、要素数1の unwrap)

結果として「multiple 無し = peaceProcessor 一本で終わる」と同等になる。

これにより:
- パイプラインの説明が1本で済む
- 実装の分岐が消える (最適化として fast path を持つのは可)
- 「単一値処理」と「複数値処理」を別概念として説明する必要がない

### type と multiple は同じ属性平面への参照

`type: "string"` と `multiple: "append"` は包含関係ではなく、**同じ属性平面の異なる断面への参照**。

```
属性平面 (全属性): processor / default / mapper / separator / collector / 入力消費数 / ...

type が主に指す断面:    processor, default, 入力消費数 (mapper/collector はデフォルト)
multiple が主に指す断面: mapper, collector, separator (processor/default はデフォルト)
```

両者が同じ属性 (例: mapper) を指す場合、合成順:

```
1. プリセットなしの初期値 (組み込みデフォルト)
2. type プリセットの値で上書き
3. multiple プリセットの値で上書き
4. ユーザがその node に直接書いた値で上書き (最優先)
```

後ろほど優先。DR-007 の ref 継承+差分上書きと同じ流儀。ユーザ認知上は別フィールドだが、機構上は同じ「definitions/registry への参照糖衣」(DR-028)。

## 経緯

### 当初の DR-008/019 の問題

DR-008 は `multiple: {kind, item_separator, key_value_separator, on_repeat, key_from, ...}` で多くのフィールドを抱え、責務が混雑していた。DR-019 で repeat を multiple に統合したが、kawaz の指摘で「option の複数回起動」と「positional のリピート個数」を混ぜていることが判明した。

kawaz:
> multiple は min/max とか言ってるけどそれもう元のマルチプル(オプション複数)の文脈ほぼ無くなってない? それオプションじゃなくてポジショナルのリピートの話じゃない?

→ multiple の責務を「複数値経路 (mapper/collector/separator) を起動するスイッチ」に絞る。個数制約 (positional のリピート) は別軸として分離。

### mergeable (DR-023 kuu本体) との接続

kuu リポジトリの DR-023「マージ可能リストオプション +/- 修飾子と ... 展開」は、`--fields "+x,-y,..."` のような **差分指定 DSL** を first-class でサポートする提案。これは「リストを単純に作る」だけの単純な accumulator では表現できず、**piece の文字列レベルで `+/-` を解釈** + **prevs を見ながら合成** が必要。

kawaz:
> ([peace])→peace を指定してるみたいな感じでもあるのか? セパレータ指定がないと内部的には要素数1の[peace]に常にしてしまってデフォルトmultipleは prev 無視して peace→[peace] を返して finalizer に [0] 的なのがあると考えることもできる?

→ mapper のシグネチャを `(piece: String, processor, prevs: T[]) → T[]` にすることで、mergeable も append も override も同じ枠で表現可能。kuu core の `Accumulator[T, U] = (T, U) → T` を一般化したもの。

### collector の命名

「`T[] → U` の最終変換」の名前として finalizer / collector / reducer / tuple / aggregator を検討。`reducer` は「畳んで1つにする」含意が強く、配列のまま返すケース (identity) に合わない。`tuple` は固定長の含意。**`collector`** が Java Stream API の Collector と意味が重なり、配列→Set/Map/List/集計値すべてに使えるため採用。

## 関連

- DR-007 (ref/link、差分上書き)
- DR-008 (multiple field) — 本 DR で再編成
- DR-015 (値の発生と伝搬)
- DR-019 (repeat→multiple 統合) — 本 DR で再分離
- DR-021 (最長一致と ambiguous)
- DR-028 (type=参照糖衣)
- DR-036 (multiple registry、accumulators 拡張)
- kuu DR-023 (mergeable リスト、本 DR の mapper シグネチャでサポート可能に)
