# DR-001: Ref バインド方式の設計判断

## 問題

struct-first CLI パーサで、ユーザーの struct とパーサの間をどう橋渡しするか。

## 発見経緯

sf-a-closure（setter クロージャ方式）との比較検討から着手。

## 解決策: Ref[T] 直接バインド

ユーザーの struct フィールドを `Ref[T]` にし、RefBinder がパース結果を copier 経由で書き込む。

```moonbit
struct Config {
  verbose : Ref[Bool]  // Ref[T] フィールド
}
let config = Config { verbose: { val: false } }
binder.flag(name="verbose", target=config.verbose)
binder.parse(args)
// config.verbose.val == true
```

内部的には、各バインドメソッドが copier クロージャを蓄積し、parse 成功後に一括実行する。
copier は `Opt[T].get()` の結果を `Ref[T].val` にコピーする遅延実行パターン。

## サブコマンド内オプション対応

当初は `sub()` で raw Parser を返し、copier を手動登録する混合スタイルだった。
レビューを受けて以下のメソッドを追加し、サブコマンド内オプションも Ref バインドに対応した:

- `positional(parser~, name~, target~)` — サブコマンド内 positional
- `sub_flag(parser~, name~, target~)` — サブコマンド内 flag
- `sub_string(parser~, name~, target~)` — サブコマンド内 string_opt
- `sub_int(parser~, name~, target~)` — サブコマンド内 int_opt
- `sub_count(parser~, name~, target~)` — サブコマンド内 count
- `sub_append_string(parser~, name~, target~)` — サブコマンド内 append_string

`parser~` パラメータで `sub()` が返した Parser を受け取る設計。
copier 登録は RefBinder が一元管理するため、サブコマンドの深さに関わらず parse 後に全 copier が実行される。

## 選択理由

### sf-a-closure との比較

| 観点 | sf-a-closure | sf-b-ref |
|------|-------------|----------|
| バインド記述 | `setter=fn(v) { config.x = v }` | `target=config.x` |
| struct 定義 | `mut` フィールド | `Ref[T]` フィールド |
| 値アクセス | `config.x` | `config.x.val` |
| 型安全性 | コンパイル時 | コンパイル時 |
| ボイラープレート | setter クロージャ記述 | `.val` アクセス |

### トレードオフ

**利点**:
- setter クロージャが不要（`target=config.x` だけ）
- 型安全（Ref[Bool] に Ref[String] を渡せない）
- MoonBit の Ref[T] を自然に活用
- サブコマンド内オプションも sub_xxx メソッドで統一的にバインド可能

**欠点**:
- struct フィールドが `Ref[T]` になる（値型 struct の純粋さが失われる）
- 値アクセスに `.val` が必要
- `Ref[T]` が MoonBit 固有のため他言語への移植性が低い
- 「struct-first」と銘打っているが、実態は Ref を介した参照バインド方式であり、
  プレーンな struct から始める理想とは異なる

## 結論

Ref バインド方式は setter クロージャ方式より記述が簡潔だが、struct 定義に `Ref[T]` が混入する。
MoonBit の参照型セマンティクスを活かした自然なパターンではあるが、「struct-first」の理想（プレーンな struct から始める）からはやや離れる。

この方式は MoonBit 固有の DX パターンとして Layer 4 で提供するのが適切。
