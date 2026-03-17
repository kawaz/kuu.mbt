# サロゲートペア調査 PoC

## 概要

MoonBit の String UTF-16 内部表現に起因する kuu の short combining の問題を調査・検証する PoC。

## 調査対象

### MoonBit String の UTF-16 特性

| API | 返す値 | サロゲートペア対応 |
|-----|--------|-------------------|
| `length()` | UTF-16 コードユニット数 | 非対応（2つにカウント） |
| `char_length()` | Unicode コードポイント数 | 対応 |
| `str[i]` | i番目の UTF-16 コードユニット値 (Int) | 非対応（ペアが分割される） |
| `iter()` | コードポイント単位イテレータ | 対応 |
| `to_array()` | `Array[Char]`（コードポイント配列） | 対応 |
| `unsafe_to_char()` | Int→Char 強制変換 | 非対応（不正な Char が生成される） |

### 重要な発見

壊れた Char（サロゲート半分）の `to_string()` は abort せず、長さ1の不正な文字列を生成する。これにより kuu の combining は `Reject` → "unexpected argument" エラーとなる。

### kuu の問題箇所

`src/core/parse.mbt` の `install_short_combine_node` 関数:

1. **L169**: `node.name.length() == 2` — UTF-16 基準で Supplementary Plane 文字の short node が収集漏れ
2. **L195-196**: `rest[ri].to_int().unsafe_to_char()` — サロゲートペア分割 → 不正な文字列生成
3. **L210, 230, 259, 277**: コードユニット単位のインデックス算術 — 位置ずれ

### 安全な箇所

- `src/core/parser.mbt:460` の `expand_and_register`: `for ch in shorts` イテレータ使用
- `src/core/parser.mbt:104` の `shorts.to_array()`: コードポイント配列を返す

## テストケース

### Part 1: String UTF-16 動作確認
- `length()` vs `char_length()` の差異
- インデックスアクセスの挙動
- イテレータの正常動作
- `to_array()` のコードポイント単位動作

### Part 2: サロゲートペア破壊パターン
- `unsafe_to_char()` による不正 Char 生成
- `length()` ベースループの破壊的動作
- `iter()` ベースループの安全な動作

### Part 3: kuu short combining 検証
- BMP 文字のみの combining → 正常動作
- Supplementary Plane 文字の個別使用 → 正常動作
- 複数 Supplementary Plane 文字の combining → ParseError で失敗
- Supplementary Plane 文字の combining → ParseError で失敗
- BMP + Supplementary 混在 combining → ParseError で失敗

## 結論

詳細は [DR-001](docs/decision-records/DR-001-surrogate-pair-issues.md) を参照。
