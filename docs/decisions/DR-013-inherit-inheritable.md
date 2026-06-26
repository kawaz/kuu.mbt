# DR-013: inherit (defaultValue 継承) と inheritable (祖先スコープからの設定)

## 決定

階層的な値継承を2つの直交フィールドで表現:

### inherit: true — defaultValue の取得先を祖先 scope に変える

```json
{"name": "ttl", "type": "number", "inherit": true}
```

- 自身に値がない (committed=false) → 祖先 scope chain で同 name の値を探す
- `inherit` と `defaultValue` は排他 (inherit を書いたら defaultValue は祖先で持つ)

### inheritable: true — 祖先 scope からも CLI 上で書ける

```json
{
  "name": "ttl",
  "type": "number",
  "inheritable": true,
  "defaultValue": 60
}
```

- 自分の scope では `--ttl`
- 祖先 scope では `--<scope-name>-ttl` (prefix 自動付与で衝突回避)
- 各 scope で書かれた値は、その scope 配下のインスタンスのデフォルトに

## 経緯

「scope chain での値継承」を AST で表現する話題:

### inherit の意味付け

最初 Claude が `inherit: true` + `defaultValue: 60` の併用ありを提案。kawaz:
> inherit:trueとdefaultValueが両方あるのが違和感。inherit:trueはデフォルトValueを親から取るイメージか？

→ **inherit と defaultValue は排他**。inherit を書いたら祖先で defaultValue を持つ。

### 「主体は1箇所、上位は間接設定」の発想

kawaz:
> またはここで例にしたttlはsocketが使用する主体なオプションとしよう。親やグローバルではあくまで広域でまとめて設定できる余地があるだけ。みたいな。その場合定義は実はsocketのオプションとしてだけ書いて。nameが衝突しない限りにおいてより上のスコープで設定することもできますよ。

これは新しい発想。`inheritable: true` で「**この opt は祖先 scope からも書ける**」を明示。

### prefix 自動付与で衝突回避

祖先 scope で書く時は `--ttl` ではなく `--socket-ttl` のような prefix 付き名前にすることで、scope 内の同 name 衝突を自動回避。

prefix 生成案:
- **案A** (直近の親要素名のみ): `--socket-ttl` (1階層飛ばし)
- **案B'** (相対パス): `--upstream-socket-ttl` (経由全部)
- **A or A+B'** (衝突時のみ長いパス): デフォルト A、必要なら長いパスも受け付ける

kawaz: 「A+B'？helpがウザくなりそうなのが心配ではある。」

→ 基本は **案A、ヘルプ表示の見せ方は後で詰める**。

### 範囲制限はしない

「inheritable をどこまでの祖先で有効にするか」のような範囲制限フィールドは入れない。デフォルトで全階層、特殊な制限ニーズは出てきてから考える。

## 効果

- 階層的継承が AST 仕様で明示的に表現される
- 主体定義は 1箇所、上位は間接的に設定する設計が自然に書ける
- 暗黙ルールなし

## 例: ttl の継承

```json
{
  "type": "command", "name": "myapp",
  "options": [
    {
      "name": "upstream",
      "multiple": {"kind": "map"},
      "keyFrom": "name",
      "options": [
        {"name": "name", "required": true},
        {
          "name": "socket",
          "multiple": {"kind": "map"},
          "keyFrom": "path",
          "positionals": [
            {"name": "path", "required": true}
          ],
          "options": [
            // ttl は socket の opt として定義 (主体)
            // inheritable: true で祖先 scope からも書ける
            {
              "name": "ttl",
              "type": "number",
              "defaultValue": 60,
              "inheritable": true
            }
          ]
        }
      ]
    }
  ]
}
```

CLI 入力:
```bash
# socket レベル
myapp --upstream --name up1 --socket /s1 --ttl 60

# upstream レベル (--socket-ttl で書く)
myapp --upstream --name up1 --socket-ttl 60 --socket /s1 --socket /s2

# global レベル
myapp --socket-ttl 60 --upstream --name up1 --socket /s1
```

## 未確定

- prefix 生成ルールの詳細 (案A 確定、A+B' のサポートは検討中)
- ヘルプ表示への影響 (どこまで help に出すか、`--help-all` で全表示するか)

## 関連

- DR-006 (scope chain)
- DR-008 (keyFrom、動的名前付きスコープ)
