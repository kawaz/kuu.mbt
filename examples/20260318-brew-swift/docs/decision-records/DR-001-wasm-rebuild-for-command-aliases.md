# DR-001: kuu.wasm リビルドによるコマンドエイリアス対応

## 問題

spm-swift (20260309) からコピーした kuu.wasm ではコマンドエイリアス (`aliases: ["ls"]`) が
認識されず、`unexpected argument: ls` エラーが発生した。

## 発見経緯

justfile テストシナリオ実行時、`brew-swift ls --full-name -1` で発覚。
WASM bridge に直接 JSON を送って再現確認。

## 解決策

現在の kuu ソースから以下の手順でリビルド:

```bash
# kuu リポジトリルート（ワークスペース内）で
moon build --target wasm-gc --release

# 生成先: _build/wasm-gc/release/build/src/wasm/wasm.wasm
# コピー先: examples/20260318-brew-swift/wasm/kuu.wasm
cp _build/wasm-gc/release/build/src/wasm/wasm.wasm examples/20260318-brew-swift/wasm/kuu.wasm
```

## 選択理由

コマンドエイリアス (DR-037) は spm-swift 作成後に追加された機能。
古い kuu.wasm には含まれていないため、最新ソースからのビルドが必須。

## 追加発見

短形式のみのフラグ (`-1`, `-l`, `-r`, `-t`) は kuu では「長名 + shorts」形式で定義する
必要がある。`flag("1")` では `--1` というロングフラグになり `-1` として認識されない。
解決: `flag("one-per-line", shorts: "1")` のように説明的な長名を付与。
