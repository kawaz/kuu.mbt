# DR-012: 制約は要素属性として書く (groupRules を作らない)

## 決定

制約は要素自身の属性として書く:

```json
{
  "name": "...",
  "required": true,                  // 単独必須
  "exclusiveGroup": ["format"],      // 排他グループ所属 (複数所属可)
  "requires": ["other-name"]         // 依存
}
```

「グループ全体に対するルール」を別場所 (`groupRules`) に書く設計はしない。

## 経緯

Claude が `groupRules` で複雑な制約セマンティクスを表現しようとした:
```json
"groupRules": {
  "format": {"atMostOne": true},
  "dest": {"atLeastOne": true, "atMostOne": true}
}
```

kawaz から指摘:
> groupRulesとか突然出てきたけど引数定義と遠くなるしわかりにくい。なんでこんなの必要?

→ 設計を後退させて、各制約を要素属性で表現できる範囲に限定。

## 各制約の表現

### required (単独必須)

```json
{"name": "filename", "required": true}
```

`required` は **boolean のみ**。グループ名を取らない (Claude が一度提案して却下された)。

### グループ的必須 (最低1つ必須) は or + required

```json
{
  "type": "or",
  "required": true,
  "children": [
    {"name": "output", "type": "string"},
    {"name": "to-stdout", "type": "flag"}
  ]
}
```

or の本来の意味 (1つだけ選ぶ) + required (必ず1つ) = exactly one。

### exclusiveGroup (排他)

```json
{"name": "json", "exclusiveGroup": ["format"]}
{"name": "yaml", "exclusiveGroup": ["format"]}
```

- 同じグループ名の要素群が排他
- `string[]` で複数グループ所属可能 (「同じ要素が複数の排他軸に属する」レアケースを許容)

### requires (依存)

```json
{"name": "decrypt", "requires": ["key-file"]}
```

自分が起動された時、指定された name の要素群も起動されている必要がある。

### サブコマンドの排他

`type: "command"` 群を `or` でラップ (DR-004) すれば、or の本来の動作で排他になる。
`exclusiveGroup` を `type: "command"` に暗黙付与するアイデアもあったが、or で表現する方向に統一。

## 効果

- 制約が AST 要素ツリーから外れない
- 専用フィールド (`groupRules`) が不要
- 各要素を見れば制約が分かる

## 関連

- DR-002 (全要素同型)
- DR-004 (or でサブコマンドの排他を表現)
