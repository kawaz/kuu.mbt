---
type: implementation
---

# DR-049: サロゲートペア対応（unicodegrapheme 導入）

## 概要

MoonBit の String は UTF-16 内部表現を採用しており、`length()` や `str[i]` は UTF-16 コードユニット単位で動作する。kuu の short combining と levenshtein 距離計算において、Supplementary Plane 文字（U+10000 以上、例: 絵文字）が正しく処理されない問題を `kawaz/unicodegrapheme` ライブラリの導入で解決する。

## 背景（3層 Unicode 問題の L1 対応）

`examples/20260317-surrogate-pair/` での調査により、Unicode 処理には3層の問題が存在することが判明した。

| レイヤー | 問題 | 対応方法 | 対応時期 |
|----------|------|----------|----------|
| L1: UTF-16 encoding | `length()` + `str[i]` がコードユニット単位 | unicodegrapheme 導入 | 本 DR |
| L2: Grapheme cluster | 合成絵文字（🇯🇵 👨‍👩‍👧‍👦 等）が複数コードポイント | unicodegrapheme UAX #29 対応済み → levenshtein/short combining は自動対応、shorts 登録は未対応 | 一部完了 |
| L3: Display width | 全角/半角の表示幅 | `rami3l/unicodewidth` | 必要時 |

本 DR では L1 の問題を解決する。修正手段として `char_length()` / `to_array()` ではなく `unicodegrapheme` の `graphemes()` を使うことで、将来の L2 対応時に必要なコード変更量を最小化する（ただし shorts の型変更等、別途対応が必要な箇所は残る。詳細は末尾「L2 対応時の追加変更」を参照）。

## 方針: unicodegrapheme による統一的な文字分割

### なぜ char_length() / to_array() ではなく unicodegrapheme か

`char_length()` への置き換えは L1（サロゲートペア）を解決するが、L2（grapheme cluster）は解決しない。国旗絵文字（🇯🇵 = 2コードポイント）や ZWJ 絵文字（👨‍👩‍👧‍👦 = 7コードポイント）をユーザーが short option に使った場合、`char_length()` ベースでは依然として正しく動作しない。

`kawaz/unicodegrapheme` を使えば:

1. 現時点（Phase 0）ではコードポイント単位の分割（L1 解決と同等）
2. 将来 UAX #29 準拠になれば、kuu のコード変更なしで L2 も解決
3. 「1文字」の定義が一貫して grapheme cluster になる

### unicodegrapheme API

```
kawaz/unicodegrapheme/src
├── graphemes(s: String) -> GraphemeView
├── GraphemeView::length() -> Int      # grapheme cluster 数
├── GraphemeView::op_get(i: Int) -> StringView  # i番目の cluster
└── GraphemeView::iter() -> Iter[StringView]    # イテレータ
```

### 使い分けの判断基準

| ケース | 使うべき手段 |
|--------|-------------|
| 「1文字ずつ処理」する箇所（short combining、levenshtein） | `graphemes()` 必須 |
| 「文字数の比較」で分岐する箇所（short node 収集条件等） | `graphemes()` が適切 |
| ASCII 固定のプレフィックス除去（`--` の除去等） | `unsafe_substring` で問題なし |
| `find("=")` + `unsafe_substring` の組み合わせ | UTF-16 座標系で内部一貫しているため問題なし |

## 修正箇所（9箇所の詳細）

### 問題 1-2: levenshtein 関数（parse.mbt:2-32）

**現在のコード:**
```moonbit
let m = a.length()
let n = b.length()
// ...
let cost = if a[i - 1] == b[j - 1] { 0 } else { 1 }
```

**問題:** `length()` は UTF-16 コードユニット数、`a[i-1]` は UTF-16 インデックスアクセス。サロゲートペア文字を含む文字列では文字数・文字比較ともに誤る。

**修正方針:** `graphemes()` で `GraphemeView` に変換し、`length()` と `op_get(i)` で grapheme cluster 単位の DP 計算を行う。

```moonbit
// 擬似コード
let ga = graphemes(a)
let gb = graphemes(b)
let m = ga.length()
let n = gb.length()
// ...
let cost = if ga[i - 1].to_string() == gb[j - 1].to_string() { 0 } else { 1 }
```

`StringView` 同士の比較は `to_string()` 経由。kuu において levenshtein はタイポ候補提示（距離 <= 2）にのみ使用されるため、パフォーマンス影響は無視できる。

### 問題 3: short node 収集条件（parse.mbt:169）

**現在のコード:**
```moonbit
if node.name.length() == 2 &&
  node.name.has_prefix("-") &&
  not(node.name.has_prefix("--")) {
```

**問題:** `name.length() == 2` は UTF-16 コードユニット数。`"-😀".length() == 3` のため、Supplementary Plane 文字の short option がフィルタから漏れる。

**修正方針:** `graphemes(node.name).length() == 2` に変更。grapheme cluster 数で「`-` + 1文字」を判定する。

```moonbit
if graphemes(node.name).length() == 2 &&
  node.name.has_prefix("-") &&
  not(node.name.has_prefix("--")) {
```

### 問題 4: combining 判定条件（parse.mbt:187）

**現在のコード:**
```moonbit
if arg.length() <= 2 || not(arg.has_prefix("-")) || arg.has_prefix("--") {
  return Reject
}
```

**問題:** `arg.length() <= 2` は UTF-16 コードユニット数。`"-😀".length() == 3` なので、単独の Supplementary Plane short option が combining パスに入ってしまう（本来は単独マッチすべき）。また `"-😀🎉".length() == 5` だが grapheme としては3文字（`-` + 2文字）なので combining 対象として正しい。

**修正方針:** `graphemes(arg).length() <= 2` に変更。

```moonbit
if graphemes(arg).length() <= 2 || not(arg.has_prefix("-")) || arg.has_prefix("--") {
  return Reject
}
```

### 問題 5: rest 部分文字列の取得（parse.mbt:190）

**現在のコード:**
```moonbit
let rest = arg.unsafe_substring(start=1, end=arg.length())
```

**分析:** `start=1` は `-`（ASCII、1 UTF-16 unit）のスキップであり、`end=arg.length()` は文字列末尾の UTF-16 オフセット。`unsafe_substring` は UTF-16 座標系で動作するため、この行自体は正しい。

**ただし:** 後続の `rest.length()` や `rest[ri]` が UTF-16 ベースで動作するため、`rest` を grapheme 単位で処理するよう全体を書き換える必要がある。

**修正方針:** `rest` の取得自体は変更不要だが、後続処理を `graphemes(rest)` ベースに書き換える。

### 問題 6: コードユニット単位のイテレーション（parse.mbt:195-196）

**現在のコード:**
```moonbit
while ri < rest.length() {
  let ch = rest[ri].to_int().unsafe_to_char()
  let short_name = "-" + ch.to_string()
```

**問題:** `rest[ri]` は UTF-16 コードユニットのインデックスアクセス。サロゲートペアの high surrogate（0xD800-0xDBFF）を単独で取得し、`unsafe_to_char()` で不正な Char に変換する。結果、`short_name` が壊れた文字列になりノードマッチに失敗する。

**修正方針:** `graphemes(rest)` で `GraphemeView` に変換し、grapheme cluster 単位でイテレートする。

```moonbit
// 擬似コード
let rest_g = graphemes(rest)
let mut ri = 0
while ri < rest_g.length() {
  let cluster = rest_g[ri]  // StringView
  let short_name = "-" + cluster.to_string()
```

### 問題 7: remaining の部分文字列取得（parse.mbt:210）

**現在のコード:**
```moonbit
let remaining = rest.unsafe_substring(start=ri + 1, end=rest.length())
```

**問題:** `ri` が UTF-16 コードユニット単位のインデックスであるため、サロゲートペア文字の後では `ri + 1` がペアの途中を指す。

**修正方針:** grapheme インデックスから UTF-16 オフセットへの変換が必要。`GraphemeView` の境界情報を活用するか、`ri + 1` 以降の grapheme cluster を結合して remaining を構築する。

```moonbit
// 擬似コード: ri+1 以降の grapheme cluster から remaining を構築
let remaining_parts : Array[String] = []
for j = ri + 1; j < rest_g.length(); j = j + 1 {
  remaining_parts.push(rest_g[j].to_string())
}
let remaining = remaining_parts.join("")
```

あるいは `GraphemeView` に range アクセスを追加する方が効率的だが、Phase 0 ではこの方式で十分。

### 問題 8: value 候補のカット（parse.mbt:217）

**現在のコード:**
```moonbit
let try_value = remaining.unsafe_substring(start=0, end=try_len)
```

**問題:** `try_len` が UTF-16 コードユニット数として使われており、サロゲートペア文字の途中で切断される可能性がある。

**修正方針:** `remaining` も `graphemes()` で処理し、grapheme cluster 数で try_len を管理する。

```moonbit
// 擬似コード
let remaining_g = graphemes(remaining)
let mut try_len = remaining_g.length()
while try_len > 0 {
  // try_len 個の grapheme cluster を結合して try_value を構築
  let parts : Array[String] = []
  for j = 0; j < try_len; j = j + 1 {
    parts.push(remaining_g[j].to_string())
  }
  let try_value = parts.join("")
```

### 問題 9: variation 名の基本名抽出（nodes.mbt:137）

**現在のコード:**
```moonbit
let base = opt_name.unsafe_substring(start=2, end=opt_name.length())
```

**分析:** `opt_name` は必ず `--` で始まる long option 名（例: `--verbose`）。`start=2` は `--`（ASCII 2文字 = UTF-16 2 unit）のスキップであり、`end=opt_name.length()` は文字列末尾の UTF-16 オフセット。`unsafe_substring` の座標系と一致しているため、**この箇所は問題なし**。

long option 名に Supplementary Plane 文字が含まれていても（例: `--😀mode`）、`--` の除去は正しく動作する。生成される base が正しい文字列であり、`"--" + prefix + "-" + base` の文字列結合も問題ない。

**修正方針:** 修正不要。ASCII 固定プレフィックスの除去であり、UTF-16 座標系で内部一貫している。

## eq_split ノード（parse.mbt:105-110）の安全性

DR-001 の9箇所には含まれていないが、念のため分析する。

```moonbit
let eq_pos = match arg.find("=") { ... }
let name = arg.unsafe_substring(start=0, end=eq_pos)
let value = arg.unsafe_substring(start=eq_pos + 1, end=arg.length())
```

`find("=")` は `=`（ASCII）の UTF-16 オフセットを返す。`unsafe_substring` も UTF-16 オフセットで動作するため、座標系が一致しており問題なし。option 名部分にサロゲートペア文字が含まれていても、`=` の位置は正しく検出され、分割も正しく行われる。

**修正不要。**

## 修正箇所のまとめ

| # | ファイル:行 | 要修正 | 修正手段 |
|---|------------|--------|----------|
| 1 | parse.mbt:3 | YES | `graphemes()` で文字数取得 |
| 2 | parse.mbt:14 | YES | `graphemes()` で文字単位アクセス |
| 3 | parse.mbt:169 | YES | `graphemes()` で文字数判定 |
| 4 | parse.mbt:187 | YES | `graphemes()` で文字数判定 |
| 5 | parse.mbt:190 | NO | UTF-16 座標系で内部一貫（後続処理の書き換えで対応） |
| 6 | parse.mbt:195-196 | YES | `graphemes()` イテレーション |
| 7 | parse.mbt:210 | YES | grapheme ベースの remaining 構築 |
| 8 | parse.mbt:217 | YES | grapheme ベースの try_len 管理 |
| 9 | nodes.mbt:137 | NO | ASCII 固定プレフィックス除去、修正不要 |

実質修正箇所: 7箇所（#1, #2, #3, #4, #6, #7, #8）

## ローカル依存の追加方法

### moon.mod.json への deps 追加

MoonBit ではローカルパッケージを `path` 指定で依存に追加できる。

```json
{
  "name": "kawaz/kuu",
  "version": "0.1.0",
  "deps": {
    "kawaz/unicodegrapheme": {
      "path": "../../unicodegrapheme/main"
    }
  }
}
```

`path` は `moon.mod.json` からの相対パス。kuu.mbt の `main/` から unicodegrapheme の `main/` へは `../../unicodegrapheme/main`（`main → kuu.mbt → kawaz → unicodegrapheme → main`）。

ただし mooncakes.io に公開する場合はバージョン指定に切り替える必要がある:

```json
"kawaz/unicodegrapheme": "0.1.0"
```

公開前に unicodegrapheme 自体も mooncakes.io に publish しておく必要がある。

**注意:** ローカル `path` 指定は同じディレクトリ構成を持たない環境では `moon test` が失敗する。開発段階では許容するが、CI/CD や公開前に必ずバージョン指定に切り替えること。

### moon.pkg（src/core）での import 追加

`src/core/moon.pkg`（または対応するパッケージ設定ファイル）に import を追加:

```
import(
  "kawaz/unicodegrapheme/src"
)
```

コード内では `@src.graphemes(s)` のように修飾名で呼び出す。エイリアスを設定する場合:

```
import(
  "kawaz/unicodegrapheme/src" as unicodegrapheme
)
```

→ `@unicodegrapheme.graphemes(s)` で呼び出し可能。

### 開発時の手順

1. `moon.mod.json` に `path` ベースの deps を追加
2. `src/core` の moon.pkg に import を追加
3. `moon check` で依存解決を確認
4. 修正コードで `@unicodegrapheme.graphemes()` を使用
5. 公開時に `path` → バージョン指定に切り替え

## テスト戦略

### TDD: テストを先に書く

t_wada 式 TDD に従い、修正前にテストを書く。

#### 1. short combining テスト

```
# BMP 絵文字の short combining
-😀😎 → -😀 -😎 に展開

# Supplementary Plane 絵文字の short combining
-🎉🎊 → -🎉 -🎊 に展開

# BMP と Supplementary の混在
-v😀w → -v -😀 -w に展開

# short + value combining（絵文字 short に値が続く）
-😀value → -😀 に value が渡される

# 単独の絵文字 short（combining されないケース）
-😀 → 単独マッチ
```

#### 2. levenshtein テスト

```
# 同一文字列（絵文字含む）
levenshtein("--😀mode", "--😀mode") == 0

# 1文字違い（絵文字含む）
levenshtein("--😀mode", "--😀mod") == 1

# 絵文字の置換
levenshtein("--😀", "--😎") == 1
```

#### 3. variation テスト

```
# 絵文字 long option の variation 展開
--😀mode の variation → --no-😀mode 等
（これは修正不要だが、安全性の確認テスト）
```

#### 4. 回帰テスト

既存の1016件のテストが全て通ることを確認。

### テスト実行

```bash
moon test --target all
```

## L2 対応との関係

### unicodegrapheme の UAX #29 対応状況

unicodegrapheme は UAX #29 (Unicode 16.0.0) 全対応を完了。公式テスト全1,093ケース合格済み。

| 入力 | graphemes().length() | 備考 |
|------|---------------------|------|
| `"😀"` | 1 | Supplementary Plane |
| `"🇯🇵"` | 1 | Regional Indicator × 2 (GB12/13) |
| `"👨‍👩‍👧‍👦"` | 1 | ZWJ シーケンス (GB11) |
| `"👋🏽"` | 1 | スキントーン修飾 (GB9 Extend) |

### L2 対応の現状

本 DR で修正した箇所（levenshtein、short combining 展開）は unicodegrapheme の分割粒度に依存するだけなので、UAX #29 対応により **L2 も自動的に解決済み**:

- levenshtein: grapheme cluster 単位で距離計算 → **対応済み**
- short combining 展開: grapheme cluster 単位でイテレーション → **対応済み**
- 合成絵文字テスト8件で検証済み（国旗/ZWJ/スキントーン）

### kuu 側で残る L2 未対応箇所

shorts の登録パスが `Array[Char]` のままなので、合成絵文字（複数コードポイント）を short option として登録できない:

- `types.mbt:150` の `shorts : Array[Char]` → `Array[String]` への型変更
- `parser.mbt:106` の `shorts.to_array()` → grapheme 単位分割
- `parser.mbt:439,462` の `for ch in shorts` → grapheme 単位イテレーション

これらは必要になった時点で対応する。現実的に合成絵文字を short option に使うユースケースは稀。
