# DR-001: Python から kuu WASM bridge を呼び出す戦略

## 問題

kuu WASM bridge は MoonBit の `wasm-gc` ターゲットでビルドされ、`js-string builtins` を使用する。
この組み合わせは V8 (Node.js v25+) でのみ動作し、Python の WASM ランタイム（wasmtime-py, wasmer 等）では実行できない。

## 発見経緯

Task #1 の WASM bridge API 調査で、`moon.pkg` の設定と `kuu-wasm.ts` のローダー実装を確認した結果、以下が判明:

1. `wasm-gc` proposal は V8 以外のランタイムではサポートが限定的
2. `js-string builtins` は V8 固有の文字列相互運用機構
3. wasmtime-py は wasm-gc の実験的サポートはあるが js-string builtins 非対応

## 検討した選択肢

### A. Node.js サブプロセスブリッジ（採用）

Python → Node.js subprocess → WASM bridge → JSON 結果

- 利点: 確実に動作、実装がシンプル、既存の WASM bridge をそのまま利用
- 欠点: Node.js 依存、プロセス起動のオーバーヘッド（約100ms）
- 適合性: デモ用途では十分。本番でもバッチ処理なら許容範囲

### B. wasmtime-py で直接実行（不採用）

- 理由: wasm-gc + js-string builtins の組み合わせが未サポート
- 将来的に MoonBit が plain WASM ターゲットをサポートすれば再検討の余地あり

### C. HTTP ブリッジ（不採用）

Node.js HTTP サーバー → Python HTTP クライアント

- 理由: デモ用途に対して過剰な複雑性

## 解決策

`src/kuu_bridge.mjs`: stdin JSON → kuu_parse → stdout JSON の薄いブリッジスクリプト
`src/kuu.py`: Python 側ラッパー。subprocess で Node.js を呼び出し、結果を dataclass に変換

## 選択理由

- JSON 入出力という kuu WASM bridge の設計が言語中立性を保証しており、ブリッジ方式は自然な帰結
- DR-027（core 純粋関数主義）の「各言語のイディオムで DX を提供」という方針にも合致
- サブプロセスのオーバーヘッドは CLI ツールの起動時間としては許容範囲内
- このパターンは wasm-gc が他ランタイムでサポートされるまでの過渡的解決策であり、将来的には直接呼び出しに移行可能
