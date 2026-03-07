# DR-021: exclusive/required バリデーション + is_set 追跡設計

## 背景

排他オプション (`exclusive`) と必須オプション (`required`) のバリデーションを実装するにあたり、「そのオプションが明示的にセットされたか」を判定する仕組みが必要だった。

## 設計判断

### 1. Opt[T] への is_set / name 追加

```moonbit
pub(all) struct Opt[T] {
  id : Int
  name : String          // "--verbose" 等。エラーメッセージ用
  getter : () -> T
  parsed : Ref[Bool]
  is_set : () -> Bool    // 明示的にセットされたか
}
```

**is_set の仕組み**: 各コンビネータ内で `was_set: Ref[Bool]` を作成し、commit クロージャ内で `was_set.val = true` にセット。`consumed=0` のデフォルトフォールバック（Initial[T] の解決等）では was_set を true にしない。

**name の追加理由**: エラーメッセージに opt 名を含めるため。OptMeta には id がなく逆引き不可。Opt[T] に持たせるのが最も自然。

### 2. OptRef — 型消去参照

```moonbit
pub(all) struct OptRef {
  name : String
  is_set : () -> Bool
}
```

MoonBit では `Array[Opt[異なる型]]` が不可能なため、exclusive/required のパラメータには型消去された OptRef を使用。`Opt::as_ref()` で変換。

### 3. exclusive/required は post_hooks ベース

DESIGN.md の旧設計では ValidateCtx 等の専用コンテキスト型を用意する予定だったが、post_hooks の `() -> Unit raise ParseError` で十分だった。

```moonbit
pub fn Parser::exclusive(self, opts: Array[OptRef]) -> Unit
pub fn Parser::required(self, opt: OptRef) -> Unit
```

内部で post_hook を登録するだけの薄いラッパー。

### 4. wrap_node_with_set ヘルパー

ExactNode の commit クロージャを was_set フラグでラップする共通ヘルパー。全コンビネータで使用。

## 不採用案

- **Parser に committed_ids: Map[Int, Bool] を追加** — Opt 側でクロージャキャプチャすれば不要
- **ValidateCtx 専用型** — post_hooks で十分。YAGNI
- **was_set を Opt のフィールドとして直接持つ** — Ref[Bool] をクロージャでキャプチャする方が Opt の immutability を保てる

## 実装状況

全て実装済み。604 → 612 テスト（exclusive 3件、required 2件、is_set 3件追加）。
