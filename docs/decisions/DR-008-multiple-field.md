# DR-008: 複数値関連を multiple フィールドに統合

## 決定

複数値関連の属性を `multiple` フィールド (オブジェクト) に統合する:

```json
"multiple": {
  "kind": "list" | "map" | "set" | "mergeable",
  "itemSeparator": ",",         // デフォルト (kind に応じて)
  "keyValueSeparator": "=",      // map のみ、デフォルト
  "onRepeat": "append"           // accumulator 戦略
}
```

- `kind` 必須: 構造を決める
- `itemSeparator`/`keyValueSeparator`: 1引数を分割する場合の区切り
- `onRepeat`: 複数回入力時の挙動

`multiple` 不在 = 単一値 (`override` のデフォルト動作)。

`type` は1要素分の型 (`string`/`int`/...) のみ。`type: "string[]"` のような配列型表記は廃止。

## 経緯

何段階かのリファクタリング:

### 第1段階: multipleValue: boolean

最初は `multipleValue: true` で配列化を示そうとした。kawaz から「true/false は意味曖昧」と。

### 第2段階: multipleValue: string

`"override"` / `"append"` / `"set"` / `"map"` / `"mergeable"` の語彙にする。

### 第3段階: type に配列型を持ち込み

`type: "string[]"` のように type に配列を含める案。kawaz の指摘:
> type:stringがmultiple指定があればstring[]になるってのが良くないかも。type:string[]を最初から許容する仕様にする。

### 第4段階: 配列型 + multipleValue 分離は冗長

`type` と `multipleValue` の両方で「複数値」を扱うと冗長。kawaz の整理:
> multipleValueは忘れた方が良いかも、あと分割系でフィールドが増えてるから分割関連だけsplitとかmultiple:{}でまとめていく?

結果: 「複数値関連」を `multiple: {...}` オブジェクトに統合、type は要素単位の型に絞る。

## multiple.onRepeat の語彙

| 値 | 挙動 |
|---|---|
| `"override"` (デフォルト) | 上書き (最後勝ち) |
| `"append"` | 配列に追加 |
| `"set"` | 重複排除した配列 |
| `"map"` | map に追加 (keyFrom or keyValueSeparator で key 決定) |
| `"mergeable"` | DR-023 マージリスト (拡張機能、opt-in) |

`true` / `false` / `increment` は語彙から外す。custom accumulator は registry で追加可能。

## 1回限定エラー

「複数回指定でエラーにしたい」ニーズは accumulator で表現可能:

```typescript
{
  accumulators: {
    "once": (current, next, ctx) => {
      if (ctx.alreadySet) throw new ValidationError(...);
      return next;
    }
  }
}
```

専用語彙を AST に増やさず、accumulator のカスタム実装で対応。

## itemSeparator のデフォルト

事故を防ぐため:
- 普通の `kind: "list"` などでは itemSeparator デフォルトなし (明示書きが必要)
- `kind: "map"` のときだけデフォルト `","` (k=v,k2=v2 パターン対応)

```json
// 単一引数を分割しない (デフォルト)
{"name": "tags", "multiple": {"kind": "list"}}
// → --tag a --tag b → ["a", "b"]
// → --tag "a,b,c" → ["a,b,c"] (1要素)

// 単一引数を分割
{"name": "tags", "multiple": {"kind": "list", "itemSeparator": ","}}
// → --tag a,b,c → ["a", "b", "c"]
```

kawaz の指摘:
> デフォルトはカンマ分割はせず複数回指定で累積のみがわかりやすいしじこがないか。

## keyFrom (動的名前付きスコープ)

map の場合、key をどこから取るかを `keyFrom` で指定:

```json
{
  "name": "upstream",
  "multiple": {"kind": "map"},
  "keyFrom": "name",
  "options": [
    {"name": "name", "required": true},
    {"name": "ttl"}
  ]
}
```

子要素の `name` の値が map のキーになる。jq の `--arg KEY VALUE` のようなパターンも同じ仕組みで書ける。

key として使われた要素は value 内にも残る (扱いやすさのため):
```json
{
  arg: {
    "X": {name: "X", value: "1"},
    "Y": {name: "Y", value: "2"}
  }
}
```

## 関連

- DR-009 (filter chain)
- DR-005 (type は要素単位の型)
