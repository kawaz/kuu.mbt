# DR-019: Optional Value Option — 値省略可能オプションの設計

## 背景

`--color [always|none]` や `--md [render|source|none]` のように、オプション自体の有無と値の有無が独立して意味を持つパターンがある。現在の kuu は `flag`（値なし）と `string_opt`（値必須）の二択で、この中間を表現できない。

## 動機となるユースケース

### git --color パターン

| 指定 | computed | 由来 |
|------|----------|------|
| なし | auto → tty 判定で always/none | default |
| `--color` | always | implicit_value |
| `--color always` | always | 明示指定 |
| `--color=always` | always | 明示指定（eq_split 経由） |
| `--color none` | none | 明示指定 |

### --md パターン（3層デフォルト）

| 指定 | computed | 由来 |
|------|----------|------|
| なし | none | default（オプション自体のデフォルト） |
| `--md`（tty） | render | implicit_value（Thunk, tty 依存） |
| `--md`（non-tty） | source | implicit_value（Thunk, tty 依存） |
| `--md render` | render | 明示指定 |
| `--md=render` | render | 明示指定（eq_split 経由） |
| `--md source` | source | 明示指定 |
| `--md none` | none | 明示指定 |

2つの独立した初期値が必要:
- **default** — オプション未指定時の値
- **implicit_value** — オプション指定だが値省略時の値

両方が即値 `Val(T)` でも遅延評価 `Thunk(() -> T)` でもあり得る。

## 核心: 既存パーツの組み合わせで解決

optional value option は新しい ExactNode の仕組みを必要としない。kuu の既存パーツ（or, serial, exact, choices）の組み合わせで Convention レイヤーに展開できる。

### 展開パターン

`string_opt(name="color", default="auto", implicit_value="always", choices=["always","none","auto"])` は内部で以下に展開:

```
or([
  serial([exact("--color"), or(["always", "none", "auto"])]),  // 値あり: consumed=2
  exact("--color", set=implicit_value),                         // 値なし: consumed=1
],
default="auto"
)
```

同じ Ref[String] を共有し、どちらが commit しても同じ cell に書き込む。

### parse_raw の最長一致による自然な解決

| 入力 | serial (consumed=2) | exact (consumed=1) | 結果 |
|------|---------------------|---------------------|------|
| `--color always` | Accept(2) | Accept(1) | serial 勝ち → "always" |
| `--color=always` | eq_split 経由 Accept(1) | — | "always" |
| `--color none` | Accept(2) | Accept(1) | serial 勝ち → "none" |
| `--color --verbose` | or Reject → serial Reject | Accept(1) | exact → implicit "always" |
| `--color rander` | or Reject → serial Reject | Accept(1) | exact → implicit "always"、"rander" は次ループへ |
| `--color`（末尾） | 値なし → serial Reject | Accept(1) | exact → implicit "always" |
| （指定なし） | — | — | default "auto" |

### なぜ安全か

1. **typo 握り潰しなし**: `--color rander` → serial の or(choices) が "rander" を Reject → serial 全体 Reject → exact consumed=1。"rander" は次のループで positional として消費されるか "unexpected argument" エラー
2. **後続トークン誤消費なし**: `--color --verbose` → or(choices) が "--verbose" を Reject → serial Reject → exact consumed=1。"--verbose" は次のループで正しくフラグ処理
3. **choices が門番**: serial 内の or(choices) が有効な値のみ通す。名前確定後の値不正は or の Reject として自然に処理される

**choices は optional value option では必須**。choices なしだと serial の値マッチが何でも Accept して後続トークンを奪う。

## API 設計

```moonbit
let color = p.string_opt(
  name="color",
  default="auto",
  implicit_value="always",
  choices=["always", "none", "auto"],
)

let md = p.string_opt(
  name="md",
  default="none",
  implicit_value=Thunk(fn() {
    if is_tty() { "render" } else { "source" }
  }),
  choices=["render", "source", "none"],
)
```

### implicit_value の型

`InitialValue[T]` を再利用:

```moonbit
pub(all) enum InitialValue[T] {
  Val(T)
  Thunk(() -> T)
}
```

- `implicit_value` 未指定 → 従来通り値必須（serial のみ、exact 値なしノードは生成しない）
- `implicit_value` 指定 → or(serial, exact) に展開

### choices の型と配置

choices は OptMeta に追加:

```moonbit
pub(all) struct OptMeta {
  // ... 既存フィールド
  choices : Array[String]    // 空なら制約なし
}
```

choices は:
- ヘルプ表示で有効な値を列挙
- optional value の serial 内で or(choices) として門番
- 通常の string_opt でもバリデーション用に使える（独立して有用）

## post フィルタ — パース後の値変換

git の `--color=auto` は、パーサが "auto" を受け取った後にアプリ側で tty を見て "always"/"none" に丸める。この「パース後の値変換」を post フィルタとして表現する。

```moonbit
let color = p.string_opt(
  name="color",
  default="auto",
  implicit_value="always",
  choices=["always", "none", "auto"],
  post=Filter::map(fn(s) {
    if s == "auto" {
      if is_tty() { "always" } else { "none" }
    } else { s }
  }),
)
```

- `color.get()` → `"always"` or `"none"`（"auto" は消滅）
- computed command 表示では post 適用後の値が使われる
- pre（String → T の前処理、DR-016）と対称的に post（T → T の後処理）

### なぜ pre だけでは不十分か

pre は `String → T`、default Thunk は `() → T`。同じロジック（例: "auto" → tty 判定 → "always"/"none"）でもシグネチャが異なるため、1つの関数を共有できない。post `T → T` なら値の出所（明示指定・implicit_value・default）に関係なく1箇所で処理できる。

### pre と post の違い

| | pre (FilterChain[String, T]) | post (FilterChain[T, T]) |
|---|---|---|
| タイミング | パース中（try_reduce 内） | パース完了後 |
| 型 | String → T | T → T |
| 対象 | 明示指定の値のみ | default・implicit_value 含む全値 |
| 失敗 | ParseError を raise | ParseError を raise |
| 用途 | 文字列→型変換、入力バリデーション | 正規化、遅延バリデーション |

### post フェーズ = 遅延バリデーションの統合先

パース完了後にしか判定できない検証・変換を post フェーズに統合:

| パターン | post での表現 |
|---|---|
| 値の正規化 | `Filter::map(fn(s) { if s == "auto" { resolve_tty() } else { s } })` |
| required | `Filter::validate(fn(s) { if s == "" { raise parse_error("required") } })` |
| 相互排他 | parse 後フックで複数 opt の値を横断チェック |
| 条件付き必須 | 同上 |

単一 opt に閉じた post は `FilterChain[T, T]` で表現。複数 opt を横断する検証（相互排他等）は別途パーサレベルのフックが必要。

post は parse 完了後に一括適用する。computed command 表示は post 適用後の値を使う。

## ヘルプ表示

### `=` マーカーによるデフォルト表示

choices がある場合、デフォルト値を `=` プレフィックスで示す:

```
# 従来の [default: xxx] 表記
--color <COLOR>  [default: auto]

# = マーカー表記（コンパクト）
--color [=always|none]
```

### 動的ヘルプ（Thunk 評価）

implicit_value が Thunk の場合、ヘルプ生成時に評価して `=` の位置を決定:

```
# tty で実行時
--md [=render|source|[=none]]

# non-tty で実行時
--md [render|=source|[=none]]
```

外側の `[=none]` はオプション自体のデフォルト（default）、内側の `=` は値省略時のデフォルト（implicit_value）。

### computed command 表示

省略・デフォルト・暗黙解決を全部展開した正規化コマンドの表示。デバッグに有用:

```
---
command: app timeline 8d780ec3 --md
command_computed: app timeline 8d780ec3 --md source --color none
---
```

## 全コンビネータへの汎用適用

implicit_value パターンは string_opt に限らず、値を取る全てのコンビネータに同じ展開で適用できる。

### 汎用展開パターン

```
or([
  serial([exact("--name"), value_matcher]),  // 値あり: consumed=2
  exact("--name", set=implicit_value),       // 値なし: consumed=1
])
```

`value_matcher` がコンビネータごとに異なるだけ:

| コンビネータ | value_matcher | implicit_value 例 |
|---|---|---|
| string_opt | or(choices) or any string | `"always"` |
| int_opt | int parser | `3000` |
| append_string | or(choices) or any string | `"latest"` |
| append_int | int parser | `1` |

### 具体例

```moonbit
// --port だけで 3000、--port 9090 で 9090
let port = p.int_opt(name="port", default=8080, implicit_value=3000)

// --tag だけで "latest" 追加、--tag foo で "foo" 追加
let tags = p.append_string(name="tag", implicit_value="latest")
```

int_opt の場合、value_matcher は int パーサ。`--port foo` → int パース失敗 → serial Reject → exact consumed=1 → implicit 3000。"foo" は次のループへ。choices がなくても型パーサが門番になる。

string_opt + choices なしの場合は門番がいないため、次の引数を値として誤消費するリスクがある。この組み合わせはユーザーの責任で使う（`--output` のように次の引数が常に値であることが文脈上明らかなケース）。

## 4層レイヤーとの整合

optional value option は Convention レイヤーの展開パターン:

```
string_opt(name="color", implicit_value="always", choices=[...])   # Sugar
  → or([serial, exact], default=...)                                # Convention: or + serial 展開
    → or([                                                          # Pattern: 同一 Ref の複数候補
        serial([exact("--color"), or(choices)]),                    # Core: ExactNode の組み合わせ
        exact("--color", set=implicit),
      ])
```

新しい Core 層の仕組みは不要。Convention 層でパーツを組み合わせるだけ。

## 実装順序

1. choices パラメータ + ヘルプ表示（optional value と独立して有用）
2. implicit_value パラメータ + or(serial, exact) 展開
3. `=` マーカーヘルプ表記
4. Thunk 対応の動的ヘルプ
5. computed command 表示

## レビュー指摘と対応

### 指摘: typo 握り潰し / 後続トークン誤消費（codex レビュー）

初版では単一 ExactNode 内で consumed=1/2 を試行する設計だった。codex から「typo が implicit_value にフォールバックされる」「choices なしで後続トークンを奪う」と指摘。

初版の対応として space 形式廃止（`--name=value` のみ）を採用したが、これは過剰な制約。

**最終対応**: 既存パーツ（or, serial, exact）の組み合わせで解決。serial 内の or(choices) が門番となり、不正な値は Reject。最長一致で serial(consumed=2) が exact(consumed=1) に勝つため、有効な値がある場合は正しく消費される。単一 ExactNode で頑張る必要がなかった。

## 実装撤回 → DR-020 へ

choices + implicit_value の実装は一度完了したが、`choices: Array[String]` が String 固定で汎用性がないことが判明し撤回。

**問題**: 候補が `exact(s) → s` のような単純文字列マッチに限定される。実際には `serial("rgb", int, int, int) → RGB(r,g,b)` のように、候補ごとにパーサの構造が異なるケースがある。値の受け口はコンビネータの組み合わせ（`or` of sub-parsers）であるべき。

post_hooks インフラと post パラメータは独立して有用なため残留。

詳細は DR-020 を参照。

## 実装状況（2026-03-07 更新）

DR-020 方針に基づき再実装完了。本 DR で設計した choices + implicit_value のコンセプトは、DR-020 の汎用 or コンビネータ設計を経て、以下の形で実装された。

### 実装済みの機能

- **string_opt**: `choices: Array[String]` + `implicit_value: Initial[String]?` パラメータとして実装
- **int_opt**: `implicit_value: Initial[Int]?` パラメータとして実装
- **内部展開**: `make_or_node` による composite ExactNode 展開（DR-020 の汎用 or 設計に基づく）
  - `make_choice_value_node` — choices からの値マッチノード生成
  - `make_implicit_flag_node` — 値省略時の implicit_value 適用ノード生成
  - `make_soft_value_node` — choices なしの柔軟な値マッチノード生成
  - `make_default_fallback_node` — consumed=0 のデフォルト値 fallback ノード生成

### 設計原則に基づく修正

- **OptMeta からの choices / has_implicit_value 削除**: ワークアラウンドフィールド排除の原則に従い、OptMeta にはパース制御用のフィールドを持たせない。choices と implicit_value はノード展開時に消費され、ExactNode の構造として表現される
- **post_hooks**: `Parser.post_hooks: Array[() -> Unit!ParseError]` として実装済み。parse_raw 末尾で全 hooks を実行。string_opt の `post` パラメータから登録される
