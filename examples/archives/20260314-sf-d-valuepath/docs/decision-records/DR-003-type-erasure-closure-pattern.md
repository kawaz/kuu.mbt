# DR-003: クロージャによる型消去パターン

## 問題

`ValuePath[S, Bool]` と `ValuePath[S, String]` を同じ配列に入れたい。
MoonBit には trait object / dynamic dispatch がないため、ジェネリック型の heterogeneous collection を直接扱えない。

## 発見経緯

型消去パターン調査で、kuu core の `ExactNode` 設計を参照した際に確認。

## 解決策

kuu core と同じクロージャ束縛パターンを採用:

```moonbit
// 型消去された PathEntry（型パラメータなし）
struct PathEntry {
  name : String
  needs_value : Bool
  on_match : (String) -> String?  // None=成功、Some(msg)=エラー
}

// Commit[T] → PathEntry の橋渡し（ジェネリック → 型消去）
fn[T] vp_custom(name : String, target : Ref[T], commit : Commit[T]) -> PathEntry {
  match commit {
    Exist(f) => PathEntry::{ name, needs_value: false,
      on_match: fn(_) { target.val = f(); None } }
    Value(f) => PathEntry::{ name, needs_value: true,
      on_match: fn(s) { let (val, err) = f(s); match err {
        Some(msg) => Some(msg)
        None => { target.val = val; None }
      }}}
  }
}

// ヘルパーは vp_custom のラッパー
fn vp_flag(name : String, target : Ref[Bool]) -> PathEntry {
  vp_custom(name, target, Exist(fn() { true }))
}
```

## 選択理由

- kuu core の `ExactNode.try_reduce : (Array[String], Int) -> TryResult` と同じ戦略
- ランタイム型キャストが不要（型安全性保証）
- MoonBit の言語制約内で最も自然な方法

## 成果

- `vp_flag` (Bool), `vp_string` (String), `vp_int` (Int), `vp_count` (Int), `vp_append` (Array[String]) を同じ `Array[PathEntry]` に格納可能
- パースループは型を一切知らず、`on_match` コールバックを呼ぶだけ
