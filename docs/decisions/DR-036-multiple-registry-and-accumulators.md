# DR-036: multiple registry の追加、accumulators の属性セット拡張、collectors は filters 統合

## 決定

### multiple registry の追加 (7→8 区分)

DR-010 の registry 区分に **multiple** を追加。multiple フィールドの値は multiple registry から引かれる。

```
multiple registry: {
  "append": {
    mapper: "append",          // accumulators registry から引く
    collector: なし,           // collector は省略時 mapper 連動デフォルト
    separator: なし,
  },
  "merge": {
    mapper: "merge",
    separator: ",",
  },
  "set": {                      // よくある組み合わせを名前で提供
    mapper: "append",
    collector: "to_set",       // filters registry から (T[]→Set<T>)
  },
  "map": {
    mapper: "append",
    collector: "to_map",
  },
}
```

multiple registry の各エントリは「mapper + collector + separator のセットを1つの名前にまとめた糖衣プリセット」。

### accumulators registry を属性セットに拡張

DR-010 では accumulators は単純な関数 `(T, U) → T` の登録だった。本 DR で **属性セット** (mapper 関数 + デフォルト collector + デフォルト separator など) に拡張する:

```
accumulators registry: {
  "append": {
    mapper: (piece, processor, prevs) → T[],
    default_collector: "identity",
    default_separator: なし,
  },
  "merge": {
    mapper: (piece, processor, prevs) → T[],  // +/-/... 解釈
    default_collector: "identity",
    default_separator: ",",
  },
  "override": {
    mapper: (piece, processor, _prevs) → [processor(piece)],
    default_collector: "unwrap_single",
  },
  "increment": {
    mapper: (_piece, _processor, prevs) → prevs.push(1),  // count 用
    default_collector: "sum",
  },
}
```

各 accumulator は「自分にとって自然な collector」をデフォルトとして持つ。これにより `multiple: "append"` だけ書いた場合に、collector が自動で identity になる (override なら unwrap_single)。

### collectors registry は新設しない (filters で代替)

「`T[] → U` の最終変換」を扱うために独立 registry を立てる案も検討したが、**filters registry の延長で扱える**ことが判明:

- filters の型は `FilterChain[A, B] = A → B raise ParseError`
- `to_set: T[] → Set<T>`、`to_map: T[] → Map<K,V>`、`sum: number[] → number` 等は全て filter として登録可能
- kuu core の `after_post: FilterChain[T, T]` がすでにこの位置を持つ

新規 registry を作らず、filters の中に「累積後の最終 filter」を登録する形で済む。

### multiple の書き方

```
multiple: "append"
   ↓
multiple registry["append"] を引く → {mapper:"append", collector:なし, separator:なし}
   ↓
mapper は accumulators registry から、collector は (なしなので) accumulator の default_collector へ
```

オブジェクト形式での部分指定も可:

```
multiple: {mapper: "append", collector: "to_set"}
   ↓
mapper は accumulators から、collector は filters から
multiple registry を経由しない直接指定
```

### type の post と multiple の post の合成

両者は位置が違うので自然な順序で合成される:

```
peaceProcessor 内:
  piece (String)
    → pre filter (FilterChain[String, String])
    → parse (types registry の value_parser、String → T)
    → post (type のもの、FilterChain[T, T]、各 piece に効く)
  T

multiple 経路:
  [T, T, ...]
    → mapper で累積 → T[]
    → collector (filters registry のもの、T[] → U、累積結果に効く)
  U
```

type の post は **各 piece 単位**、multiple の collector は **累積後**。位置が違うので衝突しない。

## registry 区分の現状 (8区分、変更余地あり)

```
types         値型 (peaceProcessor の構成プリセット)
filters       純粋 FilterChain[A,B] (collector もここ)
accumulators  mapper の属性セット
multiple      mapper+collector+separator の糖衣プリセット (新規)
handlers      command の実行フック
envProvider   環境変数解決
completers    動的補完生成
defaultFns    デフォルト値の動的生成
```

ユーザの認知層:

| 状況 | 触る registry |
|---|---|
| 普通の使い方 | 何も触らない (multiple: "append" だけ書く) |
| よくある組み合わせを使いたい | multiple registry の組み込み (append/merge/set/map) |
| 独自の組み合わせを作る | definitions.multiple に新規プリセット登録 |
| 変なことをしたい | multiple: {mapper:..., collector:...} で個別指定 |

## 経緯

kawaz の整理:

> ユーザが作ることはほぼないと思うが、糖衣用の multiple レジストリを置いて {append:{mapper,collector}} とか置いといても良い気がする。基本は組み込みの3種で済むので multiple レジストリを見ることは無いと思うが API や構造的にはこうなってると見せておくみたいな。もしユーザが変な使い方を思いつくなら好きにしろ的な?

これは DR-010 の方針「フィールド名で registry が暗黙決定」を `multiple` フィールドにも素直に適用した形。

### collector を独立 registry にしなかった理由

「mapper と collector を独立に組み合わせたい」ニーズはあるが、collector の型 (`T[] → U`) が filter の型 (`A → B raise ParseError`) に完全に乗る。新規 registry を作らず filters で済むなら、責務を増やさない方が筋が良い。

## 関連

- DR-008/019 (multiple field) — 本 DR で再編成
- DR-009 (filter chain)
- DR-010 (外部レジストリ) — 区分を 7→8 に拡張
- DR-021 (最長一致)
- DR-028 (type=参照糖衣、解決順)
- DR-034 (multiple の構造モデル)
- DR-035 (definitions の区分対称)
