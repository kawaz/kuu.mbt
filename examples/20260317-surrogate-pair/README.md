# 20260317-surrogate-pair

## テーマ

kuu の short combining におけるサロゲートペア（supplementary plane 文字）の扱いを調査・検証する PoC。

## 背景

- MoonBit の String は UTF-16 内部表現
- `length()` は UTF-16 コードユニット数を返す
- `char_length()` は Unicode コードポイント数を返す
- short combining（`-abc` → `-a -b -c` 展開）で supplementary plane の文字（U+10000以上）を使った場合、サロゲートペアにより正しく分割されない可能性がある

## 調査結果

### 発見された問題

`install_short_combine_node`（`src/core/parse.mbt`）に4つの問題:

1. **L169**: `node.name.length() == 2` — UTF-16 基準で Supplementary Plane 文字の short node が収集漏れ
2. **L195-196**: `rest[ri].to_int().unsafe_to_char()` — サロゲートペア分割（abort の可能性）
3. **L210, 230, 259, 277**: コードユニット単位のインデックス算術 — 位置ずれ
4. 壊れた Char の `to_string()` は **abort** を引き起こす（recover 不能）

### テスト結果（13テスト全通過）

| テスト | 結果 | 説明 |
|--------|------|------|
| BMP combining `-vaf` | 正常動作 | 従来通り |
| Supplementary 個別 `-😀` | 正常動作 | 文字列比較でマッチ |
| Supplementary combining `-😀v` | ParseError | name.length()==2 で除外 |
| 混在 combining `-v😀` | ParseError | インデックスアクセスでサロゲートペア分割 |

### 実用上の影響度

**低〜中**: CLI short option に絵文字等を使うケースは稀だが、`unsafe_to_char()` + `to_string()` が abort する潜在的安全性問題あり。

## ファイル構成

- `main.mbt` — 13テスト（Part 1: String UTF-16, Part 2: 破壊パターン, Part 3: kuu combining）
- `DESIGN.md` — 詳細設計・分析
- `docs/decision-records/DR-001-surrogate-pair-issues.md` — Design Record

## 詳細

[DESIGN.md](DESIGN.md) / [DR-001](docs/decision-records/DR-001-surrogate-pair-issues.md)
