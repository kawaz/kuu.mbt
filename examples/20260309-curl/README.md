# curl CLI Parser Example

kuu を使って curl の引数パーサを実装するデモ。
サブコマンドなしのフラットなオプション構造で、42個のオプション定義を通じて kuu の表現力を検証する。

## ビルド・実行

```bash
# プロジェクトルートから実行
moon check --deny-warn
moon run examples/20260309-curl
```

## just を使う場合

```bash
cd examples/20260309-curl
just check   # moon check --deny-warn
just run     # moon run examples/20260309-curl
just test    # moon test
just fmt     # moon fmt
```

## 検証ポイント

- **フラット構造**: サブコマンドなし、全オプションが同一レベル
- **append_string**: `-H`, `-d`, `-F` などリピータブルオプション
- **variation_false**: `--no-verbose`, `--no-silent` 等の反転フラグ
- **exclusive**: `--silent` vs `--verbose`, `--fail` vs `--fail-with-body`
- **rest**: 末尾の URL を複数受け取り

## 関連ドキュメント

- [設計書](docs/DESIGN.md)
