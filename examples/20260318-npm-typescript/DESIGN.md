# npm CLI Mock — DESIGN

kuu WASM bridge を使った npm CLI 引数パースの検証プロジェクト。

## アーキテクチャ

```
process.argv
    ↓
main.ts (エントリポイント)
    ↓
schema.ts (npm CLI スキーマ定義)
    ↓ JSON schema + args
kuu-bridge.ts (WASM ロード + パース)
    ↓ kuu_parse(JSON) → JSON
結果表示 / エラー表示
```

## レイヤー構成

### kuu-bridge.ts — WASM ラッパー

- WASM モジュールのロード（WASM-GC, js-string builtins）
- `kuu_parse` の型付きラッパー
- スキーマとargsを分離した API: `parse(schema, args) → Result`

### schema.ts — npm CLI スキーマ

- npm の 6 コマンド + グローバルオプションを JSON スキーマとして定義
- kuu WASM bridge の JSON フォーマットに準拠

### main.ts — エントリポイント

- `process.argv.slice(2)` からパース
- 成功時: パース結果を整形表示
- ヘルプ要求時: ヘルプテキスト表示
- エラー時: エラーメッセージ + ヘルプ表示

## 対象コマンド

1. **install** (i, add) — パッケージインストール
2. **run** (run-script) — スクリプト実行
3. **publish** — パッケージ公開
4. **audit** (fix, signatures) — セキュリティ監査
5. **config** (set, get, delete, list) — 設定管理
6. **version** — バージョン操作

## テスト方針

- 各コマンドごとにテストファイルを分離
- TDD: テストを先に書き、スキーマ定義を後から実装
- kuu_parse の JSON API を直接テスト（結果の values/command を検証）
