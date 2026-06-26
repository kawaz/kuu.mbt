# DR-008: 複数値関連を multiple フィールドに統合

## 決定

> **注**: 本 DR の JSON 例は制定時の camelCase 表記。現役 (snake_case) の対応は末尾 Superseded セクションを参照 (`itemSeparator → item_separator` 等)。

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

## 設計原則: 専用語彙を増やさず accumulator カスタム実装で対応

特殊な挙動 (1回限定エラー、独自集約ロジック等) のために AST の専用語彙を増やさない。
accumulator (= onRepeat 戦略) は registry で拡張可能であり、ユーザ定義の関数で対応する。
この原則は本 DR 全体を貫く方針であり、後続 DR (DR-034 の peaceProcessor/separator/mapper/collector 分解、DR-036 の multiple registry) もこの原則の延長線上にある。

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

専用語彙を AST に増やさず、accumulator のカスタム実装で対応 (上記「設計原則」の具体例)。

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

- DR-005 (type は要素単位の型)
- DR-019 (repeat 統合で min/max 追加)
- DR-022 (フィールド名 snake_case 化、itemSeparator→item_separator 等)
- DR-034 (multiple の4要素再構成: peaceProcessor/separator/mapper/collector)
- DR-036 (multiple registry 追加、collectors は filters 統合)

## Superseded (歴史)

> **更新: 本 DR の `multiple` フィールド構造 (`{kind, itemSeparator, keyValueSeparator, onRepeat}`) は DR-019 / DR-034 / DR-036 で段階的に再編成された。現役の構造定義は DR-036 を参照。本 DR の「設計原則: 専用語彙を増やさず accumulator カスタム実装で対応」「`type` は要素単位の型」「`multiple` 不在 = 単一値」「keyFrom による動的名前付きスコープ」は引き続き有効。**

### multiple のフィールド構造 (DR-019 / DR-034 / DR-036 で更新)

本 DR で定めた `multiple: {kind, itemSeparator, keyValueSeparator, onRepeat}` というフィールド構造は、その後段階的に再編成された:

- **DR-019**: repeat 統合で min/max 追加
- **DR-034**: multiple の4要素再構成 (peaceProcessor / separator / mapper / collector)
- **DR-036**: multiple registry 追加、collectors は filters に統合

現役の構造定義は DR-036 を参照。

### フィールド名の表記 (DR-022 で snake_case 化)

本 DR では `itemSeparator` / `keyValueSeparator` / `onRepeat` / `keyFrom` のように camelCase で書いている。DR-022 で AST フィールド名は snake_case に統一されたため、現役の表記は `item_separator` / `key_value_separator` / `on_repeat` / `key_from`。

本 DR 内の camelCase 表記は時点記録としてそのまま残してある。

### 段階的検討の経緯

本 DR に至るまで、以下の段階を経た:

1. **multipleValue: boolean** — 配列化を true/false で示そうとしたが、kawaz から「true/false は意味曖昧」と指摘
2. **multipleValue: string** — `"override"` / `"append"` / `"set"` / `"map"` / `"mergeable"` の語彙化
3. **type に配列型を持ち込み** — `type: "string[]"` 案。kawaz: 「type:stringがmultiple指定があればstring[]になるってのが良くないかも。type:string[]を最初から許容する仕様にする。」
4. **配列型 + multipleValue 分離は冗長** — kawaz: 「multipleValueは忘れた方が良いかも、あと分割系でフィールドが増えてるから分割関連だけsplitとかmultiple:{}でまとめていく?」 → 「複数値関連」を `multiple: {...}` に統合、type は要素単位に絞る、という現在の決定に到達。
