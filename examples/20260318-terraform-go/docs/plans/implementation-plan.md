# 実装計画: 20260318-terraform-go

## 前提

- 20260309-mydocker-go のアーキテクチャを踏襲
- kuu WASM bridge (DR-035) の全機能を活用
- Go + Node.js ブリッジ方式

## codex レビュー指摘への対応

### 1. 単一ダッシュ問題（致命的）

Terraform は `-var`, `-chdir`, `-auto-approve` 等すべて単一ダッシュ。
kuu は `--name` が標準で `-x` は単一文字ショートオプション。

**対応**: 本デモでは kuu 標準の `--` を使用し、Terraform との差異をドキュメントに記載。
理由: 単一ダッシュの多文字オプションは kuu の shorts 結合パース（`-abc` → `-a -b -c`）と衝突するため、
根本対応には kuu コア側の変更が必要（将来の DR 候補）。デモの目的はパース能力の検証であり、
オプションプレフィックスの差異は本質的でない。

### 2. `destroy` コマンドエイリアス（致命的）

command alias は「名前の別名」であり、`-destroy` フラグの自動注入はできない。

**対応**: `destroy` を `apply` とは独立したコマンドとして定義。
apply のオプション群（`-var`, `-target` 等）を共有しつつ、
Go 側の Validate で「destroy コマンドが選択された = destroy モード」として検証。
WASM bridge レベルでは単なる別コマンド。

### 3. `exclusive: [refresh=false, refresh-only]`（致命的）

kuu の exclusive はオプション名の排他であり、値レベルの排他は表現不可。

**対応**: `--refresh` と `--refresh-only` の排他は kuu の exclusive で表現可能
（両方が指定されること自体が矛盾）。`--refresh=false` + `--refresh-only` の
意味的矛盾はGo側のバリデーションで検証し、DR に知見として記録。

### 4. go.mod（軽微）

モジュール名 `example/terraform-go` は Go の慣習通り。配置は examples/ 直下で正しい。

## フェーズ

### Phase 1: インフラ（bridge, justfile, kuu_bridge.mjs）

mydocker-go から bridge.go と kuu_bridge.mjs を移植・改善。

1. `go.mod` 作成（モジュール名: `example/terraform-go`）
2. `kuu_bridge.mjs` を mydocker-go から移植（WASM パス調整: `../../` → kuu リポジトリルート）
3. `bridge.go` を移植（KuuBridge + NDJSON 通信）
4. `justfile` 作成（build-wasm, build-go, run, run-scenario, clean）
5. `.gitignore` 作成（バイナリ除外）

### Phase 2: スキーマ定義（schema.go）

Terraform CLI の 7 サブコマンドを kuu JSON スキーマで表現。

構造:
```
terraform (global: --chdir)
├── plan (--var[], --var-file[], --target[], --replace[], --out, --lock, --lock-timeout, --input, --json, --destroy, --refresh-only, --parallelism, --detailed-exitcode)
│   └── exclusive: [destroy, replace]
├── apply ([plan-file], --auto-approve, + plan共通オプション)
├── destroy (apply と同じオプション群。Go 側で destroy モード扱い)
├── init (--upgrade, --backend-config[], --reconfigure, --migrate-state, --plugin-dir, --lockfile, --from-module)
│   └── exclusive: [reconfigure, migrate-state]
├── fmt ([target...], --list, --write, --diff, --check, --recursive)
├── workspace
│   ├── new (NAME, --state, --lock, --lock-timeout)
│   ├── list
│   ├── show
│   ├── select (NAME)
│   └── delete (NAME, --force, --lock, --lock-timeout)
├── state
│   ├── list (--state, --id)
│   ├── show (ADDRESS, --state)
│   ├── mv (SOURCE, DESTINATION, --state, --state-out, --dry-run, --lock, --lock-timeout)
│   └── rm (ADDRESS..., --state, --dry-run, --lock, --lock-timeout)
└── output ([NAME], --json, --raw, --state, --no-color)
    └── exclusive: [json, raw]
```

**共通オプションの共有**: plan/apply/destroy で共通するオプション群（var, target, replace 等）は
Go の関数で生成し、各コマンドの Opts に追加する。

### Phase 3: テストシナリオ（scenarios.go）

カテゴリ別に 25-30 シナリオ:

**plan (5)**:
1. plan: basic with var and target
2. plan: multiple vars and var-files
3. plan: output to file with lock disabled
4. plan: destroy mode flag
5. plan: refresh-only mode

**apply (3)**:
1. apply: with plan file
2. apply: auto-approve with vars
3. apply: json output mode

**destroy (2)**:
1. destroy: basic (独立コマンドとして)
2. destroy: with target

**init (3)**:
1. init: upgrade with backend config
2. init: reconfigure
3. init: reconfigure + migrate-state (排他違反テスト)

**fmt (3)**:
1. fmt: check mode
2. fmt: multiple targets with diff
3. fmt: list=false write=false

**workspace (4)**:
1. workspace new: with name
2. workspace list
3. workspace select: with name
4. workspace delete: force

**state (3)**:
1. state list: with id filter
2. state mv: source to destination
3. state rm: dry-run

**output (2)**:
1. output: json format
2. output: specific name raw (排他テスト含む)

**global/misc (3)**:
1. chdir: global option
2. help: plan --help
3. error: unknown option

### Phase 4: エントリポイント（main.go）

mydocker-go の main.go を踏襲:
- `--scenario` フィルタ
- カラー出力（PASS/FAIL）
- 集計結果

### Phase 5: 動作確認 + DR 記録

1. `just run` で全シナリオ実行
2. 失敗シナリオの修正
3. DR に発見した課題・知見を記録（特に単一ダッシュ問題）
4. DESIGN.md 更新

## リスク

1. **`--lock=false` パターン**: kuu の `implicit_value` + `string` で表現できるか要検証
2. **排他制約の WASM bridge 対応**: DR-035 で対応済みのはずだが動作確認が必要
3. **kuu_bridge.mjs の WASM パス**: ワークスペース配置からの相対パス解決が正しいか要確認
4. **単一ダッシュ長オプション**: 将来 kuu コアで対応が必要な機能として DR に記録
