# kuu 引数定義 AST 仕様

> 状態: トップダウン再設計後の整理 (2026-06)。未確定事項は `docs/journal/2026-06-25-session1-context.md` および各 DR 参照。
> 対象: 言語非依存な引数定義のための AST。

## 0. 全体像

### 0.1 設計原則

- **言語非依存**: JSON でシリアライズ可能。各言語 DX がこの AST を生成/消費する。
- **2層 AST**:
  - **UsefulAST**: 人間が書く層、各言語 DX コードが本体、JSON は交換フォーマット
  - **AtomicAST**: パーサが直接走る正規形、シリアライズ可能なもののみ
- **キー名は snake_case 正規形** (DR-022)、case 変換は pluggable。
- **暗黙ルールを最小化**: 明示性重視、利用者の知識を信頼。

### 0.2 4層アーキテクチャ

```
人間 → UsefulAST (各言語 DX、クロージャあり)
            ↕ export/import
       UsefulAST JSON (クロージャ部分は $required)
            ↓ parseDefinition()
       AtomicAST (シリアライズ可能な正規形)
            ↓ 最長一致パース
       パース結果 (ParserContext と 結果オブジェクト)
```

### 0.3 結果の2層取り出し

```
パース → ParserContext (詳細状態: value, committed, selected, source, ...)
           ↓ convert
         結果オブジェクト (シンプルなビュー)
```

通常は結果オブジェクトで値だけ取る。`committed` / `selected` / `source` 等のメタ情報は ParserContext のみ。

---

## 1. 基本構造

### 1.1 ノードは葉か枝か

ノードには2系統:

- **葉ノード** (プリミティブ、children なし): 自分でトークンを消費する
  - 値プリミティブ: `string` / `number` / `int` / `float` / `bool` / `path` / `file` / `dir` / `datetime` / カスタム
  - `exact`: トークンを照合消費するプリミティブ。値は持っても持たなくてもよい (照合専用 or literal 値発生)
- **枝ノード** (構造、children 必須): 子に消費を委ね、結果を畳む
  - `or`: 子から1つ選ぶ (排他)
  - `seq`: 子を順に消費

葉と枝はノードのフィールド構成で区別される (葉は children を持たず type を持つ、枝は逆)。

### 1.2 構造記法 (糖衣)

裸の JSON 値は対応する node 形への糖衣として展開される (DR-026):

```
"x"          → {exact: "x"}      裸文字列 = exact 糖衣
[...]         → {seq: [...]}      裸配列 = seq 糖衣
{or: [...]}    → 選択 (or のキー形)
{seq: [...]}   → 順次 (name 等を付けたい時の明示形)
{type: ...}    → 値プリミティブ (葉)
```

`or` / `seq` キーは name / multiple / value_name 等の通常フィールドと同居可能:

```json
{"name": "color", "or": [
  [{"type":"number","name":"r"},{"type":"number","name":"g"},{"type":"number","name":"b"}],
  {"type":"string"}
]}
```

### 1.3 配置で役割が決まる (DR-018)

要素の役割は所属する配列で決まる:

- **options[]**: ハイフン起動 (`--`/`-`)、順不同
- **positionals[]**: 位置消費される要素群
- **commands[]**: サブコマンド糖衣 (詳細は §4)

option/positional は所属配列で役割が定まるので type フィールドは省略可。command 等の構造的に特別な要素のみ type 必須。

### 1.4 ノードの基本形

```json
{
  "name": "<key name>",
  "type": "<type 参照>",
  
  "long": [...],
  "short": "<chars>",
  
  "value": ...,
  "default": ...,
  "values": [...],
  "multiple": ...,
  
  "filters": [...],
  "pre_filters": [...],
  "post_filters": [...],
  
  "options": [...],
  "positionals": [...],
  "commands": [...],
  
  "export": false,
  "export_key": "<別名>",
  
  "required": true,
  "exclusive_group": ["<group>"],
  "requires": ["<other-name>"],
  
  "ref": "<name>",
  "link": "<name>",
  "inherit": true,
  "inheritable": true,
  
  "value_name": "<help 表示>",
  "help": "<説明>",
  "hidden": false,
  
  "config": {...}
}
```

---

## 2. 名前とスコープ

### 2.1 3つの名前 (DR-024)

ノードに関わる名前は3層に分離:

| 名前 | 場所 | 役割 | 結果露出 |
|---|---|---|---|
| **key name** | `name` (入口配置時) | 結果オブジェクトのキー、スコープを作る | する |
| **def name** | `definitions` のキー | 参照・テンプレ名 (ref/link 対象) | しない |
| **value_name** | `value_name` | help/usage の値プレースホルダ表示 | しない (表示のみ) |

`name` フィールドは1つ。役割は配置で決まる:
- definitions 配下に置けば def name
- options/positionals/commands に置けば key name

### 2.2 value_name のデフォルトと上書き

- 指定なし → uppercase で導出 (key name / type 名 / def name を大文字化)
- 明示 → そちらを採用
- ref 継承 + 上書き可: definitions 側の `value_name: "COLOR"` を入口側で `value_name: "FG_COLOR"` で上書きできる

### 2.3 name が結果スコープを作る (DR-025)

- **name を持つノード** = 結果スコープ (結果オブジェクトのキー) を作る
- **name 無しノード** = 透過 (値の畳み方だけ効かせて値を親に流す)

children の有無ではなく **name の有無**で結果スコープが決まる。

### 2.4 露出規則: 最も浅い name 層

結果への露出は以下の規則で決まる:

1. 根から降りていって、最も浅い (祖先側の) name 層で止める
2. その層にある name 持ちノードを**全て**結果キーにする (同じ層の name 兄弟は全部拾う)
3. それより深い name は、止めた層のノードが作る子スコープに属する (再帰)

`name` 無しノードは結果に痕跡を残さず、値の畳み方 (配列 or kv) だけ効かせる。

### 2.5 object は独立構造でなく露出の帰結

kv (object 的な結果) は専用構造を持たない。**name を持つ子が並べば結果が自然に kv になる**:

```
[{name:"r",type:"number"},{name:"g",type:"number"},{name:"b",type:"number"}]
→ 結果は {r:..., g:..., b:...}
```

混在 (name 持ちと name 無し) も問題ない: name 無しは消えるだけ、kv には name 持ちだけ現れる。

### 2.6 lexical スコープ = name が作るスコープ (DR-033)

ref/link の解決スコープは command に限らない。**name を持つ任意のノードがスコープ単位**になる:

```
rgb の中で r/g/b を DRY に定義:
rgb: [
  {name:"r", type:"number"},
  {ref:"r", name:"g"},  // 同じスコープ内の r を参照
  {ref:"r", name:"b"}
]
```

解決順: 現在スコープ → 外側のスコープへ順に → 見つからなければ definitions (DR-032)。

---

## 3. type と参照糖衣

### 3.1 type は definitions/registry への参照糖衣 (DR-028)

`type: X` は「定義済みの型 X を参照する糖衣」。組み込み型もユーザ定義型も同じ `type:` で指定:

```
type: "number"   → 組み込み (registry の value_parser)
type: "color"    → ユーザ定義 (definitions の構造テンプレ)
type: "cssColor" → ユーザ定義型 + value_parser (両方持ちうる)
```

### 3.2 解決順 (前方互換)

```
definitions.types.X → registry.types.X → warn+string フォールバック
```

ユーザのローカル定義が組み込みを shadow する。組み込み型の追加がユーザ定義を壊さない (前方互換)。未登録の場合は warn を出して string にフォールバック (DR-021 の「warn はする、reject はしない」と整合)。

### 3.3 type の語彙

**値プリミティブ (葉)**: `string` / `number` / `int` / `float` / `bool` / `path` / `file` / `dir` / `datetime` / `exact` / カスタム

**糖衣プリセット**: `flag` / `count` / `command` / `help` 等
- `flag` = bool + default:false + 起動で true
- `count` = number + default:0 + increment mapper
- `command` = name トリガ + children でスコープ
- `help` = 起動時アクション

これらは独立の type ではなく、属性プリセットへの名前。version は専用 type ではなく単なる flag。

### 3.4 type と multiple は同じ属性平面への参照 (DR-034)

`type` と `multiple` は包含関係でなく、同じ属性平面の異なる断面への参照。両方書けば合成順:

```
1. プリセットなしの初期値
2. type プリセットで上書き
3. multiple プリセットで上書き
4. ユーザの直接書き (最優先)
```

後ろほど優先。DR-007 の ref 継承+差分上書きと同じ流儀。

---

## 4. options / positionals / commands

### 4.1 配置で役割分け (DR-018)

- **options**: ハイフン起動、順不同
- **positionals**: 順序で消費
- **commands**: サブコマンド糖衣 (下記)

### 4.2 commands は positionals 内 or への糖衣

```json
"commands": [
  {"type": "command", "name": "commit", ...},
  {"type": "command", "name": "clone", ...}
]
```

展開 (内部正規形):

```json
"positionals": [
  {"or": [
    {"type": "command", "name": "commit", ...},
    {"type": "command", "name": "clone", ...},
    ...original_positionals
  ]}
]
```

- commands と original_positionals が or で排他
- commands が先、original_positionals が後 (最長一致で command 名にマッチすればそちら)
- commands 不在時は or で包まない

### 4.3 command 一級扱い、内部正規形は同型 (DR-017)

定義時は command を1級として扱う (commands[]、`type: "command"`)。パース時 (AtomicAST) は同型要素 (exact + or/seq) に展開され、パースループは「name でトリガしうる要素」という同型表現で動く。

### 4.4 復帰・途中分岐は構造プリミティブで組む (DR-020)

「サブコマンド消費後に親へ復帰」「途中分岐」「再帰」などの専用概念は持たない。これらは構造プリミティブ (or/seq/exact/multiple) の組み合わせでユーザが組む:

```
type: multiple, children: [
  {exact: "--command"},
  {or: [...サブコマンド群]}
]
```

曖昧さなく最長一致で解ければ許す、はユーザの責務。

### 4.5 「実体だけノード」 (DR-030)

入口属性 (long/short/positional 位置) を持たないノードは、CLI 引数では起動されないが結果に出る「実体だけ」のノード。

```json
{"name": "timeout", "type": "number", "value": 30}
{"name": "apiKey", "type": "string", "env": "API_KEY"}
```

用途:
- link のプレースホルダ実体
- 環境変数専用
- ハードコード設定/マジックナンバー
- 結果オブジェクトを appconfig 統合ストアとして使う

---

## 5. 構造記法と値

### 5.1 構造プリミティブ

| プリミティブ | 役割 | 値の伝搬 |
|---|---|---|
| `exact` | name の完全一致でトリガ | value あれば literal、なければ値なし |
| `or` | 子から1つ選択 (排他) | 選ばれた子の値 |
| `seq` | 子を順に消費 | 子の値の配列 (単独要素なら単独) |
| primitive (`string`/`number`/...) | 引数1個消費 or value literal | 自身の値 |

### 5.2 リテラルは primitive + value の糖衣 (DR-015)

```
"red"   → {"type": "string", "value": "red"}
255     → {"type": "number", "value": 255}
true    → {"type": "bool", "value": true}
```

### 5.3 values は or のショートハンド

```json
{"name": "color", "values": ["red", "green", "blue"]}
```

正規形:

```json
{"name": "color", "or": [
  {"type": "string", "value": "red"},
  {"type": "string", "value": "green"},
  {"type": "string", "value": "blue"}
]}
```

values の中に配列があれば seq ブランチ:

```json
"values": [
  "red", "green", "blue",
  [{"name":"r","type":"number"},{"name":"g","type":"number"},{"name":"b","type":"number"}]
]
```

(values 展開の細則は CONTEXT 論点 B、混在ケースの正式仕様は未確定)

### 5.4 「あと勝ち」mutation (DR-015)

値プレースホルダは型のゼロ値/null で初期化、CLI 入力順に mutation:

```
--since A --timerange 'X..Y' --since B
1. since_value = A
2. timerange セット → since_value=X, until_value=Y
3. since_value = B (最後勝ち)
最終: since=B, until=Y, timerange=[B,Y]
```

複雑な競合解決ルール不要、入力順がそのまま勝者。

---

## 6. multiple とその構造

### 6.1 multiple は複数値経路のスイッチ (DR-034)

multiple フィールドの値が「複数値経路を起動するか、起動するならどう積むか」を決める。

```
multiple: "append"
multiple: "merge"
multiple: {mapper: "append", collector: "to_set"}
```

multiple registry (DR-036) からプリセットを引く。

### 6.2 multiple 経路の構造 (DR-034)

```
入力: raw_string
  ↓ separator (任意、String → String[])
[piece1, piece2, ...]
各 piece に対して peaceProcessor:
  piece (String)
    ↓ pre_filters (FilterChain[String, String])
    ↓ parse (types registry の value_parser、String → T)
    ↓ post_filters (FilterChain[T, T]、各 piece 検証)
  T
mapper で累積:
  (piece, processor, prevs: T[]) → T[]
collector で最終形へ:
  T[] → U
```

- **separator**: 1引数を分割 (例: `","`)、指定なければ分割しない
- **mapper**: piece の累積関数。`+/-/...` 等の修飾子はここで剥がして合成 (mergeable など)
- **collector**: T[] → U の最終変換 (filters registry から引く、例: `to_set`、`to_map`)

### 6.3 multiple 無しは縮退ケース

multiple を書かないノードは内部的に上記モデルの特殊ケース:

- separator: なし (常に長さ1の `[piece]`)
- mapper: override (prevs 無視、`[processor(piece)]`)
- collector: unwrap_single (`[t] → t`)

結果として peaceProcessor 一本で終わる。仕様の説明・実装が1本で済む (最適化として fast path は可)。

### 6.4 multiple registry の組み込みプリセット (DR-036)

| 名前 | mapper | collector | separator | 用途 |
|---|---|---|---|---|
| `append` | append | identity | なし | リスト累積 |
| `merge` | merge (+/-/...) | identity | "," | DR-023 マージリスト |
| `set` | append | to_set | なし | 重複排除 |
| `map` | append (要素は {k,v}) | to_map | なし | kv 累積 |

ユーザが独自プリセットを作るなら definitions.multiple に登録。

---

## 7. CLI 起動 (long / short / variant)

### 7.1 long / short

```json
{
  "name": "verbose",
  "long": [],         // → --verbose
  "short": "v"        // → -v
}
```

- `long` 配列が書かれていれば `--<name>` 生成
- `long` 未指定なら `--name` 生成しない
- `short` 文字列の各文字が個別ショートオプション

### 7.2 longPrefix / shortPrefix (config)

階層継承可能な設定として `config` フィールドに:

```json
{
  "name": "mycli",
  "config": {
    "long_prefix": "--",
    "short_prefix": "-",
    "env_prefix": "MYAPP",
    "auto_env": false,
    "allow_equal_separator": true,
    "short_combine": true
  }
}
```

子要素は親の config を継承、上書き可能。

### 7.3 variant DSL (DR-011)

`long` の variant (`--no-X` のような同 opt の別入口):

**文字列 DSL**:
```
"<prefix>:<effect>[:<arg1>...]"
```

例:
- `"no:set:false"` — `--no-<name>` で false セット
- `"no:set:none"` — `--no-<name>` で "none" セット
- `"no:default"` — default に戻す (committed=true)
- `"no:unset"` — default に戻す (committed=false)
- `"reset:empty"` — 配列/Map を空に
- `"red:set:rgb:255:0:0"` — 複合値

**オブジェクト形式**:
```json
{"prefix": "red", "effect": "set", "args": ["rgb", "255", "0", "0"]}
```

args は全て string (CLI 引数パースと同じ手順を通る)。

### 7.4 effect 語彙 (4種)

| effect | args | 意味 |
|---|---|---|
| `set` | 1個以上 | 固定値セット |
| `default` | なし | default に戻す (committed=true) |
| `unset` | なし | default に戻す (committed=false) |
| `empty` | なし | 配列/Map を空に |

toggle / not は採用しない (CLI 慣習として薄い)。`"no"` 単独のようなショートハンドも入れない (アプリごとに意味が違う)。

### 7.5 variant は AtomicAST で消える

variant 構造は parseDefinition() の時点で `or + exact + literal value` に展開され、AtomicAST には残らない。

---

## 8. filter chain

### 8.1 filter の役割

filter は値の変換と検証を担う純粋関数:

```
FilterChain[A, B] = A → B raise ParseError | raise ParseReject
```

- 入力: 値 (string or T)
- 出力: 値 (string or T)
- レスポンス: 成功 / Reject (他枝を試して) / Error (この枝のつもりだが不正)

### 8.2 Reject と Error の区別 (DR-037)

- **Reject**: 「この枝ではない、他枝を試して」→ エラー保持せず脱落
- **Error**: 「この枝のつもりだが値が不正」→ エラーを保持

or の枝選択時、filter Reject は静かに脱落、Error は全体失敗時の表示候補に。

### 8.3 filter の位置 (DR-034 のパイプライン参照)

filter は2箇所に乗る:

- **peaceProcessor 内**: 各 piece に対する変換・検証
  - pre_filters: `FilterChain[String, String]` (trim 等)
  - parse: `String → T` (types registry の value_parser、暗黙)
  - post_filters: `FilterChain[T, T]` (in_range 等、各 piece に効く)
- **multiple 経路の後**: 累積結果に対する最終変換
  - collector / post_filters: `T[] → U` (to_set、to_map 等、累積後に効く)

両者は位置が違うので自然な順序で合成 (type post → 各 piece、multiple post → 累積後)。

### 8.4 DSL 文法

variant と同じ `<name>:<arg>:...` 形式:

```
"trim"                   引数なし
"in_range:1:65535"
"regex_match:^[a-z]+$"
```

args は全て string、filter registry 側でキャスト。複雑な引数はオブジェクト形式:

```json
[{"name": "complex_validator", "args": ["abc", "with:colon"]}]
```

### 8.5 `@base` sentinel

type/ref 元のデフォルト filter chain を継承する sentinel:

```json
"filters": ["@base", "non_empty"]
```

解決順:
1. ref が指定されていれば → ref 元のそのフィールド
2. なければ → type registry のデフォルト
3. どちらもなければ → 空配列

---

## 9. 制約

### 9.1 required

```json
{"name": "filename", "required": true}
```

boolean のみ。グループ的必須は or + required:

```json
{"or": [...], "required": true}
```

### 9.2 exclusive_group

```json
{"name": "json", "exclusive_group": ["format"]}
{"name": "yaml", "exclusive_group": ["format"]}
```

同じグループ名の要素群が排他 (最大1つ起動)。string[] で複数グループ所属可。

### 9.3 requires

```json
{"name": "decrypt", "requires": ["key-file"]}
```

自分が起動された時、列挙された name の要素群も起動されている必要がある。

### 9.4 groupRules は作らない (DR-012)

「グループ全体に対するルール」を別場所 (`groupRules` 等) に書く設計はしない。各要素属性で表現できる範囲に限定。

---

## 10. 参照 (ref / link)

### 10.1 ref は name 参照 (構造継承)

```json
{
  "ref": "color_template",
  "name": "fg"
}
```

- ref 元の構造を全継承
- 差分フィールドだけ書く

### 10.2 link は値同期 (DR-029)

```json
{"name": "log-level", "type": "number"}        // 実体
{"short": "v", "type": "count", "link": "log-level"}  // 参照
```

`-vvv --log-level 5 -v` → log-level セルに 0→3→5→6 と順次適用。1実体: N参照。

link 先は固定パス DSL: `.name` と `[int]` (負インデックス含む):
```
link: "logLevel"
link: "timerange.since"
link: "color.rgb[0]"
link: "color.rgb[-1]"
```

解決は遅延 (実行時)。datetime のように内部構造を AST が知らないケースがあるため。解決失敗 = その経路のパース失敗 (DR-021)。

### 10.3 ref/link は name 参照、type は型参照 (DR-032)

| 参照 | 指すもの | 解決順 |
|---|---|---|
| `type: X` | 型 | definitions.types.X → registry.types.X → warn+string |
| `ref: Y` | name (ノード) | スコープ内 → definitions |
| `link: Z` | name (値セル) | スコープ内 → definitions |

ref/link と type は指す対象が違うため統合不能。

### 10.4 definitions 領域

トップレベル/各 scope に `definitions` フィールド。registry と同じ区分の名前空間 (DR-035):

```json
{
  "definitions": {
    "types": {
      "color": {"type": "string", "values": ["red", "green", "blue"]}
    },
    "accumulators": {
      "my_merge": {...}
    }
  },
  "options": [
    {"type": "color", "name": "fg"}
  ]
}
```

- definitions 内の要素は CLI 上で直接消費されない
- デフォルトで結果オブジェクトに出ない
- 区分は必須 (糖衣で省略しない)

---

## 11. スコープと継承

### 11.1 スコープは name で自動 (DR-025, DR-033)

name を持つノードが結果スコープ = lexical スコープを作る。children の有無は無関係。

### 11.2 inherit (default の取得先)

```json
{"name": "ttl", "type": "number", "inherit": true}
```

自身に値がなければ祖先 scope chain で同 name を探す。default と排他 (inherit を書いたら default は祖先で持つ)。

### 11.3 inheritable (祖先スコープからも書ける)

```json
{"name": "ttl", "type": "number", "inheritable": true, "default": 60}
```

- 自スコープでは `--ttl`
- 祖先スコープでは `--<ancestor>-ttl` (prefix 自動付与で衝突回避)
- 各 scope で書かれた値が、その scope 配下のインスタンスのデフォルトに

prefix 生成ルール (案A 直近のみ / 案A+B' 衝突時長いパス) は未確定。

### 11.4 値源の優先順位 (DR-031)

```
1. CLI 明示 / link    (パース時操作、最優先)
2. 環境変数
3. config ファイル
4. inherit (祖先 scope)
5. default / value    (最終フォールバック)
```

順序は固定 (設定可能にしない、暗黙の罠を避ける)。

---

## 12. 環境変数

```json
{"name": "port", "env": "PORT"}
```

- envPrefix が設定されていれば自動連結 (`MYAPP_PORT`)
- 値の優先度: §11.4 を参照
- envProvider は実装側で注入

---

## 13. 外部レジストリ

### 13.1 レジストリ区分 (8区分、DR-010 + DR-036)

| レジストリ | 役割 | 引かれるフィールド |
|---|---|---|
| `types` | 値型のプリセット (peaceProcessor 中心) | `type` |
| `filters` | 純粋 FilterChain (collector も含む) | `filters`, `pre_filters`, `post_filters` |
| `accumulators` | mapper の属性セット | `multiple` のサブフィールド |
| `multiple` | mapper+collector+separator の糖衣プリセット | `multiple` (文字列指定時) |
| `handlers` | command の実行フック | (TBD) |
| `envProvider` | 環境変数解決 | `env` |
| `completers` | 動的補完生成 | (TBD) |
| `defaultFns` | デフォルト値の動的生成 | (TBD) |

### 13.2 フィールド名で registry が暗黙決定

```json
{
  "type": "int",                   → types["int"]
  "filters": ["trim"],              → filters["trim"]
  "multiple": "append",            → multiple["append"]
  "env": "PORT"                    → envProvider
}
```

### 13.3 解決順 (全区分一様、DR-028 + DR-035)

```
definitions.X.name → registry.X.name → warn+フォールバック
```

ユーザのローカル定義が組み込みを shadow (前方互換)。

### 13.4 階層化された組み込み

- **コア**: 言語実装に絶対必要な最小セット (常に同梱)
- **標準**: よく使う機能 (デフォルト同梱、opt-out 可)
- **拡張**: 特定ユースケース (デフォルト未登録、明示 import が必要)

例: `mergeable` accumulator は拡張、明示 import で登録。

### 13.5 未登録の挙動

未登録の参照に対して:
- types: warn + string フォールバック (DR-021 と整合)
- 他: ランタイムエラーで「次の手」を明示

```
RuntimeError: Type "my-uuid" not registered.
Hint: Register: kuu(ast, { types: { "my-uuid": { parse: (s) => ... } } });
```

### 13.6 diagnose モード

`kuu.diagnose(ast)` で AST 走査時に未実装を全列挙する仕組み。

### 13.7 case 変換 (pluggable、DR-022)

wire format は snake_case 固定。各言語バインディングへの case 変換は pluggable:

- Python / Rust: snake のまま (ネイティブ)
- TS / MoonBit: camelCase 変換可 (差し替え可能)

「言語ごとに変換を固定」は新たな暗黙ルールになるため避ける。デフォルト変換器を置くが固定はしない。

---

## 14. ヘルプと特殊 type

### 14.1 help

```json
{"name": "help", "type": "help", "long": [], "short": "h", "global": true}
```

- type が `help` の要素は組み込み実装
- 起動時に ParserContext の help フラグを立てる
- パーサが完了時に help フラグを見て出力切替

### 14.2 version

```json
{"name": "version", "type": "flag", "long": [], "global": true}
```

- ただのフラグ
- 結果オブジェクトの `result.version` を見てアプリがバージョン出力
- AST にバージョン文字列を持たせない

### 14.3 visibility / deprecated (未確定)

ヘルプ/補完での表示制御。詳細は未確定:

```json
"hidden": true
"deprecated": true
```

---

## 15. パース挙動

### 15.1 成功条件 (DR-021)

> 曖昧さなく最長一致で全引数を解決できたら成功。

途中で曖昧さが発生したら ambiguous エラー。

### 15.2 解けた枝の数による結末 (DR-037)

or のような選択構造での結末:

| 解けた枝の数 | 結末 |
|---|---|
| 0個 | 全体失敗 (保持された Error を表示) |
| 1個 | その枝で確定 (他枝の Reject/Error は捨てる) |
| 2個以上 | ambiguous エラー |

「解けた」= filter Error 含めて全段が通った枝。filter Reject は静かに脱落 (エラー保持しない)、filter Error は失敗時の表示候補に保持。

### 15.3 最長一致の射程

最長一致は**枝内の消費長競合**にのみ効く (例: `--color R G B` (3引数) と `--color R G` (2引数))。option と positional の境界をまたぐ全体経路が同じ長さなら最長一致は機能せず、ambiguous:

```
入力: --color 255 0 0 ("0" が実在ファイル)
枝A: --color R G B (option 3消費) + positional 0個 → 成功
枝B: --color <name> (option 1消費) + positional 2個 → 成功
両方とも全引数消費 → ambiguous
```

### 15.4 露出キーの一意性検査は実行時

定義時に潰さず、最長一致で解決できる限り許す。実際に同一入力で両方が露出して衝突した時のみ ambiguous エラー。

露出キーの型不一致は union (嫌うなら export_key で分離、強制せず指針)。

### 15.5 静的バリデータは warn のみ

潜在的 ambiguous は静的に検出して warn できるべきだが reject はしない:

- 上限なし multiple が positional 列に複数 → warn
- 露出キーが衝突しうる構造 → warn

warn はする、reject はしない、の二段構え (利用者を信頼)。

---

## 16. 用語

| 用語 | 説明 |
|---|---|
| **UsefulAST** | 人間が書く層 (各言語 DX コード) |
| **AtomicAST** | パーサ正規形 (シリアライズ可能) |
| **parseDefinition()** | UsefulAST → AtomicAST 変換 |
| **scope** | name で作られる結果スコープ = lexical スコープ |
| **key name** | 結果オブジェクトのキー (DR-024) |
| **def name** | definitions のキー (参照名) |
| **value_name** | help/usage の値プレースホルダ表示 |
| **committed** | ユーザが明示指定したか (ParserContext のメタ) |
| **selected** | この要素のいずれかの入口がマッチしたか |
| **inheritable** | 祖先 scope からも CLI 上で書ける |
| **`@base`** | フィールドのベース値展開 sentinel |
| **peaceProcessor** | 各 piece を T に変換するチェーン (pre+parse+post) |
| **mapper** | piece の累積関数 ((piece, processor, prevs) → T[]) |
| **collector** | 累積後の最終変換 (T[] → U) |
| **separator** | 1引数を分割する区切り文字 |
| **Reject** | filter/枝が「私のものではない」と返す (脱落、保持なし) |
| **Error** | filter/枝が「私のつもりだが値が不正」と返す (保持、表示候補) |
| **ambiguous** | 2通り以上の経路で全引数を解決できた状態 |
