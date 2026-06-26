# DR-004: options / positionals の2分割、サブコマンドは positionals 内の or

## 決定

要素の配置先を「マッチング戦略」で分割:

- **options**: ハイフンプレフィックス (`--`/`-`) で起動される opt 群、順不同
- **positionals**: 順序で消費される要素群 (純粋な位置消費 or 名前トリガ)

サブコマンド群は **positionals の中の or でラップ**して並べる:

```json
{
  "type": "command", "name": "git",
  "options": [
    {"name": "verbose", "type": "flag", "short": "v", "global": true}
  ],
  "positionals": [
    {
      "type": "or",
      "required": true,    // サブコマンド必須なら
      "children": [
        {"type": "command", "name": "commit", ...},
        {"type": "command", "name": "clone", ...}
      ]
    }
  ]
}
```

## 経緯

最初 Claude は3分割 (`options` / `positionals` / `commands`) を提案 (cobra/clap/argparse などのメジャーパーサに倣って)。

しかし `commands` 専用フィールドは「サブコマンドは特別」という暗黙を持ち込んでしまう。DR-002 の「全要素は同型」の原則と矛盾。

kawaz の発想:
> orに落とすのが良い気がするな。

- サブコマンドは「名前トリガで複数候補から1つ選ぶ」 = or の本来の意味
- 排他 = or の自然な動作
- 必須 = or に `required: true`
- 別の専用フィールドは不要

Claude が「サブコマンドを positionals に並べる」と書いて、kawaz から「これだと commit の後ろに clone が必要な定義になる、おかしい」と指摘。これは正論で、positionals 直下に並べると順次消費の意味になる。**or でラップが必要**。

## 効果

- 「サブコマンド」専用フィールドが消える (DR-002 と整合)
- 排他/必須/optional がすべて or + required で表現される
- positionals の意味論 (順序消費) を壊さない
- 構造的に AST を見れば挙動が分かる (or = 排他、明示)

## 採用しなかった案

### 案A: 3分割 `options` / `positionals` / `commands`

業界標準だが、commands を特別扱いする。DR-002 と矛盾。

### 案B: positionals に command を直接並べる + 暗黙自動 or 化

書く側は短いが、暗黙ルールで読みにくい。kawaz は明示性重視。

### 案C: matchBy フィールドで要素属性に持つ + flat children

要素ごとに `matchBy: "long" | "position" | "name"` で示す。flat な children に統一。書く側に判断負担、読みづらい。

## 関連

- DR-002 (全要素同型)
- DR-006 (name 重複ルール: セクション間も含む)
