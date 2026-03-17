# DR-001: WASM bridge の機能ギャップと対応方針

CV: 青山龍星

## 問題

設計で `deprecated` / `requires` / `env` を主要デモ機能として計画していたが、
現行 WASM bridge (`src/wasm/main.mbt`) はこれらに対応していない。

### 詳細

| kuu core 機能 | WASM bridge 対応 | 備考 |
|---------------|-----------------|------|
| `deprecated()` | 未対応 | パーサレベル操作で JSON スキーマの opt kind として表現不可 |
| `requires()` | 未対応 | 制約処理は `exclusive` / `required` / `require_cmd` のみ |
| `env~` | 未対応 | `parser.parse(args)` に `env~` パラメータが渡されていない |
| `at_least_one()` | 未対応 | 同上 |

### 発見経緯

codex レビューで指摘。WASM bridge のコード (`src/wasm/main.mbt:582-630`, `:745`) と
設計書のカバレッジマップを突き合わせて判明。

## 解決策

スコープを縮小し、WASM bridge が対応済みの機能に絞る。

1. **`deprecated`**: `hidden` フラグ + ヘルプ文字列で "(deprecated)" と明記する方式に変更
2. **`requires`**: スキーマから削除。ヘルプ文字列で依存関係を案内するのみ
3. **`env`**: スキーマビルダーに `.env()` メソッドは残す（将来の bridge 拡張時にそのまま使える）が、
   現時点では bridge が無視するため、デモとしては機能しないことをドキュメントに明記
4. **`at_least_one`**: スコープ外

## 選択理由

- bridge を拡張する選択肢もあるが、example の目的は kuu のポテンシャル検証であり、
  bridge 拡張は別の作業スコープ
- 既存の bridge 機能だけでも十分なデモ価値がある
  (sub + aliases, global, count, choices + implicit_value, exclusive, variation, positional, rest, dashdash, hidden)
- `env` の `.env()` メソッドを残すことで、bridge 拡張後に自動的に動作するようになる

## もう1つの問題: require_cmd 矛盾

設計書で `require_cmd` をトップレベルに設定しつつ、`--explain` / `--list` を
トップレベル専用オプションとしていた。これは矛盾する（サブコマンドなしの実行が不可能になる）。

**対応**: `require_cmd` をトップレベルから削除。実際の cargo もサブコマンドなしで
`--help`, `--version`, `--list`, `--explain CODE` が動作する。
