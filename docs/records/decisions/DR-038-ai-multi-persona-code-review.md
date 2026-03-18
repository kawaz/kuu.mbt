---
type: review
---

# DR-038: 多角的コードレビュー（5ペルソナ）の知見

日付: 2026-03-10
ステータス: **記録**

## 概要

MoonBit コアライブラリ（`~/.moon/lib/core`）の調査を踏まえ、src/core/ と src/wasm/ を5つの観点で並列レビューした結果をまとめる。

## レビュー観点と主要指摘

### 1. MoonBit イディオム

| 指摘 | 現状 | 改善案 |
|------|------|--------|
| `to_upper` 手動実装 | `to_lower()` は標準利用なのに `to_upper` だけ自前 | `String::to_upper()` に統一 |
| `one_of` バリデーション | 手書きループ | `Array.contains` + `Array.join` |
| ループパターン | 手書き for + push | `Array.filter/map/fold` 活用 |
| Option 処理 | match 式の嵐 | `Option.map/unwrap_or` |

### 2. コード品質

| 指摘 | 箇所 | 影響 |
|------|------|------|
| variation sugar 6箇所重複 | options.mbt | 各 opt 種別で同じ variation_false/toggle/true/reset/unset パターン |
| `install_short_combine_node` 155行 | nodes.mbt | 巨大関数。責務分割推奨 |
| 最長一致ロジック重複 | parse.mbt | 類似パターンの抽出可能性 |

### 3. アーキテクチャ整合性（DESIGN.md vs 実装）

| 項目 | DESIGN.md | 実装 | 対応 |
|------|-----------|------|------|
| `at_least_one` | 実装済み | **未実装** | DESIGN.md を修正 |
| `alias` | 未実装 | **実装済み** | DESIGN.md を更新 |
| OC/P 2フェーズ | 未記載 | DR-034 で決定 | DESIGN.md に反映 |
| cmd 戻り値 | `Opt[Bool]` 記述残存 | `Opt[CmdResult]` | DESIGN.md を修正 |

### 4. WASM/FFI

| 優先度 | 指摘 | 箇所 |
|--------|------|------|
| Critical | `kuu_parse` でパニック → WASM trap | main.mbt:678 |
| High | exclusive/required の未知 opt 名を静かに無視 | main.mbt:602, 624 |
| High | DR-036 の `KuuErrorKind` に対応する `error_code` 未実装 | bridge 全体 |
| Medium | test.mjs エッジケース不足 | ネスト cmd, append_int, 不正 JSON |
| Medium | JSON リテラル構文の未活用 | make_error_json 等 |

#### パニック防御の推奨実装

```moonbit
pub fn kuu_parse(input : String) -> String {
  let result : Result[String, _] = try? kuu_parse_inner(input)
  match result {
    Ok(s) => s
    Err(e) => make_error_json("internal error: " + e.to_string(), "")
  }
}
```

### 5. ディレクトリ構成

**結論: 現在のフラット構成を維持**

根拠:
- MoonBit 標準の `argparse` が 22ファイルを単一パッケージで管理（先例）
- kuu の14ファイルは問題ない規模
- types.mbt への一方向依存で循環なし
- パッケージ分割は循環依存リスク大、メリット < デメリット
- 分割検討タイミング: ファイル数 25+、循環依存発生、help 等の独立ライブラリ化時

## アクション優先度

### Immediate（次の実装セッションで）

1. DESIGN.md の乖離修正（at_least_one, alias, OC/P, cmd 戻り値）
2. `kuu_parse` のパニック防御（try? で囲む）

### Short-term

3. exclusive/required の未知 opt 名検出
4. `to_upper` の標準ライブラリ化
5. variation sugar の重複解消

### Medium-term

6. `install_short_combine_node` の分割
7. test.mjs のエッジケース追加
8. bridge の `error_code` フィールド追加

## 関連 DR

- DR-034: OC/P 2フェーズ分離
- DR-035: WASM bridge 全機能対応
- DR-036: KuuCore 4層アーキテクチャ
- DR-037: 3直交プリミティブ設計
