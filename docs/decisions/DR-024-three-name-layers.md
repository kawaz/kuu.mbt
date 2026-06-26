# DR-024: 名前は3層 (key name / def name / value_name) に分離

## 決定

ノードに関わる「名前」は3つの独立した層に分かれる。混同しない。

| 名前 | フィールド/場所 | 役割 | 結果露出 |
|---|---|---|---|
| **key name** | `name`(入口配置時) | 結果オブジェクトのキー。スコープを作る | する |
| **def name** | `definitions` のキー | 参照・テンプレ名 (ref/link 対象) | しない |
| **value_name** | `value_name` | help/usage の値プレースホルダ表示 | しない (表示のみ) |

3つは独立に決まりうる。例: `--fg`(key=fg)が `color` 型(def=color)を ref し、help に `<FG_COLOR>`(value_name)と出す——全部別文字列。

### name フィールドは1つ、役割は配置で決まる

`name` フィールドは1つのまま。definitions に置けば def name (参照名)、入口配列 (options/positionals/commands) に置けば key name (結果キー)。DR-018 の配置区別と一貫。

### value_name のデフォルトと上書き

- 指定なし → uppercase で導出 (key name / type 名 / def name を大文字化)
- 明示 → そちらを採用
- ref 継承 + 上書き: definitions 側で `value_name: "COLOR"` を持つ型を、入口側で `value_name: "FG_COLOR"` と上書きできる (ref が表示メタも継承するため、特別扱い不要)

## 経緯

`--color` 検討中、kawaz から2つの追加要求:

> 構造上名前をつけたいけどキーにしたくないというパターンがある。他オプションからの参照に使ったりテンプレに使ったり。--fg color --bg color みたいに使いたい。

→ これは def name。DR-007 の definitions + ref で既に解決済みだった。`{ref:"color", name:"fg"}` で color テンプレを fg/bg が再利用。color はキーにならない。

> help の rm <FILE> みたいにシンボル的に表示するもの。fg/bg で引数に <COLOR> みたいに表示したくなる。

→ これは value_name (表示シンボル)。key name とも def name とも独立。

kawaz の最終整理:

> デフォルトは uppercase で埋めるで良いし指定したらそちらが採用される。definition で COLOR と指定したのを fg 側で value_name:FG_COLOR と上書きしても良いし自然。

## node フィールドの2層整理

名前分離に伴い、node フィールドを「パース意味論」と「表示メタ」に層分け:

```
── パース意味論 (結果を左右する) ──
name? type? value? children? multiple? or? seq? ref? link? export? ...制約 ...filter

── 表示メタ (help のみ、パース無影響、AtomicAST 不要) ──
value_name? help? hidden?
```

表示メタは丸ごと無視してもパーサは動く (DR-001 で UsefulAST にのみあり AtomicAST には不要、と切れる)。

## 関連

- DR-003 (name 3軸) — 本 DR で key/def/value_name に再整理
- DR-007 (definitions, ref/link) — def name の土台
- DR-018 (配置区別) — name の役割が配置で決まる
- DR-025 (name = 結果スコープ)
