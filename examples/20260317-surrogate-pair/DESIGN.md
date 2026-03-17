# サロゲートペア調査 PoC

## 概要

MoonBit の String UTF-16 内部表現に起因する kuu の Unicode 文字処理の問題を調査・検証する PoC。

## 3層の Unicode 問題

| レイヤー | 問題 | 修正方法 | 時期 |
|----------|------|----------|------|
| L1: UTF-16 encoding | `length()` + `str[i]` がコードユニット単位 | `char_length()` + `iter()` / `to_array()` | 即時 |
| L2: Grapheme cluster | 合成絵文字が複数コードポイント | UAX #29 grapheme segmentation | 将来 |
| L3: Display width | 全角/半角の表示幅 | `rami3l/unicodewidth` | 必要時 |

## MoonBit String の UTF-16 特性

| API | 返す値 | サロゲートペア対応 |
|-----|--------|-------------------|
| `length()` | UTF-16 コードユニット数 | 非対応（2つにカウント） |
| `char_length()` | Unicode コードポイント数 | 対応 |
| `str[i]` | i番目の UTF-16 コードユニット値 (UInt16) | 非対応（ペアが分割される） |
| `iter()` | コードポイント単位イテレータ | 対応 |
| `to_array()` | `Array[Char]`（コードポイント配列） | 対応 |
| `unsafe_to_char()` | Int→Char 強制変換 | 非対応（不正な Char が生成される） |

壊れた Char の `to_string()` は abort せず、長さ1の不正な文字列を生成する。

## 問題箇所一覧（全9箇所）

| # | ファイル:行 | パターン | 影響 |
|---|------------|----------|------|
| 1 | parse.mbt:3-4 | `length()` で文字数取得 | levenshtein 距離計算ずれ |
| 2 | parse.mbt:14 | `str[i]` インデックスアクセス | levenshtein 文字比較誤り |
| 3 | parse.mbt:169 | `name.length() == 2` | short node 収集漏れ |
| 4 | parse.mbt:187 | `arg.length() <= 2` | combining 判定ずれ |
| 5 | parse.mbt:190 | `unsafe_substring` + `length()` | 部分文字列範囲ずれ |
| 6 | parse.mbt:195-196 | `rest[ri]` + `unsafe_to_char()` | サロゲートペア分割 |
| 7 | parse.mbt:210 | `unsafe_substring(start=ri+1)` | 位置ずれ |
| 8 | parse.mbt:217 | `unsafe_substring(end=try_len)` | 値候補カット位置ずれ |
| 9 | nodes.mbt:137 | `unsafe_substring(start=2)` | Variation 基本名抽出ずれ |

### 安全な箇所

- `parser.mbt:460` の `expand_and_register`: `for ch in shorts` イテレータ
- `parser.mbt:104` の `shorts.to_array()`: コードポイント配列
- `src/dx/` 全体: core をラップするのみで文字列処理なし

## L2: Grapheme cluster 問題

L1 修正後もコードポイント単位の処理では合成絵文字を正しく扱えない:

| 見た目 | CP数 | 構成 |
|--------|------|------|
| 😀 | 1 | U+1F600（L1修正で対応可） |
| 🇯🇵 | 2 | Regional Indicator × 2 |
| 👋🏽 | 2 | Emoji + Skin tone modifier |
| 👨‍👩‍👧‍👦 | 7 | Emoji × 4 + ZWJ × 3 |

`shorts="🇯🇵"` → `for ch in shorts` で 2 つの short option として登録されてしまう。

**MoonBit エコシステム現状**: grapheme cluster segmentation ライブラリは存在しない。
将来的に `unicode_data` ジェネレータ拡張 or UAX #29 自前実装が必要。

## テストケース（14テスト全通過）

### Part 1: String UTF-16 動作確認 (6テスト)
### Part 2: サロゲートペア破壊パターン (4テスト)
### Part 3: kuu short combining 検証 (4テスト)

## 結論

詳細は [DR-001](docs/decision-records/DR-001-surrogate-pair-issues.md) を参照。
