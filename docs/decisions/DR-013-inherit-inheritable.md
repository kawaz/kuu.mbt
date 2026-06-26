# DR-013: inherit (default_value 継承) と inheritable (祖先スコープからの設定)

## 決定

階層的な値継承を2つの直交フィールドで表現:

### inherit: true — default_value の取得先を祖先 scope に変える

```json
{"name": "ttl", "type": "number", "inherit": true}
```

- 自身に値がない (committed=false) → 祖先 scope chain で同 name の値を探す
- `inherit` と `default_value` は排他 (inherit を書いたら default_value は祖先で持つ)

### inheritable: true — 祖先 scope からも CLI 上で書ける

```json
{
  "name": "ttl",
  "type": "number",
  "inheritable": true,
  "default_value": 60
}
```

- 自分の scope では `--ttl`
- 祖先 scope では prefix 付き名前 (prefix 生成の具体ルールは本 DR では確定しない、後述 Superseded 参照)
- 各 scope で書かれた値は、その scope 配下のインスタンスのデフォルトに

## 経緯

「scope chain での値継承」を AST で表現する話題:

### inherit の意味付け

最初 Claude が `inherit: true` + `default_value: 60` の併用ありを提案。kawaz:
> inherit:trueとdefault_valueが両方あるのが違和感。inherit:trueはデフォルト値を親から取るイメージか？

→ **inherit と default_value は排他**。inherit を書いたら祖先で default_value を持つ。

### 「主体は1箇所、上位は間接設定」の発想

kawaz:
> またはここで例にしたttlはsocketが使用する主体なオプションとしよう。親やグローバルではあくまで広域でまとめて設定できる余地があるだけ。みたいな。その場合定義は実はsocketのオプションとしてだけ書いて。nameが衝突しない限りにおいてより上のスコープで設定することもできますよ。

これは新しい発想。`inheritable: true` で「**この opt は祖先 scope からも書ける**」を明示。

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
      "key_from": "name",
      "options": [
        {"name": "name", "required": true},
        {
          "name": "socket",
          "multiple": {"kind": "map"},
          "key_from": "path",
          "positionals": [
            {"name": "path", "required": true}
          ],
          "options": [
            // ttl は socket の opt として定義 (主体)
            // inheritable: true で祖先 scope からも書ける
            {
              "name": "ttl",
              "type": "number",
              "default_value": 60,
              "inheritable": true
            }
          ]
        }
      ]
    }
  ]
}
```

CLI 入力 (祖先 scope での prefix 形は本 DR では具体化しない。下記は prefix が `--<親要素名>-<name>` 形になる場合の例示):
```bash
# socket レベル
myapp --upstream --name up1 --socket /s1 --ttl 60

# upstream レベル (祖先 scope から書く例)
myapp --upstream --name up1 --socket-ttl 60 --socket /s1 --socket /s2

# global レベル
myapp --socket-ttl 60 --upstream --name up1 --socket /s1
```

## 関連

- DR-006 (scope chain)
- DR-008 (key_from、動的名前付きスコープ)
- DR-022 (フィールド名 snake_case 統一)
- DR-031 (値源優先順位、inherit は default の上・config の下に位置づけ)

## Superseded (歴史)

> 以下の記述は後続 DR で覆された / 本 DR では確定しなかった。現役仕様の理解には不要、判断経緯としてのみ残す。

### フィールド名表記 `defaultValue` / `keyFrom` (DR-022 で更新)

本 DR 制定時は `defaultValue` / `keyFrom` (camelCase) で記述していたが、DR-022 で全フィールド snake_case 統一が決まったため、現役表記は `default_value` / `key_from`。本文は更新済み (上記は最新表記)。

### inherit の位置づけ (DR-031 で更新)

> **更新: DR-031 で値源の優先順位 (CLI > env > config > inherit > default) が整理され、inherit は値源スタックの1段として位置づけ直された。本 DR の意味論 (祖先 scope chain から同 name の値を探す) は引き続き有効。他の値源との合成は DR-031 を参照。**

### prefix 生成ルール (本 DR では確定せず)

> **本 DR では prefix 生成ルールの具体仕様 (案A=直近の親要素名のみ / 案B'=相対パス全部 / 案A+B'=衝突時のみ長いパス) は確定していない。実装着手時に別 DR で確定する。本文の祖先 scope CLI 例は prefix 形の一例であり、確定仕様ではない。**

経緯としては「基本は案A、ヘルプ表示の見せ方は後で詰める」方向で議論したが、ヘルプ肥大化の懸念 (kawaz: 「A+B'？helpがウザくなりそうなのが心配ではある。」) があり、本 DR では結論を出していない。

### ヘルプ表示への影響 (本 DR では確定せず)

> **どこまで help に出すか、`--help-all` で全表示するか等のヘルプ仕様は本 DR では確定しない。prefix 生成ルールと合わせて別 DR で確定する。**
