# 20260317-surrogate-pair

## テーマ

kuu における Unicode 文字処理の問題を調査・検証する PoC。

## 背景

- MoonBit の String は UTF-16 内部表現
- `length()` / `str[i]` は UTF-16 コードユニット単位で動作する
- kuu の short combining 等でサロゲートペア文字や合成絵文字が正しく処理されない

## 発見された問題

### 3層の Unicode 問題

| レイヤー | 問題 | 影響 |
|----------|------|------|
| L1: UTF-16 | `length()` + `str[i]` がコードユニット単位 | サロゲートペア文字で combining が壊れる |
| L2: Grapheme cluster | 合成絵文字（🇯🇵 👨‍👩‍👧‍👦 等）が複数コードポイント | 国旗や家族絵文字が複数文字として扱われる |
| L3: Display width | 全角/半角の表示幅 | ヘルプ表示のカラム揃え（引数パーサとしては非本質） |

### 問題箇所（全9箇所）

`parse.mbt` に8箇所、`nodes.mbt` に1箇所。詳細は [DR-001](docs/decision-records/DR-001-surrogate-pair-issues.md)。

### テスト結果（14テスト全通過）

| テスト | 結果 | 説明 |
|--------|------|------|
| BMP combining `-vaf` | 正常動作 | 従来通り |
| Supplementary 個別 `-😀` | 正常動作 | 文字列比較でマッチ |
| 複数 Supplementary `-😀😂` | ParseError | name.length()==2 で除外 |
| Supplementary combining `-😀v` | ParseError | name.length()==2 で除外 |
| 混在 combining `-v😀` | ParseError | サロゲートペア分割で不正文字列 → Reject |

## 結論と対応方針

### L1: UTF-16 修正

`length()` → `char_length()`、`str[i]` → `iter()` / `to_array()` に変更。全9箇所。
引数は所詮 CLI 引数で長大なデータではないので、入口で `Array[String]` を文字単位の表現に変換してしまうのが最もシンプル。

### L2: Grapheme cluster 対応

L1 を修正しても合成絵文字（🇯🇵 = 2コードポイント、👨‍👩‍👧‍👦 = 7コードポイント）は複数文字として扱われる。
正しく1文字として扱うには grapheme cluster segmentation（UAX #29）が必要。

MoonBit エコシステムにはこれを提供するライブラリが存在しなかったため、本 PoC の成果として独立パッケージを新規作成した:

- **リポジトリ**: [kawaz/unicodegrapheme](https://github.com/kawaz/unicodegrapheme)
- **API**: `graphemes(s) -> GraphemeView` — 元 String のゼロコピースライスとして各 grapheme cluster にアクセス
- **現状**: Phase 0（コードポイント単位の暫定実装）。UAX #29 準拠は Phase 1 以降。

### kuu への適用

1. `unicodegrapheme` の UAX #29 実装が完了したら kuu に組み込む
2. 内部表現を `Array[String]`（各要素 = 1 grapheme cluster）にすれば、L1 と L2 が同時に解決する
3. FilterChain での文字数フィルタ等、将来の機能追加にも自然に対応できる

## ファイル構成

- `main.mbt` — 14テスト（Part 1: String UTF-16, Part 2: 破壊パターン, Part 3: kuu combining）
- `DESIGN.md` — 詳細設計・分析
- `docs/decision-records/DR-001-surrogate-pair-issues.md` — Design Record

## 詳細

[DESIGN.md](DESIGN.md) / [DR-001](docs/decision-records/DR-001-surrogate-pair-issues.md)
