# DR-022: AST キー名は snake_case を正規形、case 変換は pluggable

## 決定

### キー名の正規形 = snake_case

AST のフィールド名 (キー名) は **snake_case** を wire format (JSON 正規形) として固定する。

```
export_key / item_separator / key_value_separator / on_repeat / key_from
default_value / long_prefix / short_prefix / exclusive_group
```

### case 変換は pluggable

wire ⇄ 各言語バインディング間の case 変換は **pluggable な層**とする。各言語に「素直なデフォルト変換器」を1つ用意するが **固定はせず差し替え可能**。

- TS / MoonBit のデフォルト: camelCase 変換 (snake のまま使う設定も可)
- Python / Rust のデフォルト: 無変換 (snake がネイティブ)
- 特殊要求 (kebab で受けたい等) も変換器を差し込めば対応

これは DR-010 (外部レジストリの外部注入) と同じ構造。case 変換も「キー名変換 provider」として外から差すだけで、新概念ではない。

### 適用範囲はキー名のみ

case ルールは **AST のフィールド名 (キー名) にのみ**適用。値の語彙は別ルール:

- enum 値 (`on_repeat` の値など): 別途規定 (lowercase 単語想定、未確定)
- variant DSL (`"no:set:false"`): コロン区切り、独自
- CLI 値 (`--no-color`, `--export-key`): kebab-case (CLI 慣習であってキー名ではない)

## 経緯

camelCase と snake_case で検討。kawaz:

> URL とか ID みたいなのをどう扱うべきか (= 曖昧さ問題)、現実世界での言語利用形式との摩擦という点で snake_case 派寄り。

camelCase は頭字語 (acronym) の扱いに正解がなく (`exportUrl` / `exportURL`、`userId` / `userID`)、「URL→Url と書く」等のローカル規約を持ち込む必要がある。snake_case は `export_url` / `user_id` / `https_url` で機械的に一意。これは kuu の思想「暗黙ルールを増やさない・明示性重視」に合致する。

現状の AST に頭字語を含むキーは存在せず (棚卸し済み)、snake へ倒す書き換えコストは最小。既存 DR の camelCase は CONTEXT.md が「未確定」と明記しており、追認の破棄ではなく正式化前の整え。

case 変換の固定について kawaz:

> 言語によって変換固定より精々デフォルトとして case 変換は指定可能というかプラガブルで置いといても良い。

→ 「言語ごとに変換固定」自体が暗黙ルールになるため、pluggable に。正規形は1つ (snake)、変換は外から差せる。

## 変更対象フィールド (既存 DR の追従)

camelCase → snake_case:

`exportKey`→`export_key` / `itemSeparator`→`item_separator` / `keyValueSeparator`→`key_value_separator` / `onRepeat`→`on_repeat` / `keyFrom`→`key_from` / `defaultValue`→`default_value` / `longPrefix`→`long_prefix` / `shortPrefix`→`short_prefix` / `exclusiveGroup`→`exclusive_group`

変更なし: `id` / `name` / `type` / `value` / `values` / `short` / `long` / `multiple` / `options` / `positionals` / `commands` / `children` / `required` / `export` / `inherit` / `inheritable` / `config` / `min` / `max` / `kind`

## 効果

- 頭字語が機械的に一意、ローカル規約不要。
- kuu の「暗黙ルールを増やさない」思想に合致。
- 正規形は snake 1つ、各言語は pluggable な変換器で自然に書ける。
- 変換を言語ごとに固定しないため、新しい暗黙ルールを増やさない。

## 関連

- DR-010 (外部レジストリの外部注入) — case 変換 provider の土台
- DR-029/030 (cross-language portability)
