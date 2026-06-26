# DR-015: 値の発生と伝搬の構造的セマンティクス

## 決定

AST 要素の値の決定は **構造的セマンティクス** (値が tree を下から上に流れる) で表現する:

| type | 値の発生 | 親への伝搬 |
|---|---|---|
| primitive (`string`/`number`/...) | `value` 持つなら literal、無いなら CLI から1引数消費 | 自身の値を親に渡す |
| `exact` | `value` 持つなら literal、無いなら値なし | 値があれば親に渡す |
| `or` | 選ばれた子の値 | 子の値をそのまま伝搬 |
| `serial` / children sequence | 子の値の配列 (or 単独要素なら単独) | 配列または単独値を親に伝搬 |

リテラルは primitive type + value のシュガー:
- `"red"` → `{"type": "string", "value": "red"}`
- `255` → `{"type": "number", "value": 255}`
- `true` → `{"type": "boolean", "value": true}`

## 経緯

kawaz の整理:
> valueを持ってる要素が値を持つ。親に伝搬。

これでまず or の意味論が明確になる:

```json
{
  "name": "color",
  "type":"or",
  "children": [
    {"type":"exact", "name":"--no-color", "value": {"type":"string", "value":"none"}},
    {"type":"serial", "array": false, "children": [
      {"type":"exact", "name":"--color"},
      {"type":"or", "children": [
        {"type":"string", "value":"none"},
        {"type":"string", "value":"always"},
        {"type":"string", "value":"auto"}
      ]}
    ]}
  ]
}
```

- 子のいずれかが消費される
- 消費された子が値を持てば、それが or に伝搬
- 親 (この場合 color という name) に最終値が入る

## variant が自然に表現される

`long: ["no:set:none"]` の variant は:

```json
{
  "name": "color",
  "long": ["no:set:none"]
}
```

これは AtomicAST で:

```json
{
  "type": "or",
  "name": "color",
  "children": [
    /* --color X 入口 */
    {
      "type":"exact",
      "name":"--no-color",
      "value": {"type":"string", "value":"none"}
    }
  ]
}
```

`--no-color` の exact がマッチすると `value: "none"` の literal が発生、or に伝搬、color の値になる。

**effect 語彙 (`set` / `default` / `empty`) は不要に近い**。`value` フィールドに literal を埋めるだけで「セット」が表現される。

## リテラルもシュガー

```json
"value": ["red", "green", "blue"]
```

正規形:
```json
"value": {
  "or": [
    {"type": "string", "value": "red"},
    {"type": "string", "value": "green"},
    {"type": "string", "value": "blue"}
  ]
}
```

さらに AtomicAST レベルで「value 持ち string」を `exact` に変換する設計も可能 (この詳細は AtomicAST 確定待ち)。

## values と children の意味分離

最初は `value` / `values` / `children` を混同していた。kawaz の整理:

> children["red", "green", "blue"] コレはちがうな。これだとexact3連な引数消費をするだけになる気がするな。やはりvalueとchildrenは別か?valuesはchildrenをいい感じに構築するショートハンドってのが落とし所か?

- `children`: 起動後に順次消費する子要素群
- `values`: その要素の取りうる値の選択肢 (or のショートハンド)

`values` 内の要素が or 構造のブランチに、各リテラルが exact マッチに展開される。

## あと勝ち mutation

値プレースホルダーは型のゼロ値/null で初期化、CLI 入力順に mutation:

```bash
--since A --timerange 'X..Y' --since B
# 1. since_value = A
# 2. timerange でセット → since_value=X, until_value=Y
# 3. since_value = B (最後勝ち)
# 最終: since=B, until=Y, timerange=[B, Y]
```

複雑な競合解決ルール不要、CLI 入力順がそのまま勝者。

## count の特殊扱い

count はこの構造的セマンティクスでは表現できない (現在値依存の increment は accumulator の仕事)。

- flag: `value: true` の literal でセット (構造的)
- count: accumulator が `(current) => current + 1` を担う (非構造的、reduce)

count だけ特殊だが、count は「type=count のシュガー」として隠蔽されるので、AST 全体の構造的セマンティクスは保たれる。

## 関連

- DR-005 (type の子からの伝搬)
- DR-008 (accumulator)
- DR-011 (variant DSL の本質)
