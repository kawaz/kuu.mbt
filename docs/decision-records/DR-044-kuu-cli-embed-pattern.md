# DR-044: kuu-cli embed+extract+exec パターン

## 問題

kuu の多言語ブリッジは Node.js サブプロセス + WASM-GC に依存（DR-032, DR-033）。全ての非 V8 言語で Node.js ランタイムが必須となり、配布・DX の両面でボトルネックになっている。

DR-043 で MoonBit の native backend（LLVM/C）による `.so` 生成を調査したが、現時点では不可。

## 発見経緯

セッション中の議論。「中途半端なブリッジプロセスをかますくらいならシンプルに kuu-cli を作り、OptAST を食わせてパース結果を JSON で返す機能を提供する」という提案から発展。

## 解決策: kuu-cli + embed パターン

### kuu-cli

MoonBit native backend (C) でビルドされた単一バイナリ。stdin から OptAST JSON を受け取り、kuu core でパースし、結果 JSON を stdout に返す。

```
echo '{"version":1,"opts":[...],"args":["--verbose"]}' | kuu-cli parse
```

- I/F は既存の WASM bridge（src/wasm/）と完全に同一の JSON プロトコル（version: 1）
- Node.js 不要、WASM 不要、依存ゼロ

### embed+extract+exec パターン

各言語の DX レイヤーが kuu-cli バイナリをパッケージに同梱し、ユーザーから隠蔽する:

```
DX レイヤー (Go/Rust/Python/Swift)
  ├── kuu-cli バイナリを embed（go:embed, include_bytes!, wheel 等）
  ├── 初回実行時にキャッシュディレクトリに展開
  ├── exec kuu-cli parse < OptAST JSON
  └── stdout JSON → 言語ネイティブ型にデシリアライズ
```

ユーザーからは「普通のライブラリ」として見える。kuu-cli の存在を意識する必要がない。

### 自己再帰実行パターン（multicall binary）

将来、kuu core が各言語にネイティブ統合された場合に有効になる発展形:

```
Host binary
  ├── KUU_PARSE=1 → kuu-cli モード（stdin JSON → stdout JSON）
  └── 通常モード → exec(os.Args[0]) with KUU_PARSE=1
```

現時点では kuu core のホスト言語統合（native library, WASM in-process 等）に依存するため placeholder。

## 選択理由

### Node.js ブリッジとの比較

| | Node.js ブリッジ (現行) | kuu-cli embed |
|---|---|---|
| ランタイム依存 | Node.js 必須 | **なし** |
| プロセスモデル | 常駐 NDJSON | ワンショット exec |
| ブリッジコード | 各言語で kuu_bridge.mjs + WASM ロード | 不要（exec + JSON） |
| 配布 | node + WASM バイナリ同梱 | kuu-cli バイナリ同梱 |
| DX レイヤーの複雑度 | WASM ロード + メモリ管理 | exec + JSON 文字列 |
| レイテンシ | WASM インスタンス化 + 関数呼び出し | プロセス起動 |
| 初回コスト | WASM コンパイル | バイナリ展開（1回のみ） |

### 各言語での embed 手段

| 言語 | embed 方法 | 配布方法 |
|---|---|---|
| Go | `//go:embed bin/kuu-cli-{os}-{arch}` | `go get` で自動同梱 |
| Rust | `include_bytes!("bin/kuu-cli")` | crates.io の build.rs で取得 |
| Python | wheel に platform binary 同梱 | `pip install kuu` |
| Swift | SPM の `resources` | `swift package` |

### 懸念事項

1. **レイテンシ**: 毎回プロセス起動。ただし CLI 用途では1回のパースなので問題ない
2. **バイナリサイズ**: ホストバイナリ + kuu-cli 分。WASM (56KB) より大きくなる可能性
3. **クロスプラットフォーム**: OS/arch ごとのバイナリが必要。CI でマトリクスビルド

### Linux 最適化: memfd_create

Linux では `memfd_create` + `fexecve` でディスクに書かずにメモリ上で exec 可能。tmpfile 問題が完全に消える。

## PoC

- `examples/20260316-embed-go/` — Go 版 PoC
- `examples/20260316-embed-rust/` — Rust 版 PoC

いずれも kuu-cli が PATH にあれば動作。embed 版は kuu-cli バイナリを `bin/` に配置してビルド。

## 既存資産との関係

- `src/wasm/main.mbt` の `kuu_parse()` が行うこと（JSON → core → JSON）は kuu-cli でも完全に同一
- kuu-cli は native target で同じロジックを動かすだけ。WASM bridge のコードをほぼ流用可能
- JSON プロトコル（version: 1）は変更なし

## 次のステップ

1. kuu-cli の MoonBit ソース作成（src/wasm/ の bridge ロジックを native target で動かす）
2. MoonBit C backend でビルド・動作確認
3. PoC を実際の kuu-cli バイナリで検証
