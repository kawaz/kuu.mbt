# TUI/MoonBit 実践パターン集

tui.mbt の設計から抽出した、sandbox-moonbit で活用するパターン集。

## パッケージ構成

```
moon.mod.json  → "source": "src"
src/
  core/          # 基盤型・ユーティリティ
  render/        # 描画ロジック
  events/        # イベント処理
  io/            # プラットフォーム固有 I/O
  types/         # 共通型定義
```

- 機能ごとに細かくパッケージ分割
- テストファイル: `*_test.mbt`（ブラックボックス）、`*_wbtest.mbt`（ホワイトボックス）
- `moon.pkg`（新形式）を使用

## moon.pkg 設定

```moonbit
// ファイル単位のターゲット分岐 + native リンク設定
options(
  link: { "native": { "cc-link-flags": "src/io/tui_native.c" } },
  targets: {
    "io_js.mbt": [ "js" ],
    "io_native.mbt": [ "not", "js" ],
  },
)
warnings = "-29"
```

- `targets` でファイル単位にビルド対象を制御
- `link` で native ビルド時に C ファイルをリンク
- `warnings` で特定警告を抑制（未使用変数等）

## FFI パターン

JS と Native で同一インターフェースを提供し、ファイル分岐で実装を切り替える。

### JS FFI

```moonbit
// io_js.mbt（JS ターゲットのみ）
extern "js" fn js_print_raw(s : String) =
  #| (s) => process.stdout.write(s)
```

### C FFI (native)

```moonbit
// io_native.mbt（non-JS ターゲット）
extern "C" fn tui_enable_raw_mode() -> Int = "tui_enable_raw_mode"

// #borrow で FixedArray の借用を明示
#borrow(buf)
extern "C" fn tui_write_bytes_ffi(buf : FixedArray[Byte], len : Int) = "tui_write_bytes"
```

**sandbox-moonbit での方針**: C FFI は tui.mbt のように薄いグルーに限定。重いロジックは Rust で書いて C ABI 公開（shimux PoC と同じアプローチ）。

## コード設計パターン

### Option パラメータ（デフォルト値付き）

```moonbit
pub fn box(
  children : Array[Component],
  id? : String = "",
  width? : @types.Dimension = @types.Dimension::Auto,
  flex_grow? : Double = 0.0,
  bg? : Color = Color::transparent(),
) -> Component
```

呼び出し側は `~` suffix で展開:

```moonbit
@vnode.row(
  id~,
  bg~,
  min_width~,
)
```

### グローバル ID カウンター

```moonbit
let component_id_counter : Ref[Int] = { val: 0 }

///|
fn next_id() -> String {
  let id = component_id_counter.val
  component_id_counter.val = id + 1
  "c" + id.to_string()
}
```

### Enum + derive

```moonbit
pub(all) enum InputResult {
  Confirmed(String)
  Cancelled
  TabNext(String)
  ForceQuit
}

pub enum Role {
  Button
  Checkbox
  Custom(String)
} derive(Show, Eq)
```

## テストパターン

### スナップショットテスト

```moonbit
test "CharBuffer::new creates buffer with correct size" {
  let buf = CharBuffer::new(10, 5)
  inspect(buf.width, content="10")
  inspect(buf.height, content="5")
}
```

`moon test -u` で content を自動更新。

### Story ベース（UI コンポーネント）

- Story 構造体でカテゴリ・名前・サイズ・レンダー関数を定義
- `to_plain()` で ANSI コード除去してスナップショット比較
- ビジュアルリグレッションを文字列レベルで検出

## CJK 文字幅

```moonbit
fn char_display_width(c : Char) -> Int {
  // ASCII = 1, CJK = 2
  // Hangul, Hiragana, Katakana, CJK Unified 等を Unicode 範囲で判定
}
```

CLI/TUI ツールでは必須。MoonBit 標準ライブラリにはまだないため自前実装が必要。

## ブロックセパレータ `///|`

全ての関数・テスト・型定義の前に配置:

```moonbit
///|
pub fn render(component : Component) -> String {
  ...
}

///|
test "render empty" {
  ...
}
```

IDE 折りたたみ・ビジュアル整理・ドキュメンテーションの3役を兼ねる。

## ビルドワークフロー

justfile でタスクランナーを構成:

```just
default: check test

fmt:
  moon fmt

check:
  moon check --deny-warn

test:
  moon test

release-check: fmt info check test

info:
  moon info  # .mbti 生成ファイル更新
```

各ワークスペースに justfile を配置。`just` で check + test が即実行できる状態にする。
