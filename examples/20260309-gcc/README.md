# mygcc — gcc-like CLI argument parser demo

kuu の **Variation** 機能を集中的にデモするため、gcc のコマンドラインオプション体系をモデルにした引数パーサ。

```bash
moon run examples/20260309-gcc
```

## kuu 機能カバレッジ

| kuu 機能 | mygcc での実例 |
|---|---|
| **variation_false (sugar)** | `--wall`/`--no-wall`, `--fpic`/`--no-fpic` 等 14 フラグ |
| **variations array (explicit)** | `--fcommon`/`--no-fcommon`, `--fstack-protector`/`--no-fstack-protector` |
| **variation_toggle** | `--diagnostics-color`/`--toggle-diagnostics-color` |
| **default=true + variation_false** | `--pie`/`--no-pie`, `--fexceptions`/`--no-fexceptions` |
| **string_opt + choices** | `--optimize` (0,1,2,3,s,g,fast), `--std` (c11,c17,...), `--language` |
| **append_string** | `--define`, `--undefine`, `--include-path`, `--lib`, `--lib-path` |
| **exclusive** | `--compile`/`--assemble`/`--preprocess`, `--shared`/`--static`, `--m32`/`--m64` |
| **rest (positional) + stop_before** | ソースファイル (`main.c util.c`) |
| **shorts** | `-o`, `-c`, `-S`, `-E`, `-g`, `-v`, `-O`, `-D`, `-U`, `-I`, `-l`, `-L`, `-x` |
| **flag** | `--verbose`, `--pipe`, `--shared`, `--static`, `--m32`, `--m64` |
| **string_opt** | `--output`, `--arch`, `--tune` |

## 注目ポイント

### Variation で `-W`/`-Wno-` パターンを表現

gcc の `-Wall`/`-Wno-all` パターンを、kuu の `variation_false` で `--wall`/`--no-wall` として表現。

```moonbit
let wall = p.flag(
  name="wall",
  description="Enable most warning messages",
  variation_false=Some("no"),  // --no-wall を自動生成
)
```

同じパターンで `-f`/`-fno-` (コード生成フラグ) も表現:

```moonbit
let fpic = p.flag(
  name="fpic",
  description="Generate position-independent code",
  variation_false=Some("no"),  // --no-fpic を自動生成
)
```

### default=true で「デフォルトON、明示OFF」

gcc の `-fexceptions`（C++ではデフォルトON）や `-pie`（デフォルトON）のように、
デフォルトで有効だが `--no-xxx` で無効化できるパターン。

```moonbit
let pie = p.flag(
  name="pie",
  default=true,                // デフォルトで有効
  description="Create a position-independent executable",
  variation_false=Some("no"),  // --no-pie で無効化
)
```

### explicit variations array

sugar の代わりに `variations` 配列を直接指定する形式。より細かい制御が可能。

```moonbit
let fcommon = p.flag(
  name="fcommon",
  description="Place uninitialized global variables in a common block",
  variations=[@core.False("no")],  // sugar の variation_false と同等
)
```

### 3組の exclusive 制約

```moonbit
// コンパイルステージ: 1つだけ指定可能
p.exclusive([compile.as_ref(), assemble_only.as_ref(), preprocess.as_ref()])

// リンク方式: shared か static の一方のみ
p.exclusive([shared.as_ref(), link_static.as_ref()])

// アーキテクチャ: 32bit か 64bit の一方のみ
p.exclusive([m32.as_ref(), m64.as_ref()])
```
