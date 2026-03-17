# kuu でできること（事例集）

kuuの機能や嬉しさを具体例で紹介する。随時追加。

<!-- TODO: 各事例にコード例を追加 -->

## パース

- ショートオプション結合の型情報分解（`-vA1B1` を型で正確に分解）
- `--color` / `--color=always` が追加コードなしで動く（implicit_value）
- choices + implicit_value の共存
- 定義順序に依存しないパース
- サブコマンドのネスト
- `--` セパレータ以降の引数収集
- positional 引数と rest の組み合わせ
- serial（複数 positional の順序パース）

## オプション関係

- alias: 別名（`--verbose` と `-v`）
- clone: 独立した値を持つ派生オプション
- link: オプション間の値転送（`--verbose` → `--debug` 含意）
- adjust: パース後の値変換・バリデーション
- deprecated: 非推奨オプションの警告付きサポート
- variation: `--no-color` / `--reset-color` 等のプレフィックス派生
- exclusive / required / at_least_one: オプション間の制約

## DX

- struct-first: 構造体定義からパーサを自動構築（MoonBit dx 層）
- 環境変数連携のヘルプ表示（`[env: COLOR]`）

## 多言語

- WASM bridge 経由で JSON in → parse → JSON out
- Go / Rust / TypeScript / Python / Swift のデモ example あり
- embed+extract+exec パターンの PoC（Go / Rust）
