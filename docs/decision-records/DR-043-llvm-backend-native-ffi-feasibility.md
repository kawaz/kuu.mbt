# DR-043: MoonBit LLVM backend によるネイティブ FFI ライブラリの実現可能性調査

## 問題

kuu の多言語ブリッジは WASM-GC + js-string-builtins に依存しており、V8 系ランタイム（Node.js サブプロセス）が必須（DR-032, DR-033）。MoonBit の LLVM backend を使えば `.so` / `.a` を生成し、各言語から直接 FFI で呼び出せるのではないか。

## 発見経緯

セッション中の会話で LLVM backend の存在に言及 → PoC 実施を試みた。

## 調査結果

### MoonBit のバックエンド一覧（2026-03 時点、v0.8.3）

| backend | 出力形式 | FFI | exports | 状態 |
|---|---|---|---|---|
| `wasm-gc` | .wasm (GC proposal) | JS interop | `moon.pkg.json` の exports フィールド | 安定 |
| `wasm` | .wasm (plain) | WASI 等 | exports フィールド | 安定 |
| `js` | .js | JS interop | exports (CJS/ESM/IIFE) | 安定 |
| `native` (C) | C ソース → 実行バイナリ | C FFI (`extern "C"`) | **あり（ただし rename 不可）** | 安定 |
| `llvm` | オブジェクトファイル → 実行バイナリ | **未サポート** | 不明 | **実験的** |

### LLVM backend の現状

- x86_64 Linux / ARM64 macOS のみ対応
- **FFI 未サポート**: `extern "C"` による C ライブラリ呼び出しが使えない
- 出力は実行バイナリのみ（`.so` / `.a` 生成の仕組みなし）
- bleeding-edge ツールチェーンでのみ利用可能

### C backend (native) の export 機能

- `moon.pkg.json` の `link.native.exports` フィールドで関数をエクスポート可能
- ただし、**出力は実行バイナリ**。共有ライブラリ (`.so`) を直接生成する仕組みはない
- C ソースが中間生成物として得られるため、理論上は手動で `.so` にコンパイル可能だが公式サポート外

### FFI の方向性

MoonBit の C FFI は **MoonBit → C を呼ぶ**方向に最適化されている:

- `extern "C" fn ... = "symbol_name"` で C 関数をバインド
- `#borrow` アトリビュートでライフタイム管理
- `moonbit_make_external_object` で C リソースを MoonBit GC に載せる

**C → MoonBit を呼ぶ**方向（= kuu をライブラリとして公開する方向）は:

- `exports` フィールドで関数シンボルを公開する仕組みはある
- しかし共有ライブラリとしてパッケージングする手段が公式にない
- GC ランタイムの初期化・共存問題が未解決

## 結論: 現時点では不可

### PoC 成立阻害要因

1. **LLVM backend が FFI 未対応** — 最も致命的。export もできない
2. **共有ライブラリ生成の仕組みがない** — どのバックエンドにも `.so` / `.a` 出力オプションがない
3. **GC ランタイム問題** — MoonBit の GC（C backend は参照カウント）をホスト言語プロセスに同居させる公式手段がない
4. **環境制約** — この検証環境では `cli.moonbitlang.com` へのアクセスがブロックされ、ツールチェーン自体をインストールできなかった

### 今後の可能性

MoonBit は 2026 中盤に v1.0 を予定しており、以下が実現すれば状況が変わる:

- LLVM backend の FFI サポート追加
- 共有ライブラリ出力オプション
- C ABI でのシンボルエクスポートの安定化

### 代替案（現実的な選択肢）

| 方式 | 説明 | 評価 |
|---|---|---|
| **Node.js サブプロセス** (現行) | DR-032 の方式。WASM-GC を Node.js で実行 | 動作実績あり。サブプロセスのオーバーヘッドが課題 |
| **C backend の中間 C ソースを手動コンパイル** | `moon build --target native` で生成される C を `gcc -shared` で `.so` 化 | 非公式。GC 初期化の問題あり。壊れやすい |
| **WASM Component Model** | WASI + Component Model で言語非依存インターフェース | MoonBit 側の対応が限定的。wasmtime の wasm-gc 対応待ち |
| **コード生成（MoonBit → 各言語のパーサコード）** | kuu の定義から各言語ネイティブのパーサコードを生成 | DR-027 で検討済み。kuu の価値が「ワンソース」にあるなら本末転倒 |

## 参考リンク

- [Announcing LLVM backend for MoonBit](https://www.moonbitlang.com/blog/llvm-backend)
- [MoonBit FFI ドキュメント (v0.8.3)](https://docs.moonbitlang.com/en/latest/language/ffi.html)
- [MoonBit C-FFI ガイド](https://www.moonbitlang.com/pearls/moonbit-cffi)
- [MoonBit v0.8.3 Release](https://www.moonbitlang.com/updates/2026/03/10/index)
