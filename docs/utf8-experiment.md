# UTF-8 日本語文字列の実験結果

## 実験ワークスペース

`wip-utf8-experiment`

## ターゲット別の動作状況

| ターゲット | 結果 | 備考 |
|---|---|---|
| JS target | 完全動作 | ゼロコスト |
| wasm-gc（js-builtin-string: true） | 動作 | `use-js-builtin-string:true` が必要 |
| wasm-gc（js-builtin-string: false） | 動作しない | デフォルト設定では不可 |

## String 内部表現

- MoonBit の String は **UTF-16** が内部表現
- `length()`: UTF-16 コードユニット数を返す（サロゲートペア含む場合、見た目の文字数と異なる）
- `char_length()`: Unicode コードポイント数を返す

```moonbit
let s = "こんにちは"
s.length()       // 5 (UTF-16 コードユニット数、日本語はBMP内なので一致)
s.char_length()  // 5 (コードポイント数)
```

## Bytes

- **JS target**: `Uint8Array` にマッピングされる
- **wasm-gc**: opaque（不透明型）

## 重要な制約

- `extern "js"` は **JS target 専用**
  - wasm-gc / wasm / native では使用不可
  - JS target と wasm-gc で同じ FFI コードを共有することはできない

## 既存リポジトリの確認結果

markdown.mbt 等の既存プロジェクトでも、文字列処理は JS target または `use-js-builtin-string:true` の wasm-gc で運用されていることを確認。
