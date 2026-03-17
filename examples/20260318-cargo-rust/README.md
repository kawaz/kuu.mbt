# cargo-kuu-example — cargo CLI 引数パーサデモ (Rust + kuu WASM bridge)

CV: 青山龍星

kuu の WASM bridge を使って、Rust から cargo CLI の引数パーサを実装するデモプロジェクト。

## アーキテクチャ

```
Rust (schema.rs) → JSON schema + args
        ↓
   Node.js subprocess (bridge.mjs)
        ↓
   kuu WASM (wasm-gc + js-string builtins)
        ↓
   JSON result → Rust (serde parse)
```

## 前提条件

- Rust (cargo)
- Node.js v25+ (js-string builtins サポート)
- MoonBit (moon CLI)
- just (タスクランナー)

## ビルド・実行

```bash
# WASM ビルド + テスト (初回)
just

# cargo サブコマンドの実行例
just run build --release --features serde -j 4
just run test integration --no-fail-fast -- --nocapture
just run new my-project --lib --edition 2024

# デモシナリオ実行
just demo

# テスト
just test
```

## 使用している kuu 機能

| 機能 | 使用箇所 |
|------|---------|
| sub + aliases | build/b, run/r, test/t, check/c, doc/d, remove/rm |
| flag (global) | verbose, quiet, locked, offline, frozen |
| count | verbose (-vvv) |
| string_opt + choices | color (auto/always/never), edition, vcs, message-format |
| implicit_value | --color → "always" |
| int_opt | jobs |
| append_string (global) | config, features |
| positional | new (PATH), test (TESTNAME) |
| rest | add (DEP...), remove (DEP_ID...) |
| dashdash | run, test |
| exclusive | --bin/--lib, --verbose/--quiet, source group (--path/--git/--registry) |
| required | new の PATH |
| hidden | unstable options (-Z) |

## サブコマンド構成

```
cargo
  ├── build (b)     # ビルド — compilation/feature/package/target selection opts
  ├── run (r)       # 実行 — dashdash で引数透過
  ├── test (t)      # テスト — TESTNAME positional + dashdash
  ├── check (c)     # 型チェック — build と同等
  ├── new           # 新規作成 — required PATH, exclusive --bin/--lib, choices
  ├── add           # 依存追加 — rest DEP, exclusive source/section groups
  ├── remove (rm)   # 依存削除 — rest DEP_ID
  ├── clean         # クリーン — シンプル
  └── doc (d)       # ドキュメント — --open, --no-deps
```

## テスト

33 件の統合テスト:
- 各サブコマンドの基本動作
- コマンドエイリアス (b, r, t, c, d, rm)
- choices バリデーション (valid/invalid)
- exclusive 制約 (--bin/--lib, --verbose/--quiet, source group)
- required 制約 (new の PATH)
- dashdash 透過引数
- グローバルオプション伝搬
- ヘルプ表示
- エラーケース (unknown option/subcommand)

## Python 版との違い

| 項目 | Python (20260309) | Rust (本実装) |
|------|-------------------|--------------|
| スキーマ定義 | 辞書リテラル | 型安全ビルダーパターン |
| 結果パース | dataclass | serde derive |
| エラー処理 | 例外 | Result + thiserror |
| テスト | pytest 35件 | cargo test 33件 |
| kuu 機能 | 基本 | choices/implicit_value/exclusive/hidden 追加 |

## 発見された制限事項

- DR-001: WASM bridge が `deprecated` / `requires` / `env` 未対応
