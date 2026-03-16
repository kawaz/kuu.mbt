# DR-032: Go からの kuu WASM 利用 — Node.js ブリッジ方式

type: research

## 問題

kuu の WASM bridge (`src/wasm/`) を Go (wazero) から直接呼び出せない。

## 発見経緯

20260309-mydocker-go（examples/archives/）作業開始時の WASM bridge 調査で発覚。

## 技術的障壁

### 障壁1: wasm-gc 未サポート

kuu の WASM 出力は WebAssembly GC Proposal (`wasm-gc`) の型拡張を多用している。
wazero は wasm-gc を未サポート（対応時期未定、小チームのため finished proposals にフォーカス）。

### 障壁2: JS String Builtins 依存

`use-js-builtin-string: true` により、`kuu_parse` の引数・戻り値は `(ref extern)` 型 = JS ネイティブ文字列。
WebAssembly JS String Builtins Proposal に基づく機能で、ブラウザ/Node.js でのみ利用可能。

### plain wasm ターゲットも不可

`moon build --target wasm` では kuu のコード生成が wasm-gc 前提のため、
kuu_parse が実質的に含まれない（出力 68 bytes、`_start` のみ）。

## 解決策: Node.js ブリッジ

```
Go プロセス
  └─ exec.Command("node", "kuu_bridge.mjs")
       └─ stdin/stdout で JSON をやりとり
            └─ WebAssembly.instantiate(wasmBytes, {}, { builtins: ["js-string"] })
                 └─ kuu_parse(jsonInput) -> jsonOutput
```

Node.js v25.5.0 で `builtins: ["js-string"]` + `importedStringConstants: "_"` が動作確認済み。
kuu_parse の I/F が `JSON string → JSON string` なので、Go 側は JSON の serialize/deserialize のみ。

## 選択理由

| 方式 | 実現性 | 備考 |
|---|---|---|
| **Node.js ブリッジ** (採用) | 高 | 既存テスト (test.mjs) で実証済み |
| Deno ブリッジ | 高 | wasm-gc + JS builtins 対応。代替として有効 |
| Go native 再実装 | 中 | WASM 不使用。kuu 追従コスト大 |
| wazero wasm-gc 対応待ち | 低 | 時期不明 |

## 影響

- Go example は Node.js 依存が発生（開発時のみ）
- 本番利用では `go generate` + codegen で Node.js 依存を解消する設計を将来検討
