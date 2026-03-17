# DR-051: 20260318 Example レビュー知見 — kuu API 課題と進化の記録

## 背景

20260318 に5本の example を作成:

- npm-typescript (WASM bridge / TypeScript)
- cargo-rust (WASM bridge / Rust)
- terraform-go (WASM bridge / Go)
- brew-swift (WASM bridge / Swift)
- tar (MoonBit 直接)

MoonBit 直接（tar）と WASM bridge 経由（他4言語: TS/Rust/Go/Swift）での kuu core API の書き味を検証。過去 example（20260308-09）との比較も実施した。

## 課題

### A: WASM bridge の機能ギャップ（深刻度: 高）

WASM bridge 経由の4言語で以下の機能が使えない:

| 機能 | 状況 | 代替手段 |
|---|---|---|
| `deprecated` | 未対応 | cargo-rust: hidden + description で代替 |
| `requires` | 未対応 | cargo-rust: description で依存案内のみ |
| `env~` | 未対応 | cargo-rust: ビルダーに残して将来対応待ち |
| `at_least_one` | 未対応 | tar（MoonBit直接）のみ使用可 |

tar（MoonBit 直接）では全機能が問題なく動作する。WASM bridge の機能拡張が多言語展開の最大ボトルネックとなっている。

### B: 単一ダッシュ多文字オプション（深刻度: 中）

terraform-go DR-001 で発見。`-var`, `-chdir` のような単一ダッシュ多文字オプションを kuu は扱えない。shorts 結合パース（`-abc` → `-a -b -c`）と衝突するため、構造的に対応が困難。

Terraform / curl 等の「古い Unix 流儀」CLI は模倣不可。kuu のスコープとして対応するかどうかの判断が必要。

### C: 短形式のみのフラグ（深刻度: 低）

brew-swift DR-001 で発見。`-1`, `-l`, `-r`, `-t` のような短形式のみのフラグは、`flag("one-per-line", shorts="1")` のように説明的な長名を付ける必要がある。JSON スキーマでは長名が必須であり、短形式のみの定義はできない。

### D: command alias でのフラグ自動注入不可（深刻度: 低）

terraform-go DR-001 で発見。`destroy` は `apply -destroy` だが、command alias は名前の別名のみで、フラグの自動注入はできない。

独立コマンド + オプション共有で対応。command alias はあくまで「同じコマンドの別名」であり、「別コマンドのショートカット」ではないという kuu の設計思想的に妥当な制限。

### E: 値レベルの排他制約なし（深刻度: 低）

terraform-go DR-001 で発見。`--refresh=false` と `--refresh-only` の矛盾は `exclusive`（名前レベル）では表現不可。値の組み合わせに対する制約は kuu のスコープ外。

アプリケーションロジック側の責務であり、パーサライブラリが担うべき範囲を超えている。妥当なスコープ判断。

## 進化の記録: 過去 example との比較

### command aliases の修正

20260309-cargo-python DR-002 で「動かない」と報告されていた command aliases が、20260318 の全 example で正常動作。DR-037 での alias コンビネータ実装の成果。

### 機能カバレッジの大幅拡大

過去 example（20260308-09）から以下の機能が追加され、利用可能になった:

- exclusive
- variation_false
- aliases
- implicit_value
- choices
- dashdash
- deprecated
- env
- at_least_one

### 設計判断の記録充実

過去の example では「使えない」で終わっていた課題が、20260318 では「理由 + 代替手段 + 将来方針」まで明記されるようになった。各 example の DR に判断根拠が残っている。

### 5言語での実証

過去は Python / TypeScript の2言語だったが、Rust / Go / Swift が追加され、5言語での kuu API 検証が完了。

## 今後のアクション

1. **WASM bridge Phase 2**（deprecated / requires / env / at_least_one 対応）— 多言語展開の最大ボトルネック
2. **短形式のみフラグの JSON スキーマ対応検討** — 長名なしでの定義を許容するか
3. **単一ダッシュ多文字オプションのスコープ判断** — kuu として対応するか、スコープ外とするか
