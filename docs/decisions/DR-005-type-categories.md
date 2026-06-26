# DR-005: type の3カテゴリと子からの値型推論

## 決定

`type` フィールドの値は以下の3カテゴリ:

| カテゴリ | 値の例 | 役割 |
|---|---|---|
| **値プリミティブ** | `string` / `number` / `int` / `float` / `boolean` / `path` / `file` / `dir` / `datetime` / カスタム | 値の型 |
| **挙動シュガー (値あり)** | `flag` / `count` / `command` | 値型 + 慣習挙動のプリセット |
| **挙動シュガー (副作用)** | `help` / (将来) `completion` | 起動時アクション |

`type` は1要素分の型を指す。`type: "string[]"` のような配列型表記はしない (DR-008 で multiple フィールドに分離)。

`type` を省略した場合、**子要素 (children / values) の値からの伝搬で型が決まる**。明示書きは「アサーション」として、子の伝搬と一致しない場合は型エラー。

## 経緯

最初は `type` フィールドに or/sequence などの構造プリミティブも混在させていた。kawaz の整理で:
- 構造 (or / sequence) は children の中の構造表現に
- type は「この要素1個分の値型」と「起動挙動シュガー」に絞る

「子からの伝搬」については:

> 例2はcolorにtypeは不要で子から伝搬で決まる形かな。書いても良いけどその場合は楚から伝搬する可能性のある方との一致が必要?

これで `type` 明示は「アサーション」、デフォルトは「推論」と整理。

シュガー (flag/count/command/help) は、各々が独立した type ではなく、値型+挙動のプリセット:
- `flag` = boolean + defaultValue=false + 起動で true セット
- `count` = number + defaultValue=0 + 起動で increment
- `command` = name でトリガ + children をスコープ
- `help` = 起動時に ParserContext の help フラグセット

version は専用 type ではなく、**ただのフラグ**。結果オブジェクトの `result.version` を見てアプリがバージョン出力。AST にバージョン文字列を持たせない。

> versionは特殊化する必要無いに改め。ただのフラグで、パース結果を見てパーサの外でアプリがバージョン出力するかのフラグを見て出すだけのもので、引数パースの結果にversion値を持つ必要性はなかった。

## 効果

- type の語彙が明確に分類される
- 構造プリミティブが type から消える
- 子からの伝搬で書く側が楽 (型を毎回書かなくてよい)
- 明示書きは型チェックの安全弁

## 関連

- DR-002 (全要素同型、シュガーは愛称)
- DR-008 (multiple フィールド、配列型表記の廃止)
- DR-010 (type registry)
