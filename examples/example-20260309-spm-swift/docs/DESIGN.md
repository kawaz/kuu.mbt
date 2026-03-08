# SPM CLI Parser — Design Document

## 概要

Swift Package Manager (SPM) CLI の引数パースを kuu WASM bridge 経由で Swift から実行するデモ。
kuu の多言語 DX 戦略 (DR-027) を Swift で実証する最初の例。

## アーキテクチャ

```
Swift (main.swift)
  │
  ├── SPMSchema.swift   — SPM CLI 定義を JSON スキーマとして構築
  │
  └── KuuBridge.swift   — bun subprocess 経由で kuu WASM を呼び出し
        │
        └── bridge.mjs  — kuu.wasm をロードし stdin→kuu_parse→stdout
              │
              └── kuu.wasm (96KB, wasm-gc + js-string-builtins)
```

### データフロー

1. Swift が SPM CLI スキーマ（JSON dict）+ CLI args を構築
2. JSON を bun の stdin に送信
3. bridge.mjs が kuu.wasm の `kuu_parse()` を呼び出し
4. パース結果 JSON を stdout に返却
5. Swift が結果を `ParseResult` / `CommandResult` にデコード
6. サブコマンドに応じて結果を表示

## SPM CLI 構造

### グローバルオプション (13個)

| オプション | 種別 | 説明 |
|---|---|---|
| `--verbose` / `-v` | flag | 情報出力を増やす |
| `--very-verbose` / `--vv` | flag | デバッグ出力を含める |
| `--quiet` / `-q` | flag | エラー出力のみ |
| `--configuration` / `-c` | string (choices) | debug / release |
| `--package-path` | string | パッケージパス |
| `--scratch-path` | string | ビルドディレクトリ |
| `--cache-path` | string | キャッシュパス |
| `--arch` | string | アーキテクチャ |
| `--swift-sdk` | string | Swift SDK |
| `--jobs` / `-j` | int | 並列ジョブ数 |
| `--disable-sandbox` | flag | サンドボックス無効化 |
| `--enable-dependency-cache` | flag | 依存キャッシュ有効化 |
| `--enable-build-manifest-caching` | flag | マニフェストキャッシュ |

### サブコマンド

- **build**: `--product`, `--target`, `--show-bin-path`, `--build-tests`, `--build-system`
- **test**: `--filter`, `--skip` (append), `--parallel`, `--num-workers`, `--enable-code-coverage`, `--xunit-output`, `--list-tests`
- **run**: `--skip-build`, `--build-tests`, positional `executable`, rest `arguments`
- **package**: 10個の子サブコマンド（init, update, resolve, show-dependencies, clean, reset, edit, unedit, describe, dump-package, add-dependency, add-target）

## 技術的制約と対応

### WASM bridge の js-string-builtins 依存 (DR-001)

kuu WASM は `use-js-builtin-string: true` でビルドされており、JS ランタイムが必須。
Swift から直接 WASM を実行できないため、bun subprocess をブリッジとして使用。

### dashdash kind 未サポート

WASM bridge は `dashdash` kind を未実装。`rest` kind で代替し、
`swift run my-tool -- --input data.json` のパターンは kuu core の
デフォルト `--` ハンドリングと `rest` の組み合わせで動作確認済み。

### -Xcc 等の単一ダッシュロングオプション

SPM は `-Xcc`, `-Xswiftc` 等の単一ダッシュ+複数文字オプションを使用。
kuu の標準パースでは `--` プレフィックスのロングオプションが前提のため、
本デモではこれらを省略。将来の kuu 拡張で対応可能。

## ファイル構成

```
examples/example-20260309-spm-swift/
├── Package.swift          — Swift Package 定義
├── README.md              — 概要・使い方
├── justfile               — ビルド・テストタスク
├── Sources/
│   ├── main.swift         — エントリポイント、結果表示
│   ├── KuuBridge.swift    — WASM ブリッジ（bun subprocess）
│   └── SPMSchema.swift    — SPM CLI スキーマ定義
├── wasm/
│   ├── kuu.wasm           — kuu WASM モジュール (96KB)
│   └── bridge.mjs         — JS ブリッジスクリプト
└── docs/
    ├── DESIGN.md           — 本文書
    └── decision-records/
        └── DR-001-swift-wasm-bridge-architecture.md
```
