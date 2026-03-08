# mycargo — 設計ドキュメント

## 概要

kuu WASM bridge を Python から利用し、cargo CLI の引数パースを実証するデモプロジェクト。

## アーキテクチャ

```
                    JSON schema + args
Python (main.py) ──────────────────────► Node.js (kuu_bridge.mjs)
       ▲                                         │
       │                                         ▼
       │ ParseResult                    WASM (kuu_parse)
       │ (dataclass)                             │
       │                                         ▼
       ◄──────────────────────────────── JSON result
                    subprocess
```

### レイヤー構成

| レイヤー | ファイル | 責務 |
|---------|---------|------|
| スキーマ定義 | `cargo_schema.py` | cargo CLI のオプション/サブコマンド構造を JSON スキーマで宣言 |
| WASM ブリッジ | `kuu.py` + `kuu_bridge.mjs` | kuu_parse の呼び出しと結果の型変換 |
| アプリケーション | `main.py` | パース実行と結果の整形表示 |

## 対象サブコマンド

14 個のサブコマンドを実装:

| コマンド | エイリアス | 主な検証ポイント |
|---------|----------|----------------|
| build | b | ビルド共通オプション群、ターゲット選択 |
| test | t | positional (testname) + rest (test-args) の組み合わせ |
| run | r | rest (args) でバイナリ引数を渡す |
| bench | - | positional + rest パターン |
| check | c | build と同じオプション群の再利用 |
| clippy | - | fix フラグ + rest (clippy-args) |
| fmt | - | check/all フラグ + rest (fmt-args) |
| doc | d | open/no-deps フラグ |
| new | - | positional (path) + choices (edition, vcs) |
| init | - | new と類似構造 |
| publish | - | dry-run + token |
| install | - | positional (crate) + version/git/branch |
| clean | - | release + target 指定 |
| update | - | package + precise バージョン指定 |

## グローバルオプション

| オプション | 型 | 検証ポイント |
|----------|---|------------|
| --verbose/-v | count | -vv で2になること |
| --quiet/-q | flag | verbose と共存（WASM bridge レベルでは排他制約なし） |
| --color | string (choices) | auto/always/never の選択肢バリデーション |
| --manifest-path | string | パス文字列 |
| --frozen/--locked/--offline | flag | 複数フラグの組み合わせ |

## 設計判断

- [DR-001](decision-records/DR-001-python-wasm-bridge-strategy.md): Python-WASM ブリッジ戦略
- [DR-002](decision-records/DR-002-command-aliases-limitation.md): WASM bridge のコマンドエイリアス未対応

## 依存関係

- Python 3.11+
- Node.js v25+ (WASM bridge 実行用)
- pytest (テスト実行用)
- kuu WASM モジュール (`just build-wasm` でビルド)
