---
type: research
---

# DR-033: WASM bridge 制限事項と多言語ブリッジ戦略

## 背景

kuu の WASM bridge (`src/wasm/main.mbt`) は JSON schema → kuu core (WASM-GC) → JSON result のアーキテクチャで動作する。10個の example（5言語）を通じて、bridge の対応範囲と制限が明確になった。

## WASM-GC と js-string-builtins の制約

kuu の WASM は **WASM-GC + js-string-builtins** でビルドされる。

- WASM-GC: ホスト環境の GC を利用。バイナリが小さい（56KB raw / 19KB zstd）
- js-string-builtins: JS ネイティブ文字列を WASM から直接利用

この組み合わせは **V8 系ランタイム（Node.js, Deno, Bun）でのみ動作**する。wazero (Go), wasmtime (Rust/Python), WasmKit (Swift) 等は WASM-GC 未対応のため直接実行不可。

## 対応済み機能

| kind | 説明 |
|---|---|
| flag | bool フラグ |
| string | 文字列オプション（choices 対応） |
| int | 整数オプション |
| count | カウンタ（-vvv） |
| append_string | 文字列配列蓄積 |
| append_int | 整数配列蓄積 |
| positional | 位置引数 |
| rest | 残り全位置引数 |
| command | サブコマンド（ネスト対応） |

## 未対応機能

各 example で発見された制限事項を統合。

### 高優先度

| 機能 | 概要 | 発見元 | 影響 |
|---|---|---|---|
| **variations** | --flag / --no-flag の否定形・トグル等 | gcc, curl | gcc で 17 個の variation が全て使用不可 |
| **command aliases** | `build` → `b` 短縮名 | cargo-python | パース失敗（"unexpected argument"） |
| **serial** | 複数位置引数の順次消費 | git-typescript | positional + rest で代用 |

### 中優先度

| 機能 | 概要 | 発見元 | 対処法 |
|---|---|---|---|
| **exclusive** | 排他的オプション制約 | git-typescript | ホスト言語側で事後検証 |
| **required** | 必須オプション制約 | git-typescript | ホスト言語側で事後検証 |
| **require_cmd** | サブコマンド必須制約 | git-typescript | result.command 未定義を検出 |
| **implicit_value** | 値省略時のデフォルト | git-typescript | 常に値指定を要求 |
| **dashdash** | `--` セパレータ | gcc | rest(stop_before) で代用 |

### 低優先度（ホスト言語側で対処が自然）

| 機能 | 概要 | 理由 |
|---|---|---|
| **post フィルタ** | trim, non_empty, in_range 等 | クロージャは JSON 表現不可。ホスト言語の型システムで補完 |
| **custom[T]** | カスタムパーサ | 同上。DR-030 の設計方針に従う |

## 多言語ブリッジ方式

| 言語 | 方式 | 理由 |
|---|---|---|
| TypeScript | 直接 WASM | V8 で WASM-GC + js-string-builtins 完全対応 |
| Go | Node.js サブプロセス | wazero が WASM-GC 未対応 |
| Python | Node.js サブプロセス | wasmtime-py が WASM-GC 未対応 |
| Swift | bun サブプロセス | WasmKit が WASM-GC 未対応 |

TypeScript 以外は全て「V8 系ランタイムをサブプロセスで呼ぶ」パターンに収束。JSON in/out のインターフェースが言語中立性を保証している。

## 設計上の帰結

### 2層バリデーション構造

1. **パース層（WASM）**: 対応済み kind の構文解析
2. **ビジネスロジック層（ホスト言語）**: exclusive, required, post 等の制約検証

### bridge 拡張の方針

- variations と command aliases は JSON schema で表現可能 → bridge 側で対応すべき
- exclusive, required 等の制約は「プリセット制約名」として schema に追加可能だが、ホスト言語側実装の方が柔軟
- custom[T], post はクロージャであり JSON 表現不可 → ホスト言語側が正解（DR-030）

## 関連 DR

- DR-027: core 純粋関数主義 + 多言語 DX レイヤー構想
- DR-030: opt AST の言語間ポータビリティ
- DR-032: Go からの kuu WASM 利用（Node.js ブリッジ方式）
