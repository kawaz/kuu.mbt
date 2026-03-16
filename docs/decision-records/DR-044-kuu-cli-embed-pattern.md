# DR-044: kuu-cli embed+extract+exec パターン

type: decision

## 問題

kuu の多言語ブリッジは Node.js サブプロセス + WASM-GC に依存（DR-032, DR-033）。全ての非 V8 言語で Node.js ランタイムが必須。DR-043 で native FFI も現時点では不可。

## 発見経緯

セッション中の議論。「中途半端なブリッジプロセスをかますくらいならシンプルに kuu-cli を作り、OptAST を食わせてパース結果を JSON で返す」という提案から発展。

## 判断

**kuu-cli (native binary) + embed+extract+exec パターンを採用する。**

### kuu-cli

MoonBit native backend (C) でビルドされた単一バイナリ。stdin JSON → kuu core → stdout JSON。I/F は既存 WASM bridge と同一（JSON protocol v1）。

### embed パターン

各言語の DX レイヤーが kuu-cli バイナリをパッケージに embed し、ユーザーから隠蔽する。ユーザーからは普通のライブラリに見える。

## 選択理由

| | Node.js ブリッジ (現行) | kuu-cli embed |
|---|---|---|
| ランタイム依存 | Node.js 必須 | **なし** |
| ブリッジコード | kuu_bridge.mjs + WASM ロード | 不要（exec + JSON） |
| 配布 | node + WASM 同梱 | kuu-cli バイナリ同梱 |
| DX レイヤー複雑度 | WASM ロード + メモリ管理 | exec + JSON |

## 実現可能性

Go/Rust で PoC 実施済み。OS ごとのセキュリティ制約も調査済み。

詳細: `docs/research/2026-03-16-embed-extract-exec-feasibility.md`

## PoC

- `examples/20260316-embed-go/`
- `examples/20260316-embed-rust/`

## 次のステップ

1. kuu-cli の MoonBit ソース作成（src/wasm/ の bridge ロジックを native target で動かす）
2. MoonBit C backend でビルド・動作確認
3. PoC を実際の kuu-cli バイナリで end-to-end 検証
