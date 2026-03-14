# DR-001: Swift WASM ブリッジアーキテクチャ選定

## 問題

kuu は MoonBit 製 CLI パーサで、WASM モジュールとしてビルドされる。
Swift から kuu を利用するには WASM を実行する手段が必要。

## 発見経緯

Task #1 (WASM ビルド確認) で `use-js-builtin-string: true` による
JS ランタイム依存が判明。

## 選択肢

### A. WasmKit (Pure Swift WASM runtime)
- **利点**: 外部依存なし、SPM パッケージとして追加可能
- **欠点**: wasm-gc + js-string-builtins 未サポート。kuu WASM を実行不可

### B. JavaScriptCore (Apple 標準)
- **利点**: macOS/iOS で標準搭載、外部依存なし
- **欠点**: wasm-gc / js-string-builtins のサポートが不確実

### C. bun subprocess
- **利点**: wasm-gc + js-string-builtins 完全サポート、確実に動作
- **欠点**: bun のインストールが必要、プロセス起動オーバーヘッド

### D. MoonBit で直接実装（Swift を断念）
- **利点**: 確実に動作、既存例との一貫性
- **欠点**: Swift の多言語 DX 戦略 (DR-027) を実証できない

## 解決策

**C. bun subprocess** を採用。

## 選択理由

1. **確実に動作する**: wasm-gc + js-string-builtins を完全サポート
2. **DR-027 の実証**: Swift から kuu を使う多言語パイプラインを実際に動かせる
3. **実用的アーキテクチャ**: 将来の Swift DX レイヤーもこの方式を基盤にできる
4. **bun のオーバーヘッドは許容範囲**: CLI ツールでは起動時に1回だけ呼ぶ

## 副次的発見

- WASM bridge に `dashdash` kind が未実装 → `rest` で代替可能
- SPM の `-Xcc` 等の単一ダッシュロングオプションは kuu 標準パースでは未対応
- `aliases` フィールドは WASM bridge でも正常に動作
