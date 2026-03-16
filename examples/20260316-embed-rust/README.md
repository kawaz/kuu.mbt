# embed-poc (Rust)

kuu-cli の embed+extract+exec パターンの PoC (Rust)。

## アーキテクチャ

```
Host binary (Rust)
  │
  ├── include_bytes!("bin/kuu-cli-{os}-{arch}")
  │     └── 初回: ~/.cache/kuu/kuu-cli-{hash} に展開
  │
  ├── kuu_parse(&schema)
  │     ├── OptAST JSON を serde で組み立て
  │     ├── exec kuu-cli parse < JSON
  │     └── stdout JSON → ParseResult
  │
  └── ユーザーコード
        └── result.values["host"] → "example.com"
```

## 使い方

```bash
# kuu-cli が PATH にある場合
cargo run -- --verbose serve --port 3000

# embedded binary を使う場合
mkdir -p bin
cp /path/to/kuu-cli bin/kuu-cli-linux-amd64
cargo run --features embed -- --verbose serve --port 3000
```
