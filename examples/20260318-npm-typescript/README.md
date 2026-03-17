# npm CLI Mock — kuu WASM bridge example

kuu の WASM bridge を使って npm CLI の引数パースを TypeScript で実装した検証プロジェクト。

## 前提条件

- Node.js v22+（WASM-GC + js-string builtins 対応）
- kuu WASM ビルド済み（`just build-wasm` をリポジトリルートで実行）

## セットアップ

```bash
just setup    # 依存インストール
just build    # kuu WASM ビルド
```

## 使い方

```bash
just run -- install express --save-dev
just run -- run test -- --coverage
just run -- publish --access public --dry-run
just run -- audit fix --audit-level high
just run -- config set registry https://registry.npmjs.org
just run -- version patch --preid beta
```

## テスト

```bash
just test           # 全テスト実行
just test-watch     # ウォッチモード
```

## 対象コマンド

| コマンド | エイリアス | kuu 機能デモ |
|----------|-----------|-------------|
| install | i, add | exclusive save flags, append_string, rest |
| run | run-script | dashdash, positional |
| publish | — | choices, flag |
| audit | — | nested commands (fix, signatures) |
| config | c | nested commands (set, get, delete, list) |
| version | — | positional choices, flag variations |
