# 20260309-spm-swift

Swift Package Manager (SPM) CLI の引数パースを kuu WASM bridge 経由で Swift から実行するデモ。

## 概要

- **APP**: Swift Package Manager (`swift build/test/run/package`)
- **LANG**: Swift
- **ブリッジ方式**: Swift → bun → kuu WASM (wasm-gc + js-string-builtins)

kuu の多言語 DX 戦略 (DR-027) を Swift で実証する最初の例。

## アーキテクチャ

```
Swift (main.swift) → KuuBridge → bun bridge.mjs → kuu.wasm → JSON result
```

## 対象サブコマンド

| コマンド | 主要オプション |
|---|---|
| `build` | `--product`, `--target`, `--show-bin-path`, `--build-tests` |
| `test` | `--filter`, `--skip`, `--parallel`, `--num-workers`, `--enable-code-coverage` |
| `run` | `--skip-build`, positional executable, `--` passthrough args |
| `package` | `init`, `update`, `resolve`, `show-dependencies`, `clean`, `reset`, `edit`, `unedit`, `add-dependency`, `add-target` |

グローバルオプション: `-v`, `-q`, `-c debug/release`, `--package-path`, `--jobs`, `--disable-sandbox` 等13個。

## 前提条件

- Swift 6.0+
- bun (JS runtime for kuu WASM bridge)

## ビルド・実行

```bash
just            # ビルド + 全テストシナリオ
just build      # ビルドのみ
just test       # テストシナリオ実行
just run ARGS   # 任意の引数で実行
```

### 実行例

```bash
# リリースビルド
swift run spm-swift build --product MyApp -c release -v

# テスト（フィルタ＋並列）
swift run spm-swift test --filter ParserTests --parallel --num-workers 4

# 実行（引数パススルー）
swift run spm-swift run my-tool -- --input data.json --output result.json

# パッケージ初期化
swift run spm-swift package init --type executable --name MyProject

# ヘルプ表示
swift run spm-swift --help
```

## ファイル構成

```
├── Package.swift          — Swift Package 定義
├── justfile               — ビルド・テストタスク
├── Sources/
│   ├── main.swift         — エントリポイント
│   ├── KuuBridge.swift    — bun subprocess ブリッジ
│   └── SPMSchema.swift    — SPM CLI スキーマ (kuu JSON format)
├── wasm/
│   ├── kuu.wasm           — kuu WASM モジュール (96KB)
│   └── bridge.mjs         — JS ブリッジスクリプト
└── docs/
    ├── DESIGN.md
    └── decision-records/
        └── DR-001-swift-wasm-bridge-architecture.md
```

## 技術的知見

- kuu WASM は `use-js-builtin-string: true` で JS ランタイム必須 → bun subprocess で解決
- `dashdash` kind は WASM bridge 未実装 → `rest` で代替可能
- SPM の `-Xcc` 等の単一ダッシュロングオプションは kuu 標準パースでは未対応
- ネストされたサブコマンド (`package init` 等) は kuu の command-in-command で自然に表現可能
