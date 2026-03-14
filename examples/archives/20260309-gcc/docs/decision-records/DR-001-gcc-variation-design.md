# DR-001: gcc example の Variation 機能デモ設計

## 背景

kuu の Variation 機能（`variation_false`, `variation_toggle`, `variation_true`, `variation_reset`, `variation_unset`）の実用パターンを検証するため、gcc の CLI オプション体系をモデルにしたデモを作成する。

なお、`variation_unset` は gcc のオプション体系に対応する自然なユースケースがないため、本デモでは対象外とする。Unset は「オプションが設定されたこと自体を取り消す」操作であり、gcc の `--no-flag`（値の反転）や `--reset-flag`（デフォルトへの復帰）とは異なる意味を持つ。

## 問題

gcc のオプション体系には `--flag` / `--no-flag` パターンが大量に存在する:

- `-Wall` / `-Wno-all` (警告制御)
- `-fPIC` / `-fno-PIC` (コード生成)
- `-pie` / `-no-pie` (リンカ)

このパターンが kuu の Variation で自然に表現できるかを検証する必要がある。

## 決定

### 1. gcc オプションを `--` プレフィックスにマッピング

**選択理由**: kuu は `--` プレフィックスを標準とするため、gcc の `-` プレフィックスオプションを `--` スタイルに変換。これはパーサの構文制約であり、セマンティクスは保たれる。

### 2. Variation の sugar と explicit の両方を使用

**選択理由**: 同一のデモ内で両形式を示すことで、ユーザーが好みの書き方を選べるようにする。

- 大多数: `variation_false=Some("no")` (sugar、簡潔)
- 2個: `variations=[@core.False("no")]` (explicit、柔軟)

### 3. Toggle のデモに `diagnostics-color` を採用

**選択理由**: gcc の `--diagnostics-color` は「状態のトグル」という概念に適合する。実際の gcc では `--diagnostics-color=auto|always|never` だが、Toggle デモとして簡略化。

### 4. MoonBit 予約語の回避

**問題**: `define` は MoonBit の予約語で変数名に使えない。
**解決**: `defs` / `undefs` にリネーム。オプション名（`name="define"`）はそのまま。

## kuu Variation 機能カバレッジ

| Variation 種別 | デモ数 | 例 |
|---|---|---|
| `False("no")` via sugar | 15 | `--wall`/`--no-wall`, `--debug`/`--no-debug` |
| `False("no")` via explicit | 2 | `--fcommon`/`--no-fcommon` |
| `Toggle("toggle")` | 1 | `--toggle-diagnostics-color` |
| `True("force")` | 1 | `--force-diagnostics-color` |
| `Reset("reset")` | 1 | `--reset-debug` |
| `default=true` + `False` | 3 | `--pie`, `--fexceptions`, `--diagnostics-color` |

## 発見された設計課題

### `get().unwrap()` の嵐

kubectl example と同様、パース後の値取得が `opt.get().unwrap()` の繰り返しになる。
DR-031 で既に指摘済み。将来的に `get_or(default)` 等の折衷案が必要。

### `rest()` + `dashdash()` の同一パーサでの使用不可

**問題**: `rest()` と `dashdash()` を同一パーサで使用すると、`--` が built-in separator node と `dashdash()` のノードの両方にマッチし "ambiguous argument: --" エラーになる。

**発見経緯**: Scenario 2 で linker passthrough (`-- -Wl,--as-needed`) を試みた際に発覚。

**原因**: `parse.mbt` の `install_separator_node()` が positional 引数用の built-in `--` separator を生成する。`dashdash()` も同名のノードを生成するため、`parse_raw()` の最長一致ロジックで同スコアの Accept が2つ返り ambiguous 判定される。

**回避策**: gcc では `-Wl,` プレフィックスでリンカ引数を渡すため `dashdash()` は不要。`rest(stop_before=["--"])` のみ使用。サブコマンド内で `dashdash()` を使う場合（kubectl exec の `--`）は問題ない（サブコマンドの positional と競合しないため）。

### Help に Variation が表示されない

**問題**: `--no-wall`, `--no-fpic`, `--toggle-diagnostics-color` 等の variation で生成されるオプションが `--help` 出力に表示されない。ユーザーはこれらのオプションの存在をヘルプだけでは知ることができない。

**影響度**: 中。README やドキュメントで補完する必要がある。将来的にヘルプにも variation を表示する機能が望ましい。
