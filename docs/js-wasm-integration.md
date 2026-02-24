# JS/Swift/MoonBit 連携

## 連携方式一覧

| 方式 | 連携先 | 推奨度 | 特徴 |
|---|---|---|---|
| wasm-gc + js-string-builtins → JS | JS | 最推奨 | 文字列ゼロコスト |
| JS バックエンド → JS | JS | 推奨 | ゼロコスト |
| Component Model → 任意言語 | 任意 | 標準化志向 | WASI標準ベース |
| native → C FFI → Swift | Swift | 実験的 | .dylib 未サポートが課題 |

## FFI 詳細

### extern "js"（JS target 専用）

JS ターゲットでのみ使用可能。wasm-gc / wasm / native では使用不可。

```moonbit
extern "js" fn alert(msg : String) -> Unit = "globalThis.alert"
```

### extern "C"（native）

ネイティブバックエンドで C 関数を呼び出す。

```moonbit
extern "C" fn c_puts(s : Bytes) -> Int = "puts"
```

### extern "wasm"

wasm バックエンドでインポート関数を宣言。

## 型マッピング

| MoonBit 型 | JS | C/Native |
|---|---|---|
| Int | number | int32_t |
| Int64 | BigInt | int64_t |
| Double | number | double |
| String | string (js-string-builtins) | char* (手動変換) |
| Bool | boolean | int32_t (0/1) |
| Bytes | Uint8Array (JS target) | uint8_t* |
| Unit | undefined | void |

## バインディング生成

```bash
wit-bindgen moonbit
```

Component Model 用のバインディングを WIT ファイルから自動生成する。
