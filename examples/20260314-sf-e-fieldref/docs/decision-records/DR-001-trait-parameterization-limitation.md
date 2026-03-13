# DR-001: MoonBit trait の型パラメータ制限

## 問題

README で設計した `trait AnyBind[S]`（型パラメータ付き trait）が MoonBit でコンパイルできない。

## 発見経緯

Step 2（AnyBind trait 実装）の `moon check` で以下のエラー:

```
Parse error, unexpected token `[`, you may expect `{`.
```

MoonBit の trait 定義は型パラメータを受け付けない。

## 関連エラー

1. `trait AnyBind[S]` — trait に型パラメータ不可
2. `&AnyBind[S]` — trait object にも型パラメータ不可
3. `impl[S, T] AnyBind[S] for FieldBind[S, T]` — 上記に依存するため不可
4. `pub(all) trait` — trait の可視性に `pub(all)` は不可（`pub` のみ）
5. `fn f[T]()` — deprecated。`fn[T] f()` を使う

## 解決策

**クロージャベースの型消去**に切り替える。FieldRef と parse 関数をクロージャでキャプチャし、型 T を消去した `Binder[S]` struct を使う。

```moonbit
// NG: trait に型パラメータ
trait AnyBind[S] { apply(Self, S, String) -> (S, ReduceResult) }

// OK: クロージャで型消去
struct Binder[S] {
  name : String
  apply : (S, String) -> (S, ReduceResult)
}
```

これは kuu 本体の ExactNode パターン（クロージャで Ref[T] をキャプチャ）と同じアプローチ。

## 選択理由

- MoonBit の型システムの制約として受け入れる
- クロージャベースの型消去は kuu で実証済みの安定パターン
- trait object よりも実装がシンプルになる利点もある
- 将来 MoonBit が parameterized trait をサポートすれば、trait object 方式への移行も可能
