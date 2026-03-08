# kuu バイナリサイズ調査 (2026-03-05)

## 計測条件

- moon 0.1.20260209 (feature flags: rupes_recta, rr_moon_pkg)
- `--release` ビルド
- `src/_size_check/` の is-main パッケージで計測
- kuu の主要 API を全種使用（flag, int_opt, string_opt, append_string, append_int, count, positional, rest, cmd, parse, get, child, as_map, generate_help, ParseErrorInfo::to_string, HelpRequested/ParseError エラーハンドリング）
- ランタイム（GC, 文字列処理, Map/Array 等の標準ライブラリ）込みの数値

## 結果

### Raw サイズ

| ターゲット | bytes | KB |
|---|---|---|
| WASM-GC | 37,740 | 36.9 |
| WASM (linear memory) | 68,019 | 66.4 |
| JS | 158,223 | 154.5 |
| JS (bun minify) | 38,930 | 38.0 |

### 圧縮サイズ

| ターゲット | gzip -9 | zstd --ultra -22 | brotli --best |
|---|---|---|---|
| WASM-GC | 14.9 KB | 13.4 KB | 12.7 KB |
| WASM | 24.6 KB | 21.5 KB | 19.9 KB |
| JS | 18.2 KB | 15.5 KB | 14.8 KB |
| JS (bun minify) | 10.5 KB | 9.7 KB | 9.0 KB |

### 所感

- JS は minify 前は最大だが、minify + 圧縮で最小（brotli 9.0 KB）
  - JS は文字列リテラルの重複が多く、圧縮の恩恵が大きい
- WASM-GC は raw で最小、圧縮後は JS minify に次ぐ（brotli 12.7 KB）
- WASM (linear memory) は全方式で最大

## 再現手順

```bash
just build-release
just size
```
