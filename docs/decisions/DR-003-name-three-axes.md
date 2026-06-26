# DR-003: name は3軸を兼任、必要に応じて exportKey で分離

## 決定

`name` フィールドは以下の3つの役割を兼ねる:

1. **CLI マッチング (軸1)**: long opt の `--name` 生成、short opt のもとになる name、command のトリガ name、positional のヘルプ表示
2. **結果 export key (軸2)**: 結果オブジェクトのキー (デフォルト name そのまま)
3. **AST 内部参照 (軸3)**: ref/link の参照対象 (scope 内で重複禁止)

別軸にしたいケースのために独立した2フィールド:

```json
{
  "name": "FROM",          // 軸3 内部参照 + 軸1 ヘルプ表示
  "exportKey": "from",     // 軸2 別キーで export
  "export": false          // 軸2 抑制
}
```

- `exportKey`: 別キーで export (デフォルト name 流用)
- `export: false`: export 抑制 (配列要素として扱う)

## 経緯

最初は name の3軸を全部混ぜていて、kawaz から「positional でも名前で export 可能だし、いまいち曖昧」と指摘。

> nameはhelp用に使うだけで取り出しは名無しのリストになって欲しい（--color R G B）とか、ポジショナルでも名前で取り出したい（rsync FROM TO）とかユースケースは色々あると思う。

Claude が `namedExport: boolean | string` のような複合フィールドを提案したが、kawaz から「ユニオン型ダメ、独立フィールド」と。

> exportKey:string 別名を着けたい
> export: false  exportを抑制したい
> の二つをオプショナルで用意するのが素直か?

## 効果

- 普通の opt は何も書かなくても自然に動く (name がそのまま使われる)
- 別キーで export したいケースは `exportKey` だけ書く
- 配列要素にしたいケースは `export: false` だけ書く
- 3軸が独立した役割を持ち、混乱しない

## 重複ルール

- `name` はスコープ内 (同じ command 配下の options + positionals すべて) で一意
- 重複 = ref/link 解決の曖昧化 + 結果キー衝突
- `id` (グローバル一意、オプション) はテンプレート用

## 関連

- DR-004 (3分割を捨てて or で書く方向に)
- DR-006 (name 重複ルールはセクション間も含む)
