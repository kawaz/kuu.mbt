# DR-053: プリミティブ分解 — name/exact/serial/or によるオプション構造の一般化

## 背景

現在の kuu のコンビネータ（string, int 等）は「名前マッチ + 値消費」を一体で管理している。例えば `string(name="port", value_name="PORT")` は `--port <PORT>` を生成するが、これは本質的に2つのプリミティブの合成:

```
serial(exact("--port"), string("PORT"))
```

value_name は「1引数のシュガー」にすぎない。この分解を進めれば、現在表現できない複合値パターンが自然に表現できる。

## 動機: 複合値パターン

```
--color <NAME> | <R> <G> <B>
```

現在の kuu ではこのパターンを1つのオプションとして定義できない。分解すれば:

```
serial(
  exact("--color", name("color")),
  or(
    name="COLOR",
    [
      str("NAME"),
      serial(
        int(name="R"),
        int(name="G"),
        int(name="B"),
      )
    ]
  )
)
```

## プリミティブの整理

### exact(pattern)
- 引数文字列と完全一致するトークンを1つ消費
- 現在の ExactNode の名前マッチ部分に相当

### name(name)
- 単独では何にもマッチしない（consumed=0）
- メタ情報（名前）を付与するだけの存在
- exact と link されると「名前付きオプショングループ」を形成
- 複数の exact を1つの name にリンクすることで、複数ロングオプション名の共有が可能

### serial(...)
- 子プリミティブを順に消費
- 現在の「名前 + 値」の暗黙的 serial を明示化

### or(...)
- 子パターンのいずれかにマッチ（最長一致）
- 現在の make_or_node に相当
- name を付けられる（ヘルプ表示で段を分ける等に活用）

### 値プリミティブ
- FilterChain ベースの値消費。位置引数と同じ仕組み
- 全て `custom(pre=Filter::parse_xxx())` のシュガーとして実装可能

#### 基本型

| プリミティブ | 型 | 備考 |
|---|---|---|
| `string` | `String` | identity filter（値をそのまま） |
| `int` | `Int` | `Filter::parse_int` |
| `float` | `Double` | `Filter::parse_float` |
| `boolean` | `Bool` | `Filter::parse_bool`。true/t/on/1, false/f/off/0（case-insensitive）。flag と違い値を取る |

#### ドメイン型（将来候補）

| プリミティブ | 型 | 依存 | 備考 |
|---|---|---|---|
| `path` / `file` | `String` | — | ファイルパス。補完ヒント用に string と区別 |
| `datetime` | `TimeSpec` | `kawaz/timespec` | 日時指定: `2026-03-18T09:00` |
| `duration` | `Duration` | `kawaz/timespec` | 時間幅: `30s`, `5m`, `1h30m` |
| `timerange` | `TimeRange` | `kawaz/timespec` | 期間: `2026-03-01..2026-03-18` |

ドメイン型は core には含めず、別パッケージ（`kuu-timespec` 等）として提供する想定。core は `custom` で任意の型を扱えるため、ドメイン型は pre フィルタを提供するだけで良い。

## option コンビネータの分解ツリー

現在の Sugar 層コンビネータ（`string(name="host", shorts="hH", variation_unset="no")`）は、内部的に `register_option` が long/short/variation の全展開を一体で行っている。プリミティブ分解では、これが以下のツリーに分解される:

```
option(name="host", shorts="hH", variation_unset="no")
= or([
    long(name="host", variation_unset="no")
    = or([
        serial(exact("--host"), string()),
        exact("--no-host", unset_handler),
      ]),
    short("hH")
    = or([
        serial(exact("-h"), string()),
        serial(exact("-H"), string()),
      ]),
  ])
```

### 各レイヤーの責務

| コンビネータ | 責務 |
|---|---|
| `option` | long/short をグループ化するコンテナ。ヘルプ・OptMeta を共有。name/shorts/variations 等のシュガーパラメータを持ち、子の long/short に分配する |
| `long` | `--{name}` プレフィックスの ExactNode 生成 + variations（`--no-{name}` 等）の展開 |
| `short` | shorts 文字列の各文字を `-{c}` の ExactNode に展開 |
| `serial` | 子プリミティブを順に消費（`exact + value` の順序合成） |
| `exact` | トークン完全一致（1引数消費） |
| `or` | 子パターンのいずれかにマッチ（最長一致） |
| `string`/`int`/`float` | 値を1つ消費するだけの値プリミティブ |

### 現在の register_option との対応

現在の `register_option` が行っている処理がこのツリー構造そのもの:

1. `"--" + name` の ExactNode 生成 → `long` 内の `serial(exact("--host"), ...)` に対応
2. shorts の各文字を ExactNode に展開 → `short` に対応
3. variations の展開（`--no-{name}` 等） → `long` 内の `exact("--no-host", ...)` に対応
4. `make_or_node` で全ノードを統合 → 最外の `or` に対応
5. OptMeta 登録 → `option` の責務

### この分解の利点

- **独立した組み合わせ**: `long` だけ・`short` だけ・`exact` だけの利用が自然にできる
- **複合値パターン**: `serial(exact("--color"), or([str("NAME"), serial(int("R"), int("G"), int("B"))]))` のような表現が可能
- **eq_split**: `serial(exact("--host"), string())` の `serial` が `--host=value` の `=` 分割も内包できる
- **将来の拡張**: 新しいプレフィックスパターン（`+flag`、`/flag` 等）も `exact` の組み合わせで表現可能

## Sugar 層との関係

Sugar 層のシンプルなコンビネータは、上記ツリーの省略形:

| Sugar | 分解 |
|---|---|
| `flag(name="verbose")` | `option("verbose") { exact("--verbose") }` |
| `string(name="host", shorts="h")` | `option("host", shorts="h") { string() }` |
| `int(name="port")` | `option("port") { int() }` |
| `count(name="verbose")` | `option("verbose") { count_handler }` |
| `positional(name="FILE")` | `string()` （option でラップしない、名前はヘルプ用のみ） |

## コンテナへの名前付与

serial, or 等のコンテナにも名前を付けられる:

```
or(
  name="COLOR",     // このグループ全体の名前
  [str("NAME"), serial(int("R"), int("G"), int("B"))]
)
```

名前は任意（付けなくてもよい）。付けた場合:
- ヘルプ表示で `--color COLOR` + `COLOR: NAME | R G B` のように段を分けて表示可能
- エラーメッセージで `"invalid value for COLOR"` のようにグループ名を参照可能

## 命名改善の方向性

現在の `string`, `int` という命名は「opt（オプション）」と「value（値）」を混同している。

- `string` は「文字列値を取るオプション」の意だが、プリミティブとしての本質は「文字列値を1つ消費する」こと
- `positional(name="FILE")` が `str("FILE")` に分解されることからも明らか — 値プリミティブとオプション（名前マッチ）は独立した概念

### 命名の対応表

| 現在 | プリミティブ | 備考 |
|---|---|---|
| `string` | `string` / `str` | 値消費プリミティブ |
| `int` | `int` | 値消費プリミティブ |
| `float` | `float` | 値消費プリミティブ |
| `append_string` | `append[String]` 相当 | 配列蓄積 |
| `flag` | そのまま | 値なし。exact の特殊形 |
| `count` | そのまま | 出現回数。exact の特殊形 |

**Sugar 層は現在の命名を維持してよい**（後方互換 + 使いやすさ）。プリミティブ層で `string`, `int`, `float` というシンプルな名前を使い、Sugar 層がそれをラップする構造。

## 既存実装との整合性

kuu の「投機実行 + 最長一致」モデルはこの分解と自然に整合する:

- `make_or_node` が既に or の最長一致を実装
- `serial` は consumed の合計で表現可能（現在の「名前ノード + 値ノード」が暗黙的に serial）
- ExactNode の try_reduce は `(args, cursor) -> TryResult` で、serial/or はこの上に構築可能

## 現時点の位置づけ

この分解は kuu の設計の根幹に関わる。現在の ExactNode + 投機実行モデルとの整合性を慎重に検討する必要がある。

**即座に実装する必要はない。** 現在の Sugar 層コンビネータは引き続き有用であり、このプリミティブ分解は「内部実装の一般化」として段階的に進められる。

## name パラメータの必須性

### 現行 Sugar 層: name は必須（正しい）

| コンビネータ | name の用途 | 必須? |
|---|---|---|
| flag/string/int/float/count/append_* | `--name` 生成 | 必須 |
| cmd/sub | サブコマンド名 | 必須 |
| positional/rest | ヘルプ表示 `<NAME>` + OptMeta | 必須 |
| serial/never | — | パラメータなし |
| dashdash | separator（デフォルト `"--"`） | 任意 |

Sugar 層では name が `--name` や `<NAME>` の生成に直結するため、デフォルト値なしの必須パラメータが正しい。

### 将来のプリミティブ層: name は任意

DR-053 のプリミティブ分解では `or(...)` や `serial(...)` のようなコンテナに name は不要。`name` コンビネータが独立しているため、名前付与は明示的に行う。Sugar 層は引き続き name 必須でよい。

## 共通パラメータの struct 化（断念）

現在の各コンビネータは name, description, global, shorts, aliases, env, hidden, value_name の8パラメータを個別に受け取っている。struct にまとめればシグネチャが簡潔になるが、**MoonBit は struct フィールドのデフォルト値を未サポート**（2026-03 時点）。`{}` は `Map` リテラルと解釈される。`derive(Default)` + record update `{ ..Foo::default(), name: "x" }` は動作するが冗長。

ユーザー API の簡潔さが最優先であり、内部コードの泥臭さ（パラメータの繰り返し）は MoonBit の言語制約として許容する。言語側で struct フィールドデフォルトがサポートされれば再検討。

## 検討事項

- ExactNode の try_reduce シグネチャとの整合性
- serial/or の入れ子が投機実行モデルに自然に載るか
- name コンビネータの consumed=0 が OC/P フェーズで問題にならないか
- ヘルプ生成への影響（現在の OptMeta ベースの生成との互換性）
- 命名リネームのタイミング — Sugar 層は互換維持、プリミティブ層で新命名を導入
