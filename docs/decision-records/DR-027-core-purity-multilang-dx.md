# DR-027: core 純粋関数主義 + 多言語 DX レイヤー構想

## 背景

examples/archives/ の mygit Before/After 比較（20260307 vs 20260308）で、以下のパターンが残存していることが判明:

1. `get().unwrap()` / `get().unwrap_or(default)` の繰り返し
2. `match result.child("xxx")` によるディスパッチのボイラープレート
3. serial 内の `let mut` + `Option` パターン

これらを core に解決させようとすると core が肥大化し、言語固有のイディオムと乖離する。

## 決定

### 1. core は純粋関数ベースの薄いパースエンジンに留める

- `get() -> T?` と `get_or(T) -> T` 程度の API で十分
- core に DX 機能を詰め込まない
- 純粋関数 + 充実テストで堅牢性を確保

### 2. 言語固有の DX は各言語のイディオムで別レイヤーとして提供

core の低レベル API セットを FFI で export し、各言語の「良きやり方」で高級 API を提供する:

| 言語 | アプローチ |
|---|---|
| **MoonBit** | codegen で struct + 純粋関数（`extract_xxx_opts(result) -> XxxOpts!ParseError`）を生成 |
| **TypeScript** | union / infer / conditional types で型レベル解決。required → non-optional |
| **Go** | `go generate` で struct 生成 |
| **Rust** | derive マクロ / proc マクロで型安全ラッパー |
| **Python** | dataclass / TypedDict ベースのラッパー |
| **Swift** | Codable / property wrapper パターン |

### 3. パッケージ構成イメージ

```
src/core/       … パースエンジン（純粋関数、全言語共通）
src/codegen/    … MoonBit 用コードジェネレータ
pkg/ts/         … TypeScript ラッパー
pkg/go/         … Go ラッパー
pkg/rs/         … Rust ラッパー
pkg/py/         … Python ラッパー
pkg/swift/      … Swift ラッパー
```

## 選択理由

- core が純粋関数 + テスト充実で堅牢なら、その上に何を載せても安心
- 型安全な取り出し（required option → non-optional）の最適解は言語ごとに異なる
- 1つの core で全言語に対応するより、各言語の得意技を活かすほうが DX が良い
- 各言語のラッパーは独立して進化可能

## 発見経緯

examples/archives/ の mygit の定期的な作り直し（20260307 → 20260308）で API の進化を計測する運用の中で、`get().unwrap()` 問題の本質的な解決策として浮上。
