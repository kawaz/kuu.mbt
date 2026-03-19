# WebAssembly エコシステム総合ガイド

## 全体像 — 何が何なのか

```
                       ┌────────────────────────────────────────┐
                       │     パッケージレジストリ                  │
                       │  wa.dev / OCI / mooncakes.io           │
                       └──────────────┬─────────────────────────┘
                                      │ wkg / warg-cli
                       ┌──────────────▼─────────────────────────┐
                       │     Component Model (Phase 1 提案)      │
                       │  WIT (IDL) + Canonical ABI              │
                       │  「異なる言語間の型安全な相互運用」         │
                       └──────┬─────────────────┬───────────────┘
                              │                 │
                    ┌─────────▼──────┐  ┌───────▼────────┐
                    │ Core Module    │  │ Core Module     │
                    │ (線形メモリ)    │  │ (wasm-gc)       │
                    │ C/Rust/MoonBit │  │ MoonBit/Kotlin  │
                    └─────────┬──────┘  └───────┬────────┘
                              │                 │
                    ┌─────────▼─────────────────▼────────┐
                    │     WASI (システムインターフェース)    │
                    │  ファイル / ネットワーク / HTTP / ...  │
                    │  「ブラウザ外でWASMを動かすためのOS API」│
                    └──────────────┬─────────────────────┘
                                   │
          ┌────────────────────────▼────────────────────────────┐
          │              ランタイム                                │
          │  ブラウザ: V8 / SpiderMonkey / JSC                    │
          │  スタンドアロン: Wasmtime / Wasmer / WasmEdge          │
          │  組込み: wazero (Go) / WAMR (IoT)                    │
          └────────────────────────────────────────────────────┘
```

---

## 1. 仕様 — 「何が何で、何が嬉しいのか」

### 1.1 WebAssembly Core (wasm)

**一言で**: ブラウザで動くポータブルなバイナリ命令セット。

| バージョン | 時期 | 追加された主要機能 |
|-----------|------|-------------------|
| **1.0 (MVP)** | 2017 | 4型(i32/i64/f32/f64)、線形メモリ、関数import/export |
| **2.0** | 2024/12 | SIMD、Bulk Memory、Multi-Value、Reference Types |
| **3.0** | 2025/9 | **GC**、64bit Memory、Multiple Memories、例外処理、Tail Call |

**何が嬉しいか**:
- ネイティブの95%以上の速度でブラウザ上で動く
- サンドボックス実行でセキュア
- どの言語からでもコンパイル可能なユニバーサルターゲット

### 1.2 wasm（線形メモリ） vs wasm-gc — 最重要の区別

| | wasm（線形メモリ） | wasm-gc |
|--|-------------------|---------|
| **メモリモデル** | 型なしバイト配列（malloc/free） | ランタイム管理の struct/array |
| **GC** | 言語が自前GCをwasm内に持ち込む | ホストVM（ブラウザ等）のGCを利用 |
| **向いている言語** | C, C++, Rust（手動メモリ管理） | Kotlin, Dart, MoonBit, Java（GC言語） |
| **バイナリサイズ** | GC実装分が肥大化 | 極めて小さい |
| **Component Model** | 対応済み | **対応作業中（Pre-Proposal）** |
| **WASI** | 対応済み | Component Model経由では未対応 |
| **ブラウザ** | 全ブラウザ対応 | Chrome 119+ / Firefox 120+ / Safari 18.2+ |

**wasm-gc が解決する問題**: GC言語をwasmに移植すると、言語のGC実装ごとwasm内に持ち込むため (1) バイナリが肥大化 (2) ブラウザGCとwasm内GCが二重稼働 (3) JS-wasm間の循環参照を回収不能、という問題があった。wasm-gc はホストVMのGCを直接使うことでこれを解消。

**実サイズ比較**: Fannkuch ベンチマーク — Java(wasm-gc) 2.3KB vs C(線形メモリ) 6.1KB

### 1.3 WASI (WebAssembly System Interface)

**一言で**: wasm をブラウザの外（サーバー、CLI、エッジ）で動かすための OS API 標準。

| バージョン | 時期 | 特徴 |
|-----------|------|------|
| **Preview 1 (0.1)** | 2020 | ファイルI/O、環境変数、CLI引数。ネットワーク非対応 |
| **Preview 2 (0.2)** | 2024/1 | Component Model 上に再構築。HTTP、ソケット追加 |
| **0.3** | 2026前半予定 | ネイティブ async（stream\<T\>, future\<T\>） |
| **1.0** | 2026末〜2027予定 | 長期安定版 |

**何が嬉しいか**:
- **ケーパビリティベースセキュリティ**: プログラムは与えられた権限のみ使用可能。グローバルなファイルアクセス等は不可
- **ポータビリティ**: 同じwasmバイナリがLinux/macOS/Windows/組込みで動作
- **サンドボックス**: デフォルトで何のシステムリソースにもアクセス不可。必要な権限だけ付与

**Preview 1 → 2 の最大の変化**: IDL が WITX → WIT に変わり、Component Model 上に再構築された。ファイルディスクリプタ（整数）→ 偽造不可能な型付きハンドルに。

### 1.4 Component Model

**一言で**: 異なる言語で書いた wasm モジュール同士を型安全につなぐ仕組み。

| 概念 | 説明 |
|------|------|
| **WIT** | インターフェース定義言語。関数シグネチャや型を言語非依存で定義 |
| **Canonical ABI** | コンポーネント間のデータ受け渡しのビットレベル表現の標準 |
| **Component** | WIT で型付けされた Core Module のラッパー。メモリを export しない |
| **World** | コンポーネントの import/export の全体像を定義するスコープ |

**Core Module と Component の違い**:

| | Core Module | Component |
|--|-------------|-----------|
| 型 | i32/i64/f32/f64 のみ | string, list, record, variant, option, result 等 |
| 通信 | 共有線形メモリ経由 | 型付き関数呼び出しのみ |
| メモリ | export 可能 | export **不可** |

**何が嬉しいか**:
- Go で書いたコンポーネントと Rust で書いたコンポーネントが型安全に通信
- npm の wasm 版として、言語を問わずライブラリを共有可能
- 共有メモリのオフセット計算ミスによるバグを構造的に排除

**現状**: Wasmtime で動作可能。ブラウザでは未サポート（jco でトランスパイルが必要）。Phase 1 提案のまま。

### 1.5 wasm-gc と Component Model の関係

**概念的には直交（独立）だが、統合作業が進行中。**

- wasm-gc = 「モジュール内部でデータをどう管理するか」
- Component Model = 「モジュール間でデータをどう受け渡すか」

**現在の制約**: Canonical ABI は線形メモリ前提で設計されており、wasm-gc モジュールをそのまま Component にできない。`gc` canonical option の追加が Pre-Proposal として議論中（[component-model#525](https://github.com/WebAssembly/component-model/issues/525)）。

**kuu への影響**: MoonBit の `--target wasm`（線形メモリ）で Component 化は今すぐ可能。`--target wasm-gc` での Component 化は仕様策定待ち。

### 1.6 JS String Builtins Proposal

**一言で**: wasm-gc 内から JS の String を直接扱う仕組み。

MoonBit の `use-js-builtin-string: true` で有効化。MoonBit の String が JS の String オブジェクトにコンパイルされ、変換コスト・バイナリサイズが激減する。Chrome 131+ でデフォルト有効。

---

## 2. ランタイム — 「どこで動くのか」

### ブラウザ

| エンジン | ブラウザ | wasm-gc |
|----------|---------|---------|
| V8 | Chrome, Edge, Node.js, Deno | Chrome 119+ |
| SpiderMonkey | Firefox | Firefox 120+ |
| JavaScriptCore | Safari | Safari 18.2+ |

### スタンドアロン

| ランタイム | メンテナー | 特徴 | 用途 |
|-----------|-----------|------|------|
| **Wasmtime** | Bytecode Alliance | WASI/Component Model のリファレンス実装。コールドスタート最速（μs） | サーバー、クラウド |
| **Wasmer** | Wasmer Inc. | LLVM/Cranelift/V8 選択可。WASIX（独自POSIX拡張）対応 | 汎用、iOS対応 |
| **WasmEdge** | Second State (CNCF) | AI推論拡張、Docker統合 | エッジ、IoT、AI |
| **wazero** | コミュニティ | 純粋Go実装、CGO不要 | Goアプリへの埋込み |
| **WAMR** | Bytecode Alliance | 超軽量（~64KB Flash）。組込み向け | Arduino, ESP32 |

**選び方**:
- 標準準拠・Component Model → **Wasmtime**
- Go プロジェクトへの埋込み → **wazero**
- 既存UNIXアプリの移植 → **Wasmer** (WASIX)
- エッジ/AI → **WasmEdge**
- マイクロコントローラ → **WAMR**

---

## 3. ツールチェイン — 「何を使って作るのか」

### 3.1 Component Model 関連（Bytecode Alliance）

| ツール | 役割 |
|--------|------|
| **wasm-tools** | wasm バイナリの低レベル操作。`component embed`（WIT埋込み）/ `component new`（Component化）が核心 |
| **wit-bindgen** | WIT → 各言語のバインディング生成。Rust, C, Go, **MoonBit** 等対応 |
| **jco** | JS/TS 向けオールインワン。`transpile`（Component→ESモジュール）/ `componentize`（JS→Component） |
| **cargo-component** | Rust 向け cargo サブコマンド。ビルド+Component化を一体化 |

### 3.2 従来の wasm ツール

| ツール | 役割 |
|--------|------|
| **Emscripten** | C/C++ → wasm+JS。OpenGL/SDL2対応。ゲーム移植に強い。非常に成熟 |
| **WASI SDK** | C/C++ → WASI対応wasm。Emscriptenとの違いはブラウザJS依存なし |
| **wasm-pack** | Rust → wasm → npmパッケージ。wasm-bindgen ベース |
| **Binaryen (wasm-opt)** | wasm バイナリの最適化。サイズ縮小+高速化。wasm-gc にも対応 |
| **wabt** | WAT↔wasmのテキスト/バイナリ変換。仕様準拠検証 |

### 3.3 使い分けフロー

```
MoonBit で Component を作る場合:

  moon build --target wasm
       ↓
  wasm-tools component embed wit/ *.wasm --encoding utf16 -o core.wasm
       ↓
  wasm-tools component new core.wasm -o component.wasm
       ↓
  wkg publish / warg publish  (wa.dev に公開)

JS から使う場合:
  jco transpile component.wasm -o output/  (ESモジュール生成)
```

---

## 4. パッケージレジストリ — 「どこで共有するのか」

| レジストリ | 対象 | プロトコル | メンテナー | 現状 |
|-----------|------|-----------|-----------|------|
| **wa.dev** | WASM Component | Warg → OCI移行中 | Bytecode Alliance | Component Model の公式レジストリ。WIT を理解して型情報表示 |
| **OCI レジストリ** | WASM Component | OCI 1.1 Artifact | Docker Hub, GHCR 等 | 既存インフラを流用。エコシステム標準化が進行中 |
| **wasmer.io** | WASM Module | 独自 | Wasmer Inc. | Wasmer エコシステム内。`wasmer run` で即実行 |
| **mooncakes.io** | MoonBit パッケージ | 独自 | MoonBit チーム | MoonBit ソースコードレベルの共有。WASMではなくソース配布 |

| CLI | 用途 |
|-----|------|
| **wkg** | wa.dev / OCI からの取得・公開。Bytecode Alliance 推奨。Warg と OCI を抽象化 |
| **warg-cli** | Warg プロトコルのリファレンスクライアント。wkg に後継されつつある |

---

## 5. 言語サポート — 「どの言語で書けるのか」

### Component Model 対応状況

| 言語 | ツール | Component出力サイズ例 | 成熟度 |
|------|--------|---------------------|--------|
| **Rust** | cargo-component / wasm32-wasip2 | 100 KB | 最も成熟 |
| **MoonBit** | wit-bindgen moonbit + wasm-tools | **27 KB** | 実験的。サイズ最小 |
| **Go** | TinyGo 0.34+ (wasip2) | — | 本番利用可 |
| **Python** | componentize-py | 17 MB | 実験的（CPython同梱） |
| **JS/TS** | jco componentize | 8.7 MB | 実験的（SpiderMonkey同梱） |
| **C/C++** | WASI SDK + wit-bindgen | — | 安定 |
| **C#** | componentize-dotnet | — | プレビュー |

### wasm-gc 対応言語

| 言語 | 備考 |
|------|------|
| **MoonBit** | wasm-gc ネイティブ設計。LLVM不使用でWAT直接生成 |
| **Kotlin/Wasm** | Kotlin Multiplatform。Compose for Web 対応 |
| **Dart/Flutter** | Flutter 3.24+。起動5-10倍高速化 |
| **Java** | J2Wasm（Google実験的） |
| **OCaml** | wasm_of_ocaml |

---

## 6. MoonBit 固有 — ターゲットの使い分け

| ターゲット | GC | 用途 | Component Model |
|-----------|-----|------|-----------------|
| `wasm-gc` (デフォルト) | ホストVM | ブラウザ向けライブラリ | **非対応**（仕様策定待ち） |
| `wasm` | 参照カウント(自前) | Component化 / WASI / サーバー | **対応** |
| `js` | JSランタイム | Node.js / ブラウザ（wasm非対応環境） | N/A |
| `native` | 参照カウント | CLI ツール | N/A |

### MoonBit + Component Model の手順

```bash
# 1. WIT 定義
# 2. バインディング生成
wit-bindgen moonbit wit/world.wit --out-dir . --derive-eq --derive-show

# 3. stub.mbt に実装を記述

# 4. ビルド（線形メモリ版）
moon build --target wasm

# 5. Component 化（UTF-16 エンコーディング指定が必要）
wasm-tools component embed wit/ target/wasm/release/build/gen/gen.wasm \
  --encoding utf16 -o core.wasm
wasm-tools component new core.wasm -o component.wasm
```

**注意点**:
- MoonBit は内部 **UTF-16**。Component Model は **UTF-8** を期待。`--encoding utf16` 必須
- wit-bindgen の再実行で stub が消えるため、実装は別ディレクトリに保存推奨

### js-builtin-string（wasm-gc + JS文字列最適化）

`moon.pkg.json` で `"use-js-builtin-string": true` を指定すると、MoonBit の String が JS の String に直接コンパイルされる。変換コスト・バイナリサイズが激減（回文判定: 117バイト）。Chrome 131+ 対応。

---

## 7. フレームワーク・統合

| プロジェクト | 何か | 用途 |
|------------|------|------|
| **Spin** (Fermyon) | WASM サーバーレスフレームワーク | `spin new` → `spin build` → `spin up` で即サーバー |
| **wasmCloud** (CNCF) | WASM ネイティブプラットフォーム | Kubernetes/エッジへの分散デプロイ |
| **Extism** (Dylibso) | WASM プラグインシステム | 既存アプリにプラグイン機能を追加 |
| **Docker + WASM** | コンテナ内WASM実行 | `docker run` でWASMを直接実行。サイズ1/10、起動1/10 |

---

## 8. kuu.mbt への示唆

### 現在の kuu WASM bridge

`src/wasm/main.mbt` で `kuu_parse(input: String) -> String` を export。JSON in/out。wasm-gc + js-builtin-string で動作。

### Component Model 化の選択肢

| 方式 | 現実性 | メリット | デメリット |
|------|--------|---------|-----------|
| `--target wasm` で Component 化 | **今すぐ可能** | WIT で型安全API、wa.dev 公開可能 | wasm-gc の恩恵なし（バイナリ大、自前GC） |
| `--target wasm-gc` で Component 化 | 仕様策定待ち | 最小バイナリ、ホストGC | Pre-Proposal 段階 |
| 現状維持（JSON bridge） | 動作中 | シンプル、js-builtin-string 対応 | 型安全でない、言語非依存でない |

### DR-029/DR-030 との関連

- **DR-029（言語境界 serialize 設計）**: Component Model は JSON シリアライズを WIT 型定義で置き換える方向と合致
- **DR-030（opt AST ポータビリティ）**: WIT で opt 定義を表現し、Component として export すれば、JSON export 不要で言語間ポータビリティが実現
- ただし wasm-gc + Component Model の統合完了を待つのが理想的

---

## Sources

仕様群:
- [Wasm 2.0 / 3.0 (webassembly.org)](https://webassembly.org/news/)
- [WasmGC Chrome Blog](https://developer.chrome.com/blog/wasmgc)
- [V8 WasmGC Porting](https://v8.dev/blog/wasm-gc-porting)
- [Component Model Concepts (Bytecode Alliance)](https://component-model.bytecodealliance.org/)
- [WASI Roadmap (wasi.dev)](https://wasi.dev/roadmap)
- [wasm-gc + Component Model Pre-Proposal](https://github.com/WebAssembly/component-model/issues/525)

ツール:
- [wasm-tools](https://github.com/bytecodealliance/wasm-tools)
- [wit-bindgen](https://github.com/bytecodealliance/wit-bindgen)
- [jco](https://bytecodealliance.github.io/jco/)
- [Binaryen](https://github.com/WebAssembly/binaryen)

MoonBit:
- [MoonBit Component Model Blog](https://www.moonbitlang.com/blog/component-model)
- [MoonBit JS String Builtins](https://www.moonbitlang.com/blog/js-string-builtins)
- [MoonBit FFI Docs](https://docs.moonbitlang.com/en/latest/language/ffi.html)
- [MoonBit Component Model Tutorial](https://docs.moonbitlang.com/en/stable/toolchain/wasm/component-model-tutorial.html)

レジストリ:
- [wa.dev](https://wa.dev/)
- [wasm-pkg-tools (wkg)](https://github.com/bytecodealliance/wasm-pkg-tools)
