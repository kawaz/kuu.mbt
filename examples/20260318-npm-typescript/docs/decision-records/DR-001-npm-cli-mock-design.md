# DR-001: npm CLI mock の設計方針

## 概要

kuu WASM bridge を使って npm CLI の引数パースをモックする TypeScript プロジェクトの設計。

## 目的

1. kuu の WASM bridge が実用的な CLI パースに耐えるか検証
2. TypeScript から kuu を利用する際の DX を体験・評価
3. 問題点や改善ポイントの発見

## 技術選定

### WASM bridge 直接利用

kuu の TypeScript DX レイヤー（pkg/ts/）は DESIGN.md のみで実装なし。
本 example では WASM bridge の JSON API を直接使い、薄い TypeScript ラッパーを自作する。

**理由:**
- DX レイヤー実装を待たずに検証可能
- WASM bridge の JSON API の使い勝手を直接評価できる
- 発見した DX 課題を TS DX レイヤー設計にフィードバックできる

### 対象コマンド（6個）

kuu の各機能を網羅的にデモするため以下を選定:

| コマンド | kuu 機能 | 面白いポイント |
|----------|----------|----------------|
| `install` | exclusive, append_string, aliases, rest | 相互排他 save フラグ群 |
| `run` | dashdash, positional | `-- <args>` のスクリプト引数転送 |
| `publish` | choices, flag, string | access 制限の選択肢 |
| `audit` | nested command, choices, append_string | fix/signatures サブコマンド |
| `config` | nested command, positional, serial | set/get/delete/list 4サブコマンド |
| `version` | positional with choices, flag variation | `--no-commit-hooks` 反転フラグ |

### グローバルオプション

| オプション | 種別 | 備考 |
|------------|------|------|
| `--registry <url>` | string | env: NPM_CONFIG_REGISTRY |
| `--json` | flag | JSON 出力モード |
| `--workspace <name>` / `-w` | append_string | 複数指定可 |
| `--workspaces` | flag | 全ワークスペース |
| `--loglevel <level>` | string + choices | silent〜silly |

### プロジェクト構成

```
examples/20260318-npm-typescript/
├── README.md            # プロジェクト説明
├── DESIGN.md            # 設計ドキュメント
├── docs/decision-records/
├── src/
│   ├── kuu-bridge.ts    # WASM ロード + 型付きラッパー
│   ├── schema.ts        # npm CLI スキーマ定義
│   └── main.ts          # エントリポイント
├── tests/
│   ├── install.test.ts
│   ├── run.test.ts
│   ├── publish.test.ts
│   ├── audit.test.ts
│   ├── config.test.ts
│   └── version.test.ts
├── justfile
├── package.json
├── tsconfig.json
└── vitest.config.ts
```

### ツールチェーン

- **Node.js**: WASM-GC + js-string builtins 対応（v22+）
- **TypeScript**: 型安全なスキーマ定義
- **Vitest**: テストフレームワーク
- **tsx**: TypeScript 直接実行

## 発見・課題

### kuu WASM bridge の能力確認

1. **command 内の exclusive が正常動作**: install の save フラグ群（6個相互排他）が期待通り機能
2. **ネストコマンドの結果構造が明確**: `result.command.command` で audit > fix のような2段ネストを取得可能
3. **variation_false がオプトレベルで機能**: version の `--no-git-tag-version` が正しく `false` を返す
4. **global:true オプションがコマンド前後どちらでも有効**: `--json install` も `install --json` も動作
5. **= 形式のオプション指定が動作**: `--tag=beta` のような形式もパース可能
6. **dashdash 後の引数なしケースも正常**: `npm run test --` で `["--"]` が空配列

### TypeScript DX の課題

1. **WASM-GC の型定義が未整備**: `WebAssembly.instantiate` の第3引数に `@ts-expect-error` が必要
2. **結果の values が `Record<string, unknown>`**: 型安全な値取得には型ガードが必要
3. **positional 未指定時のデフォルトが空文字列**: `""` が返る（null や undefined ではない）
4. **env フィールドはヘルプ表示用のみ**: WASM bridge の JSON API では実際の環境変数値取得は別途 env map を渡す必要がある
