# embed-poc (Go)

kuu-cli の embed+extract+exec パターンの PoC。

## アーキテクチャ

```
Host binary (Go)
  │
  ├── //go:embed bin/kuu-cli-{os}-{arch}
  │     └── 初回: ~/.cache/kuu/kuu-cli-{hash} に展開
  │
  ├── KuuParse(schema)
  │     ├── OptAST JSON を組み立て
  │     ├── exec kuu-cli parse < JSON
  │     └── stdout JSON → ParseResult
  │
  └── ユーザーコード
        └── result.Values["host"] → "example.com"
```

## 従来 (Node.js bridge) との比較

| | Node.js bridge | kuu-cli embed |
|---|---|---|
| ランタイム依存 | Node.js 必須 | **なし** |
| ブリッジコード | kuu_bridge.mjs + WASM ロード | 不要 |
| プロセスモデル | 常駐 (NDJSON) | **ワンショット** (1 exec / 1 parse) |
| 配布 | node_modules に WASM 同梱 | **go:embed でバイナリ同梱** |
| 初回コスト | WASM インスタンス化 | バイナリ展開 (1回のみ) |

## 使い方

```bash
# kuu-cli が PATH にある場合
go run . --verbose serve --port 3000

# kuu-cli を embed する場合 (ビルド時に bin/ に配置)
mkdir -p bin
cp /path/to/kuu-cli bin/kuu-cli-linux-amd64
go build -o embed-poc .
./embed-poc --verbose serve --port 3000
```

## 自己再帰実行パターン (multicall binary)

```bash
# 環境変数 KUU_PARSE=1 で起動すると kuu-cli モードになる
KUU_PARSE=1 ./embed-poc < schema.json
```

これは kuu core が Go にネイティブ統合された場合に有効になるパターン。
現時点では placeholder。
