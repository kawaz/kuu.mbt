# cargo-rust example 設計書

CV: 青山龍星

## 概要

kuu の WASM bridge を利用して、Rust で cargo CLI の引数パースを実装する実証コード。
cargo (Rust のパッケージマネージャ) の主要サブコマンドとオプションを忠実に再現し、
kuu の多言語対応ポテンシャルを検証する。

## アーキテクチャ

```
Rust (cargo_schema) → JSON schema
         ↓
    Node.js subprocess
         ↓
    kuu WASM bridge (wasm-gc + js-string builtins)
         ↓
    JSON result → Rust (serde parse)
```

Python 版 (20260309-cargo-python) と同じ Node.js サブプロセス方式。
wasm-gc + js-string builtins は V8 依存のため、wasmtime からは直接呼び出せない。

## Python 版との差別化

| 観点 | Python 版 | Rust 版 (本実装) |
|------|-----------|-----------------|
| スキーマ定義 | 辞書リテラル (型なし) | 型安全ビルダーパターン |
| 結果パース | dataclass | serde derive |
| エラー処理 | 例外 | Result + thiserror |
| cargo 機能カバレッジ | 14 サブコマンド (基本) | 9 サブコマンド (深掘り) |
| kuu 機能カバレッジ | 基本コンビネータ + choices | exclusive/deprecated/variation/requires/env/implicit_value |

## 実装するサブコマンド

kuu 機能のショーケースを最大化するため、サブコマンドの数より各コマンドの「深さ」を重視する。

### 1. build / b
- **kuu 機能**: sub (aliases), global options, append_string, flag, int_opt, string_opt (choices), hidden
- **注目**: `--all` は `--workspace` のエイリアスとして hidden + description "(deprecated)" で表現
- **オプション**: --release/-r, --jobs/-j, --target, --features/-F, --all-features, --no-default-features,
  --package/-p, --workspace, --all (deprecated), --message-format (choices), --profile

### 2. run / r
- **kuu 機能**: dashdash, positional (optional), exclusive
- **注目**: `-- [ARGS]...` でバイナリへの引数を渡す
- **オプション**: --release/-r, --bin, --example, --package/-p, --features/-F + dashdash

### 3. test / t
- **kuu 機能**: positional (TESTNAME), dashdash, flag (--no-run, --no-fail-fast)
- **注目**: positional と dashdash の組み合わせ
- **オプション**: --no-run, --no-fail-fast, --doc, --release + positional TESTNAME + dashdash

### 4. new
- **kuu 機能**: positional (required), exclusive (--bin vs --lib), choices (--vcs, --edition), required
- **注目**: 必須 positional + 排他制約
- **オプション**: PATH (required positional), --bin, --lib, --edition (choices), --vcs (choices), --name

### 5. add
- **kuu 機能**: rest (複数 positional), exclusive (source group, section group), flag (--no-default-features, --no-optional)
- **注目**: ソース排他グループ (--path vs --git vs --registry)
- **オプション**: DEP... (rest), --path, --git, --branch, --tag, --rev, --dev, --build,
  --features/-F, --no-default-features, --default-features, --optional, --no-optional, --rename, --dry-run/-n

### 6. remove / rm
- **kuu 機能**: sub (aliases), rest, exclusive (section group)
- **オプション**: DEP_ID... (rest), --dev, --build, --package/-p, --dry-run/-n

### 7. clean
- **kuu 機能**: シンプルなサブコマンド、flag
- **オプション**: --doc, --release/-r, --profile, --target, --target-dir, --dry-run/-n

### 8. check / c
- **kuu 機能**: build と共通オプションの再利用パターン
- **オプション**: build と同等 (--all-targets 追加)

### 9. doc / d
- **kuu 機能**: flag (--no-deps, --open, --document-private-items)
- **オプション**: --open, --no-deps, --document-private-items, --release, --features/-F

## グローバルオプション

| オプション | kuu 型 | 特記 |
|-----------|--------|------|
| --verbose / -v | count (global) | -vv で very verbose |
| --quiet / -q | flag (global) | verbose と exclusive |
| --color | string (global) | choices + implicit_value |
| --locked | flag (global) | |
| --offline | flag (global) | |
| --frozen | flag (global) | --locked + --offline を暗示 |
| --config | append_string (global) | KEY=VALUE 形式 |
| --manifest-path | string (global) | |
| --explain | string (top-level only) | |
| --list | flag (top-level only) | |

## kuu 機能カバレッジマップ

| kuu 機能 | 使用箇所 |
|----------|---------|
| flag | 全サブコマンド |
| count | verbose (-vvv) |
| string_opt | color, target, profile, manifest-path |
| int_opt | jobs |
| append_string | features, config |
| positional | new (PATH), test (TESTNAME) |
| rest | add (DEP...), remove (DEP_ID...) |
| dashdash | run, test |
| sub + aliases | build/b, run/r, test/t, check/c, doc/d, remove/rm |
| global | verbose, quiet, color, locked, offline, frozen, config, manifest-path |
| choices | color, edition, vcs, message-format |
| implicit_value | color (--color → "always") |
| exclusive | bin/lib, verbose/quiet, source group, section group |
| hidden | unstable options (-Z) |
| required | new の PATH positional |

> **Note**: test/doc/add の `--no-run`, `--no-fail-fast`, `--no-deps`, `--no-default-features`, `--no-optional` は
> plain flag として実装している。cargo の `--no-run` に対応する `--run` は存在しないため
> `variation_false` は不適切であり、独立した flag が正しいモデリングとなる。

### WASM bridge 未対応のため除外 (DR-001)

| kuu core 機能 | 状況 |
|---------------|------|
| deprecated | bridge 未対応。`hidden` + description で "(deprecated)" と明記 |
| requires | bridge 未対応。description で依存関係を案内 |
| env | bridge 未対応。`.env()` はビルダーに残す（将来の bridge 拡張時に自動有効化） |
| require_cmd | トップレベルでは使用しない（--explain/--list との矛盾、DR-001 参照） |

## ファイル構成

```
examples/20260318-cargo-rust/
  Cargo.toml              # Rust プロジェクト設定
  justfile                # タスクランナー
  README.md               # プロジェクトドキュメント
  src/
    main.rs               # エントリポイント + 結果表示
    schema.rs             # cargo CLI スキーマ定義 (型安全ビルダー)
    bridge.rs             # kuu WASM bridge 呼び出し
    bridge.mjs            # Node.js WASM ブリッジスクリプト
  tests/
    integration_test.rs   # 統合テスト
  docs/
    DESIGN.md             # 本ファイル
    decision-records/
```

## 依存クレート

- `serde` + `serde_json`: JSON (de)serialization
- `thiserror`: エラー型定義

dev 依存:
- (なし — 標準の `#[test]` を使用)

## ビルド・実行

```bash
# 前提: kuu WASM をビルド済み (リポジトリルートで moon build --target wasm-gc --release)
just build-wasm   # WASM ビルド
just build        # Rust ビルド
just run -- build --release --features serde -j4
just test         # 統合テスト
just demo         # デモ実行
```
