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
  on_match : (String) -> Unit  // クロージャで型情報をキャプチャ
}

// ヘルパーがジェネリック → 型消去の橋渡し
fn vp_flag(name : String, target : Ref[Bool]) -> PathEntry {
  // target : Ref[Bool] をクロージャ内にキャプチャ
  // PathEntry 自体は Bool を知らない
  PathEntry::{ name, needs_value: false, on_match: fn(_) { target.val = true } }
}
```

## 選択理由

- kuu core の `ExactNode.try_reduce : (Array[String], Int) -> TryResult` と同じ戦略
- ランタイム型キャストが不要（型安全性保証）
- MoonBit の言語制約内で最も自然な方法

## 成果

- `vp_flag` (Bool), `vp_string` (String), `vp_int` (Int), `vp_count` (Int), `vp_append` (Array[String]) を同じ `Array[PathEntry]` に格納可能
- パースループは型を一切知らず、`on_match` コールバックを呼ぶだけ
