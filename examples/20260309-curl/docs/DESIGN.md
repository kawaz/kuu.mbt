# curl CLI Parser Example — 設計書

## 概要

curl の引数パースを kuu で実装するデモ。
サブコマンドを持たないフラットなオプション構造で、大量の定義を扱う際の kuu の表現力を検証する。

## 検証ポイント

| 検証項目 | curl での具体例 |
|---|---|
| フラットなオプション構造 | サブコマンドなし、40+ オプションが同一レベルに並ぶ |
| 大量の flag/string_opt/int_opt 定義 | 7カテゴリに分類した実用的なオプション群 |
| append_string (リピータブル) | `-H` (header), `-d` (data), `-F` (form) など |
| `--no-xxx` 反転パターン | `variation_false=Some("no")` で `--no-verbose`, `--no-silent` 等を生成 |
| exclusive 制約 | `--silent` vs `--verbose`, `--fail` vs `--fail-with-body` |
| rest (複数ポジショナル) | 末尾の URL を複数受け取る |
| string_opt でのタイムアウト表現 | `--connect-timeout`, `--max-time` は秒数だが小数も許容するため string_opt |

## アーキテクチャ

```
main() → run(args) → Parser::new() → オプション定義 → parse() → 結果表示
```

サブコマンドなし。`run()` が全オプションを定義し、パース結果を表示する。
mygit example と対照的に、フラット構造の CLI を kuu で表現するパターンを示す。

## オプション分類

| カテゴリ | 数 | 主な API |
|---|---|---|
| HTTP Method & Request | 7 | string_opt, append_string |
| Headers & Auth | 5 | append_string, string_opt |
| Output Control | 8 | string_opt, flag |
| Connection & Timeout | 6 | string_opt, int_opt |
| TLS/SSL | 3 | flag, string_opt |
| Proxy | 3 | string_opt |
| Redirect & Cookie | 4 | flag, int_opt, string_opt |
| Misc Flags | 6 | flag |
| **合計** | **42** | |

## 設計判断

### --no-buffer の扱い

curl では `--no-buffer` が主要形式であり、`--buffer` は存在しない。
これを kuu で表現する方法として:

- **採用**: `flag(name="no-buffer")` — シンプルに `--no-buffer` という名前のフラグとして定義
- **不採用**: `flag(name="buffer", default=true, variation_false=Some("no"))` — 意味論的には正しいが、`--buffer` を有効にする使い方が curl に存在しないため過剰

### タイムアウト値の型

`--connect-timeout` と `--max-time` は秒数だが、curl は `1.5` のような小数値も受け付ける。
kuu に float_opt がないため string_opt を使用。実アプリケーションでは post フィルタで float パースを行う想定。
