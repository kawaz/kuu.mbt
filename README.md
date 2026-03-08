# mydocker — Docker CLI Argument Parsing with kuu (Go)

青山龍星だ！kuuの実力をGoで証明するサンプルだぜ！

## 概要

MoonBit製CLIパーサライブラリ [kuu](https://github.com/kawaz/kuu.mbt) を使って、
Docker CLI のサブコマンド構造を Go から引数パースする実証コード。

### 検証内容

- **10サブコマンド**: run, build, ps, images, pull, push, exec, compose, network, volume
- **ネストしたサブコマンド**: compose (up/down/logs/ps), network (create/ls/rm/inspect), volume (create/ls/rm/inspect)
- **全オプション種**: flag, string, int, count, append_string, positional, rest
- **グローバルオプション**: verbose(-vvv), debug, log-level, host
- **制約**: choices, exclusive, required
- **エラーハンドリング**: 不明オプション、無効な選択肢
- **ヘルプ**: ルート/サブコマンドの --help

### アーキテクチャ

```
Go プロセス (main.go)
  │  JSON スキーマ + 引数
  v
Node.js ブリッジ (kuu_bridge.mjs)
  │  WebAssembly.instantiate + builtins: ["js-string"]
  v
kuu core WASM (wasm-gc)
  │  パース実行
  v
JSON 結果 → Go で検証
```

wazero が wasm-gc 未対応のため Node.js ブリッジ経由 (DR-031 参照)。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `main.go` | エントリポイント、シナリオ実行フレームワーク |
| `schema.go` | Docker CLI の kuu JSON スキーマ定義 |
| `scenarios.go` | 19個のテストシナリオ + バリデーション |
| `bridge.go` | kuu WASM bridge の Go ラッパー (Node.js 経由) |
| `kuu_bridge.mjs` | Node.js WASM ローダー (NDJSON プロトコル) |
| `docker.go` | **デザインモック** — kuu Go API (struct tag) の理想形 |

## 実行方法

```bash
# 1. kuu WASM をビルド
just build-wasm

# 2. 全シナリオ実行
just run

# 3. 特定シナリオのみ
just run-scenario "compose up: detached with files"
```

## 結果

```
--- Results: 19 passed, 0 failed ---
```
