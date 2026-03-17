# DR-001: サロゲートペア問題の調査と分析

## ステータス

調査完了

## 背景

MoonBit の String は UTF-16 内部表現を採用しており、U+10000 以上の文字（Supplementary Plane）はサロゲートペア（2つの UTF-16 コードユニット）で表現される。kuu の short combining 実装がこの特性に対応しているか調査する。

## 発見された問題

### 問題1: short node 収集条件の不一致

**ファイル**: `src/core/parse.mbt:169`

```moonbit
node.name.length() == 2
```

short combining で使用する short node の収集条件が `name.length() == 2` となっている。`length()` は UTF-16 コードユニット数を返すため:

- BMP 文字の short option（例: `-v`）: `"-v".length() == 2` → 収集される
- Supplementary Plane 文字の short option（例: `-😀`）: `"-😀".length() == 3` → 収集されない

**修正案**: `node.name.char_length() == 2` に変更

### 問題2: インデックスアクセスによるサロゲートペア分割

**ファイル**: `src/core/parse.mbt:195-196`

```moonbit
while ri < rest.length() {
  let ch = rest[ri].to_int().unsafe_to_char()
```

`rest[ri]` は UTF-16 コードユニット単位のインデックスアクセスで、サロゲートペアの high/low を個別に取得してしまう。`unsafe_to_char()` で変換すると、不正なコードポイント（0xD800-0xDFFF）が生成される。

壊れた Char の `to_string()` は abort せず、長さ1の不正な文字列を生成する。これにより `short_name` が不正な値になり、ノード名と不一致で `Reject` が返される。

**修正案**: `for ch in rest` のイテレータを使用し、位置管理を別途行う

### 問題3: インデックス算術の不整合

**ファイル**: `src/core/parse.mbt:230, 259, 277`

```moonbit
ri += 1
ri = ri + 1 + try_len
```

インデックス `ri` が常に 1 コードユニットずつ進むため、サロゲートペア文字（2 コードユニット）の後の位置計算がずれる。

**修正案**: 各文字の UTF-16 コードユニット数（BMP: 1, Supplementary: 2）を考慮した加算、またはイテレータベースへの全面書き換え

### 問題4: substring 位置のずれ

**ファイル**: `src/core/parse.mbt:210`

```moonbit
let remaining = rest.unsafe_substring(start=ri + 1, end=rest.length())
```

`ri + 1` がサロゲートペアの途中を指す可能性がある。

## 影響範囲

### 影響を受ける機能

- short combining（`-abc` → `-a -b -c` 展開）
  - Supplementary Plane 文字の short option が combining に参加できない
  - BMP 文字と Supplementary Plane 文字の混在 combining が失敗する（Reject → "unexpected argument"）

### 影響を受けない機能

- 個別の short option 使用（`-😀` 単体）: ノードマッチングは文字列比較なので正常
- long option: `--emoji` 等は影響なし
- shorts パラメータの登録: `for ch in shorts` イテレータ使用で安全
- `String.to_array()`: Char（コードポイント）配列を返すので安全

## 全体スキャン結果

`install_short_combine_node` 以外にも問題箇所が見つかった。テストファイルを除く全ソースをスキャンした結果:

| # | ファイル:行 | 問題 | 影響 |
|---|------------|------|------|
| 1 | parse.mbt:3-4 | `levenshtein()` で `length()` を文字数として使用 | タイプ補完の距離計算がずれる |
| 2 | parse.mbt:14 | `levenshtein()` で `a[i-1] == b[j-1]` インデックスアクセス | 文字比較が誤る |
| 3 | parse.mbt:169 | `name.length() == 2` で short node 収集 | Supplementary Plane short が除外 |
| 4 | parse.mbt:187 | `arg.length() <= 2` で combining 判定 | 判定がずれる |
| 5 | parse.mbt:190 | `unsafe_substring` + `arg.length()` | 部分文字列の範囲がずれる |
| 6 | parse.mbt:195-196 | `rest[ri]` + `unsafe_to_char()` ループ | サロゲートペア分割 |
| 7 | parse.mbt:210 | `unsafe_substring(start=ri+1, ...)` | 位置ずれ |
| 8 | parse.mbt:217 | `unsafe_substring(start=0, end=try_len)` | 値候補のカット位置がずれる |
| 9 | nodes.mbt:137 | `unsafe_substring(start=2, end=opt_name.length())` | Variation 名の基本名抽出がずれる |

## 3層の Unicode 問題

| レイヤー | 問題 | 修正方法 | 時期 |
|----------|------|----------|------|
| L1: UTF-16 encoding | `length()` + `str[i]` がコードユニット単位 | `char_length()` + `iter()` / `to_array()` | 即時対応 |
| L2: Grapheme cluster | 合成絵文字（🇯🇵 👨‍👩‍👧‍👦 等）が複数コードポイント | grapheme cluster segmentation (UAX #29) | 将来対応 |
| L3: Display width | 全角/半角の表示幅 | `rami3l/unicodewidth` | 必要時 |

### L2: Grapheme cluster の詳細

合成絵文字の例:

| 見た目 | コードポイント数 | 構成 |
|--------|-----------------|------|
| 😀 | 1 | U+1F600 |
| 🇯🇵 | 2 | U+1F1EF U+1F1F5 (Regional Indicator) |
| 👋🏽 | 2 | U+1F44B U+1F3FD (Skin tone modifier) |
| 👨‍👩‍👧‍👦 | 7 | 4 emoji + 3 ZWJ |

L1 修正後も `shorts="🇯🇵"` は `for ch in shorts` で 2 つの short option として登録されてしまう。

**MoonBit エコシステムの現状**: grapheme cluster segmentation ライブラリは存在しない。
- `moonbit-community/unicode_data` に `is_grapheme_extend()` はあるが `Grapheme_Cluster_Break` テーブルはない
- `rami3l/unicodewidth` は表示幅計算のみ
- 将来的には `unicode_data` ジェネレータ拡張 or UAX #29 自前実装が必要

## 修正方針

### Phase 1: UTF-16 修正（即時）

上記9箇所を修正。主な手法:

1. `length()` → `char_length()`
2. `str[i]` ループ → `to_array()` で `Array[Char]` に変換してからイテレート
3. `unsafe_substring` + UTF-16 インデックス → char 配列ベースの部分文字列構築
4. `unsafe_to_char()` の排除
5. `levenshtein()` は配列化してから DP 計算

### Phase 2: Grapheme cluster 対応（将来）

shorts 登録・short combining・文字カウント全般を grapheme cluster 単位に。
ライブラリ整備が前提。

## 決定

本 PoC で問題の全体像を検証・記録。修正は別ワークスペースで Phase 1 から着手する。
