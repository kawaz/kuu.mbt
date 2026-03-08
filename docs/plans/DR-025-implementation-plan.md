# DR-025 実装計画: コンビネータの Compositional 分解

## ゴール

現在の6つのモノリシックコンビネータ（flag, string_opt, int_opt, count, append_string, append_int）を
内部プリミティブに分解し、ユーザーが型パラメトリックに組み立てられる compositional API を提供する。
既存コンビネータは互換ラッパーとして維持し、テスト667件を全通しさせる。

## 現状の問題

1. **options.mbt の肥大化（~790行）**: 6コンビネータが各自 make_*_node を直接組み立て、重複コードが多い
2. **implicit_value + choices で分岐爆発**: string_opt だけで4パターンの分岐がある
3. **拡張困難**: 新しいコンビネータ追加時に同じボイラープレートを繰り返す必要がある
4. **ユーザーカスタマイズ不可**: 既存6種以外のパターンをユーザーが作れない

## 設計方針

### 内部プリミティブは private を維持する

make_*_node 群や ExactNode ベースの内部実装は **pub 化しない**。
理由: DR-025 §4「現アーキテクチャからの距離」で指摘されている通り、ExactNode ベースから
reducer ツリーへの将来的な移行を阻害しないため、内部表現を API 契約にしない。

ユーザー向け API は `custom[T]` / `custom_append[T]` の高レベルコンビネータのみ公開する。

### choices は String 固定

`choices` パラメータは `Array[String]` 固定とする（pre 適用前の生入力値で比較）。
理由: MoonBit に型クラス（Eq 制約等）がないため、`Array[T]` + comparator の設計が複雑化する。
生値比較で十分な実用性があり、変換後の値で制約したい場合は `post` や `Filter::validate` で対応できる。

## フェーズ構成

### フェーズ1: Variation 展開の独立化

**目的**: 各コンビネータに散在する variation 展開ロジックを統一関数に集約

**変更内容**:
- `expand_variation_nodes` 関数を新設（private）:
  ```
  fn expand_variation_nodes(
    base_name: String,
    variations: Array[Variation],
    make_node_for_variation: (String, Variation) -> ExactNode,
  ) -> Array[ExactNode]
  ```
- **コールバック方式を採用する理由**:
  - Variation の意味論がコンビネータごとに異なる:
    - Toggle/True/False は Bool 専用（flag/count でのみ有効）
    - Reset/Unset は全コンビネータ共通（cell を initial に戻す / was_set を false に）
  - `cell: Ref[T]` を直接受け取る方式だと Toggle(Bool の反転) が T 汎用で表現できない
  - コールバックにすることで、各コンビネータが自分の型に合った variation ノードを生成できる
- 各コンビネータの make_long_nodes 内の for ループをコールバック付き統一関数呼び出しに置換

**注意**: 現在 options.mbt に既に `make_variation_nodes` ローカル関数が各コンビネータ内に
存在する可能性あり。それらを統合する形で進める。

**ファイル**: nodes.mbt（新関数追加）、options.mbt（リファクタリング）

**テスト影響**: なし

### フェーズ2: 統一オプション登録プリミティブ

**目的**: 共通の「ノード生成 + variation展開 + was_set管理 + expand_and_register + OptMeta構築」パイプラインを統一

**変更内容**:
- `Parser::register_option` を新設（private）:
  ```
  fn Parser::register_option[T](
    self: Parser,
    name~: String,
    aliases~: Array[String] = [],
    short~: Char = '\u0000',
    global~: Bool = false,
    help~: String = "",
    value_name~: String = "",
    default_display~: String = "",
    hidden~: Bool = false,
    kind~: OptKind = ValueOpt,
    variations~: Array[Variation] = [],
    was_set: Ref[Bool],
    make_main_node: (String) -> ExactNode,
    make_short_main_node: (String) -> ExactNode,
    make_node_for_variation: (String, Variation) -> ExactNode,
    reset_all: () -> Unit,  // cell + pending + was_set を全てリセット
    getter: () -> T,
  ) -> Opt[T]
  ```
- **コールバック方式の設計意図**:
  - `make_node_for_variation`: 各コンビネータが型に合った variation ノードを生成
    - flag: Toggle/True/False 対応（Bool 反転・固定値設定）
    - count: Reset 時に pending もリセット
    - custom: Toggle/True/False は Reset 相当にフォールバック（デフォルト値に戻す）
  - `reset_all`: cell だけでなく pending 等の内部状態も含めた完全リセット
    - count の pending/cell 2段階更新を正しく処理
  - cell/pending を register_option に渡さず、コールバック内でキャプチャさせる
- 共通処理を集約:
  1. make_main_node で主ノード生成
  2. wrap_node_with_set で was_set ラップ
  3. expand_variation_nodes + make_node_for_variation で variation ノード生成
  4. expand_and_register で登録
  5. OptMeta の構築と metas への追加
  6. Opt[T] の構築と返却
- 各コンビネータを register_option 呼び出しに書き換え

**ファイル**: parser.mbt（新関数）、options.mbt（書き換え）

**テスト影響**: なし

### フェーズ3: ユーザー向け compositional API

**目的**: 型パラメトリックなコンビネータをユーザーに公開

**変更内容**:

#### 3a. `Parser::custom` — 汎用値コンビネータ
```
pub fn Parser::custom[T](
  self: Parser,
  name~: String,
  aliases~: Array[String] = [],
  short~: Char = '\u0000',
  global~: Bool = false,
  help~: String = "",
  value_name~: String = "",
  default_display~: String = "",
  hidden~: Bool = false,
  variations~: Array[Variation] = [],
  default~: T,
  default_fn~: (() -> T)? = None,
  pre~: FilterChain[String, T],
  post~: FilterChain[T, T]? = None,
  choices~: Array[String] = [],
  implicit_value~: Lazy[T]? = None,
) -> Opt[T]
```
- string_opt/int_opt を統合した型パラメトリックなコンビネータ
- `pre` で String→T 変換を指定（必須）
- `post` で T→T の後処理を指定（任意）
- `default_fn` で動的デフォルト値を指定（任意、default より優先）
- `choices` は pre 適用前の生文字列で比較（Array[String] 固定）
- `implicit_value` は Lazy[T] で遅延評価
- **variation sugar params (toggle/true/false/reset/unset) は持たない**。
  `variations` 配列を直接渡す。sugar params は互換ラッパー（string_opt等）側の責務。
  custom に Toggle/True/False が渡された場合は Reset 相当として処理する
  （値コンビネータでは Bool 反転の意味論がないため、デフォルト値へのリセットにフォールバック）

#### 3b. `Parser::custom_append` — 累積コンビネータ
```
pub fn Parser::custom_append[T](
  self: Parser,
  name~: String,
  aliases~: Array[String] = [],
  short~: Char = '\u0000',
  global~: Bool = false,
  help~: String = "",
  value_name~: String = "",
  hidden~: Bool = false,
  variations~: Array[Variation] = [],
  pre~: FilterChain[String, T],
) -> Opt[Array[T]]
```
- append_string/append_int を統合
- custom 同様、variation sugar params は持たない

**ファイル**: options.mbt（新コンビネータ追加）

**テスト影響**: 新APIのテスト追加のみ

### フェーズ4: 既存コンビネータの互換ラッパー化

**目的**: 既存6コンビネータを新 API のラッパーとして再実装し、options.mbt を大幅削減

**変更内容**:
```
// string_opt → custom の薄いラッパー
pub fn Parser::string_opt(...) -> Opt[String] {
  self.custom(
    ...,
    pre=Filter::map(fn(s) { s }),  // identity
    ...
  )
}

// int_opt → custom の薄いラッパー
pub fn Parser::int_opt(...) -> Opt[Int] {
  self.custom(
    ...,
    pre=Filter::parse_int(),
    ...
  )
}

// append_string → custom_append の薄いラッパー
pub fn Parser::append_string(...) -> Opt[Array[String]] {
  self.custom_append(
    ...,
    pre=Filter::map(fn(s) { s }),
  )
}

// append_int → custom_append の薄いラッパー
pub fn Parser::append_int(...) -> Opt[Array[Int]] {
  self.custom_append(
    ...,
    pre=Filter::parse_int(),
  )
}
```

**flag/count は custom に統合しない**:
- flag は consumed=1（値引数なし）で custom（consumed=2）とは根本的に異なる
- count は flag ベースで累積（+1）する特殊パターン
- どちらも register_option を直接使って再実装する

**ファイル**: options.mbt（書き換え）

**テスト影響**: 既存テスト667件が全て通ることを確認

## リスクと対策

### 1. flag/count は custom とは consumed 数が異なる
- **対策**: flag/count は register_option を直接使い、custom には含めない

### 2. choices + implicit_value の組み合わせ複雑性
- **対策**: custom 内部で分岐を集約。4パターンの分岐は残るが、1箇所に集約されることで保守性向上

### 3. make_soft_int_value_node が options.mbt 内にある
- **対策**: フェーズ1 で nodes.mbt に移動

### 4. post フィルタの適用タイミング
- **対策**: post は parse 後の post_hooks で適用（現行 string_opt と同じ方式）

### 5. default_fn の適用タイミング
- **対策**: register_option 呼び出し前に `initial = default_fn.or(default)` で解決（現行と同じ）

## 成功基準

1. 既存テスト667件が全て通る
2. options.mbt のコード量が大幅削減される
3. ユーザーが `custom` で独自型のオプションを作れる（例: Float, Path, Enum）
4. 新しい型のオプション追加が FilterChain 一つで可能
5. post / default_fn / choices / implicit_value が custom でも動作する

## codex レビュー指摘事項（対応済み）

1. ~~post と default_fn が custom API に含まれていない~~ → 追加済み
2. ~~make_*_node の pub 化は将来移行を自爆する~~ → 内部プリミティブは private 維持に変更
3. ~~choices: Array[T] は Eq 制約なしで不可能~~ → Array[String] 固定に変更
4. ~~make_variation_nodes の Ref[T] 汎用化は Toggle/True/False(Bool専用) で破綻~~ → コールバック方式に変更
5. ~~register_option に pending がなく count の2段階更新が壊れる~~ → reset_all コールバック + cell/pending をキャプチャ方式に変更
6. ~~custom が variation_toggle/true/false を受けるのに Reset/Unset のみ対応は自己矛盾~~ → custom から sugar params を削除、variations 配列のみ受付に変更
