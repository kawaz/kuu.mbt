# 20260318-terraform-go

Terraform CLI の引数パースを kuu WASM bridge + Go で実装するデモ。

## 目的

- kuu の WASM bridge が複雑な CLI（2階層サブコマンド、排他制約、繰り返しオプション等）をパースできることを実証
- Go から kuu を利用するパターン（Node.js ブリッジ方式）の検証
- Terraform 固有の CLI パターン（`-var 'key=value'`、`-lock=false` 等）への対応確認

## 検証対象サブコマンド

| # | コマンド | 検証ポイント |
|---|---------|-------------|
| 1 | `plan` | 繰り返し可能オプション（`-var`, `-target`, `-replace`）、bool反転（`-lock=false`）、排他制約 |
| 2 | `apply` | positional arg (plan file)、`-auto-approve`、plan と共通オプション |
| 3 | `init` | `-backend-config` 繰り返し、`-reconfigure` vs `-migrate-state` 排他 |
| 4 | `fmt` | 複数 positional args、デフォルト true の bool 反転（`-list=false`） |
| 5 | `workspace` | 2階層サブコマンド（new/select/delete/list/show） |
| 6 | `state` | 2階層サブコマンド + 複数 positional args（mv SOURCE DEST） |
| 7 | `output` | optional positional arg、`-json` vs `-raw` 排他 |

## 特に検証する CLI パターン

1. **繰り返しオプション**: `-var 'region=us-east-1' -var 'env=prod'`
2. **bool `=false` 反転**: `-lock=false`, `-input=false`（デフォルト true）
3. **排他制約**: `-destroy` vs `-replace`、`-reconfigure` vs `-migrate-state`
4. **2階層サブコマンド + positional**: `workspace new NAME`, `state mv SRC DEST`
5. **コマンドエイリアス**: `destroy` = `apply -destroy` 相当
6. **グローバルオプション**: `-chdir=DIR`（全サブコマンド共通）

## アーキテクチャ

```
Go プロセス (main.go)
  ↓ JSON schema + args (NDJSON)
Node.js ブリッジ (kuu_bridge.mjs)
  ↓ WebAssembly.instantiate + builtins: ["js-string"]
kuu core WASM (wasm-gc format)
  ↓ kuu_parse(schema_json) → result_json
Go プロセス (bridge.go)
  ↓ JSON パース + バリデーション
テスト結果表示
```

## 実行方法

```bash
# 全シナリオ実行
just run

# 特定シナリオのみ
just run-scenario "plan: basic with var and target"

# WASM のみビルド
just build-wasm
```

## ファイル構成

```
examples/20260318-terraform-go/
  README.md           # 本ファイル
  DESIGN.md           # 設計書
  justfile            # タスクランナー
  go.mod              # Go module 定義
  bridge.go           # kuu WASM bridge Go ラッパー
  schema.go           # Terraform CLI スキーマ定義
  scenarios.go        # テストシナリオ + バリデーション
  main.go             # エントリポイント
  kuu_bridge.mjs      # Node.js WASM ローダー
  docs/
    decision-records/ # 設計判断記録
```
