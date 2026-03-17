# 20260318-terraform-go 設計書

## 概要

kuu WASM bridge を使って Terraform CLI の引数パースを Go で実装するデモプログラム。
20260309-mydocker-go の後継として、より複雑な CLI パターンを検証する。

## 前提

- kuu WASM bridge は DR-035 で全機能拡張済み（exclusive, required, implicit_value 等）
- Go からは Node.js ブリッジ経由で WASM を呼び出す（DR-032: wasm-gc が wazero 未対応のため）
- 20260309-mydocker-go のアーキテクチャを踏襲・改善

## 設計上の決定事項

### 1. オプションプレフィックス: `--`（ダブルダッシュ）を使用

Terraform は `-var`, `-chdir` 等すべて単一ダッシュを使用するが、本デモでは kuu 標準の `--` を使用。

**理由**: kuu の shorts 結合パース（`-abc` → `-a -b -c`）と単一ダッシュ多文字オプションは衝突する。
根本対応には kuu コア側の変更が必要であり、本デモのスコープ外。
パース能力の検証が目的であり、プレフィックスの差異は本質的でない。

### 2. `destroy` コマンド: 独立コマンドとして定義

Terraform の `destroy` は内部的に `apply -destroy` 相当だが、kuu の command alias は
「名前の別名」であり `-destroy` フラグの自動注入はできない。

**対応**: `destroy` を独立コマンドとして定義し、apply と同じオプション群を共有。
Go 側の Validate で `destroy` コマンド選択 = destroy モードとして検証。

### 3. 値レベルの排他制約: Go 側で検証

`--refresh=false` と `--refresh-only` の矛盾のような値レベルの排他は、
kuu の exclusive モデル（オプション名の排他）では直接表現できない。
Go 側のバリデーションロジックで検証し、知見として DR に記録。

## mydocker-go からの改善点

### 1. ファイル配置のフラット化

mydocker-go は `src/` 内に Go ファイルを配置していたが、Go の慣習に従いプロジェクトルート直下に配置。

### 2. WASM bridge の新機能活用

mydocker-go では未サポートだった以下の機能を活用:
- `exclusive` 制約（`--reconfigure` vs `--migrate-state` 等）
- `implicit_value`（`--lock=false` パターン）

### 3. テストシナリオの構造化

mydocker-go の 19 シナリオに対し、Terraform の複雑さに合わせて 28 シナリオ。

## Terraform CLI の特殊パターンと kuu での表現

### `--var 'key=value'` パターン

Terraform の `-var` はスペース区切りで値を取り、値自体に `=` を含む。
kuu の `append_string` で自然に表現可能:

```json
{"kind": "append_string", "name": "var"}
```

`--var 'region=us-east-1' --var 'env=prod'` → `["region=us-east-1", "env=prod"]`

### `--lock=false` パターン（デフォルト true の bool 反転）

kuu の `string` + `implicit_value` で表現:

```json
{"kind": "string", "name": "lock", "default": "true", "implicit_value": "true"}
```

`--lock` → `"true"`, `--lock=false` → `"false"`, 省略時 → `"true"`

### `destroy` コマンド

独立コマンドとして定義。apply と同じオプション群を共有:

```json
{"kind": "command", "name": "destroy", "opts": [...applyCommonOpts]}
```

### 2階層サブコマンド

```json
{"kind": "command", "name": "workspace", "opts": [
  {"kind": "command", "name": "new", "opts": [
    {"kind": "positional", "name": "name"},
    {"kind": "string", "name": "state"}
  ]},
  {"kind": "command", "name": "list"},
  {"kind": "command", "name": "show"},
  {"kind": "command", "name": "select", "opts": [
    {"kind": "positional", "name": "name"}
  ]},
  {"kind": "command", "name": "delete", "opts": [
    {"kind": "positional", "name": "name"},
    {"kind": "flag", "name": "force"}
  ]}
]}
```

## テストシナリオカテゴリ

1. **plan 基本**: `--var`, `--target`, `--out` の組み合わせ
2. **plan 排他**: `--destroy` と `--replace` の排他
3. **apply 基本**: plan file (positional), `--auto-approve`
4. **destroy**: 独立コマンドとしての destroy
5. **init 基本**: `--upgrade`, `--backend-config` 繰り返し
6. **init 排他**: `--reconfigure` vs `--migrate-state`
7. **fmt 基本**: 複数 positional, `--check`, `--diff`
8. **fmt bool反転**: `--list=false`, `--write=false`
9. **workspace 2階層**: new, list, show, select, delete
10. **state 2階層**: mv, list, show, rm
11. **output 基本**: optional positional, `--json` vs `--raw` 排他
12. **グローバル**: `--chdir=DIR`
13. **ヘルプ**: 各サブコマンドの `--help`
14. **エラー**: 不正オプション、制約違反
