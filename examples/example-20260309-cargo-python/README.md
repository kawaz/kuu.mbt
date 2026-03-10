# mycargo — cargo CLI 引数パーサデモ (Python + kuu WASM bridge)

kuu は MoonBit で書かれた CLI 引数パーサライブラリ。WASM にコンパイルすることで言語を問わず同じパース定義を使い回せる。

kuu の WASM bridge を使って、Python から cargo CLI の引数パーサを実装するデモプロジェクトなのだ！

## 概要

- **APP**: cargo (Rust ビルドツール)
- **言語**: Python (kuu WASM bridge 経由)
- **チャレンジ**: 14サブコマンド + 7グローバルオプションの大規模CLI
- **CV**: ずんだもん

## 目的

- kuu の WASM bridge が Python からも正しく動作することを実証するのだ
- 14個のサブコマンド（build, test, run, bench, check, clippy, fmt, doc, new, init, publish, install, clean, update）のパースを検証
- Node.js サブプロセスブリッジパターンの実証（wasm-gc は V8 依存のため）

## アーキテクチャ

```
Python (main.py) ── JSON ──► Node.js (kuu_bridge.mjs) ──► WASM (kuu_parse)
       ▲                                                        │
       └──────────────── JSON result ◄──────────────────────────┘
```

## 前提条件

- Python 3.11+
- Node.js v25+
- [uv](https://docs.astral.sh/uv/) — Python パッケージマネージャ。依存管理と実行に使用
- [just](https://just.systems/) — タスクランナー。`justfile` に定義されたビルド・テストコマンドを実行する
- [moon](https://www.moonbitlang.com/) — MoonBit のビルドツール。kuu WASM モジュールのビルドに必要
- kuu WASM モジュール (`just build-wasm` でビルド)

## ビルド・実行

```bash
just              # コマンド一覧
just build-wasm   # WASM モジュールビルド
just run          # サンプル実行
just test         # テスト実行
just demo         # 複数コマンドのデモ実行
just help         # ヘルプ表示
```

## 使用例

```bash
# build: リリースビルド
just run build --release --target x86_64-unknown-linux-gnu --jobs 4

# test: テスト名指定 + テストランナー引数
just run test my_test --release -- --nocapture

# run: バイナリ実行 + 引数渡し
just run run --bin myapp -- arg1 arg2

# new: プロジェクト作成
just run new myproject --lib --edition 2021

# グローバルオプション
just run -vv --color always build --release
```

## 発見された kuu の制限事項

- [DR-001](docs/decision-records/DR-001-python-wasm-bridge-strategy.md): wasm-gc + js-string builtins は V8 依存 → Node.js サブプロセスブリッジで解決
- [DR-002](docs/decision-records/DR-002-command-aliases-limitation.md): WASM bridge でコマンドエイリアス未対応
