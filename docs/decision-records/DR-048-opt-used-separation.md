---
type: decision
---

# DR-048: Accessor.is_set を Opt.used に分離 — 値の committed と opt の used は別概念

**ステータス: accepted（実装済み）**

## 問題

現在の `Accessor[T]` に `is_set: () -> Bool` が含まれているが、これは2つの異なる概念を1つのフィールドに混在させている:

- **val の committed**: 値がデフォルトではなく明示的にセットされたか（ValCell レベル）
- **opt の used**: この Opt 名が CLI で使われたか（Opt レベル）

通常のコンビネータでは `committed = used` なので区別が不要だが、alias では分離が必要:
`--verbose` と `-v` が同じ値を共有しても、「どっちが使われたか」は別。
committed は値に1つ、used は Opt ごとに1つ。

### 現状の実装（ハック）

alias では `Accessor::with_is_set` で Accessor の `is_set` をローカル変数 `opt_used` に差し替えている:

```moonbit
// parser.mbt alias 内
let opt_used : Ref[Bool] = { val: false }
let alias_acc = target_acc.with_is_set(fn() { opt_used.val })
```

「この Opt が使われたか」という概念が Opt の構造に表現されておらず、
ローカル変数 + Accessor の is_set 差し替えで間接的に実現されている。

## 提案

### Accessor から is_set を除去

Accessor は純粋に値操作のみ（get/set/set_value/set_commit/reset の5操作）:

```moonbit
priv struct Accessor[T] {
  get : () -> T
  set : (T) -> Unit
  set_value : (T) -> Unit
  set_commit : () -> Unit
  reset : () -> Unit
}
```

`with_is_set` メソッドも不要になる。

### Opt に used を追加

```moonbit
pub(all) struct Opt[T] {
  id : Int
  name : String
  priv accessor : Accessor[T]
  parsed : Ref[Bool]
  priv used : () -> Bool
}
```

- 通常の Opt: `used = fn() { vc.committed.val }`（値のセット = この opt が使われた）
- alias の Opt: `used = fn() { opt_used.val }`（独立した使用フラグ）
- clone の Opt: `used = fn() { clone_used.val }`（独立した使用フラグ）

### Opt::is_set() メソッド

ユーザー API としての `Opt::is_set()` は `self.used` を返す:

```moonbit
pub fn[T] Opt::is_set(self : Opt[T]) -> Bool {
  (self.used)()
}
```

## 概念の整理

| 概念 | 所属 | 意味 | 数 |
|---|---|---|---|
| `committed` | ValCell | 値が明示的にセットされたか | 値に1つ |
| `used` | Opt | この Opt 名が CLI で使われたか | Opt ごとに1つ |
| `is_set()` | Opt (public API) | ユーザーから見た「セットされたか」= `used` | Opt ごとに1つ |

## 関連 DR

- **DR-045**: ValCell/Accessor 分離 — Accessor に is_set を含めた設計の問題を解消
