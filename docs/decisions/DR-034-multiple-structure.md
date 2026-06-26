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

DR-008 は `multiple: {kind, item_separator, key_value_separator, on_repeat, key_from, ...}` で多くのフィールドを抱え、責務が混雑していた。DR-019 で repeat を multiple に統合したが、「option の複数回起動」と「positional のリピート個数」を混ぜていることが判明した。

→ multiple の責務を「複数値経路 (mapper/collector/separator) を起動するスイッチ」に絞る。個数制約 (positional のリピート) は別軸として分離。

### mergeable (kuu.mbt 本体側 DR) との接続

kuu.mbt 本体リポジトリの「マージ可能リストオプション +/- 修飾子と ... 展開」提案 [external: kuu.mbt DR-023] は、`--fields "+x,-y,..."` のような **差分指定 DSL** を first-class でサポートする提案。これは「リストを単純に作る」だけの単純な accumulator では表現できず、**piece の文字列レベルで `+/-` を解釈** + **prevs を見ながら合成** が必要。

→ mapper のシグネチャを `(piece: String, processor, prevs: T[]) → T[]` にすることで、mergeable も append も override も同じ枠で表現可能。kuu core の `Accumulator[T, U] = (T, U) → T` を一般化したもの。

### collector の命名

「`T[] → U` の最終変換」の名前として finalizer / collector / reducer / tuple / aggregator を検討。`reducer` は「畳んで1つにする」含意が強く、配列のまま返すケース (identity) に合わない。`tuple` は固定長の含意。**`collector`** が Java Stream API の Collector と意味が重なり、配列→Set/Map/List/集計値すべてに使えるため採用。

## 関連

- DR-007 (ref/link、差分上書き)
- DR-015 (値の発生と伝搬)
- DR-028 (type=参照糖衣)
- DR-036 (multiple registry、accumulators 拡張、collectors を filters registry に統合)
- [external: kuu.mbt DR-023] (mergeable リスト、本 DR の mapper シグネチャでサポート可能に)

## Superseded (歴史)

> **更新: 以下の記述は後続 DR で覆された。現役仕様の理解には不要、判断経緯としてのみ残す。**

### collector の独立 registry 化 (DR-036 で更新)

> **更新: DR-036 により本 DR の collector 独立 registry 構想は廃案。現役では filters registry に統合。本 DR の peaceProcessor/separator/mapper/collector の4要素構造自体は引き続き有効。**

本 DR の初期構想では collector を独立した registry として扱う想定だったが、DR-036 で **filters registry の延長で扱える** ことが整理された。`T[] → U` は filter のシグネチャに収まるため、collectors registry を新設せず filters registry に統合する。

### accumulators registry の扱い (DR-036 で更新)

> **更新: DR-036 により accumulators registry エントリは「属性セット」(mapper + default_collector + default_separator) に拡張され、multiple registry が新設された。本 DR の mapper シグネチャ自体は引き続き有効。**

本 DR では accumulator (mapper) を単純関数として扱っていたが、DR-036 で **accumulators registry エントリを「属性セット」(mapper + default_collector + default_separator) に拡張** + **multiple registry を新設** することで、multiple プリセットを参照糖衣として一貫させた。

### DR-008/019 の再編成扱い

> **更新: 本 DR は当初 DR-008 (multiple field) の再編成 + DR-019 (repeat→multiple 統合) の再分離として位置付けられたが、registry 構成は DR-036 でさらに整理された。DR-008/019 の旧表 (multiple フィールド統合形・mv の取り分) は本 DR で再編成済みのため現役仕様の参照先は DR-036 + 本 DR §決定。**

本 DR は当初 DR-008 (multiple field) を再編成し、DR-019 (repeat→multiple 統合) を再分離する位置付けだったが、registry 構成は DR-036 でさらに整理された。
