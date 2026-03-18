---
type: decision
---

# DR-044: clone / link / adjust コンビネータ実装

> **Note**: DR-045 で大幅に進化。clone は alias ラッパー(v1)から独立 cell の save/restore パターンに変更。link に propagate_set~ パラメータ追加。alias の commit は Accessor.set_commit 経由に統合。

## 背景

DR-037 で設計した 3 直交プリミティブ（clone, link, adjust）と、
DR-043 で追加した `priv setter` により、実装の準備が整った。

## 設計方針

### adjust: post_hook による値変換

最もシンプルなプリミティブ。パース後に FilterChain（値を加工する関数）を通して値を変換する。

```moonbit
pub fn[T] Parser::adjust(
  self : Parser, target : Opt[T], after_post~ : FilterChain[T, T],
) -> Unit
```

**実装**: `post_hook` に `(target.setter)((after_post.run)((target.getter)()))` を登録。
`is_set` が true の場合のみ適用する（未設定の default 値には変換を掛けない）。

同一 target に複数の adjust を登録した場合、post_hooks の登録順（= adjust の呼び出し順）に実行される。

### link: post_hook による値転送

source の値を target に転送する。source が set されている場合のみ。

```moonbit
pub fn[T] Parser::link(
  self : Parser, target : Opt[T], source~ : Opt[T],
) -> Unit
```

**実装**: `post_hook` に source.is_set チェック → `(target.setter)((source.getter)())` を登録。
getter は `() -> T` 型（raw 値を返す）。source が set されていれば無条件に転送する。

**is_set の非更新**: link による値転送は `setter` を使うため、target の `is_set` は変更しない。
これは設計上の意図的な判断 — link は「パースによる設定」ではなく「コンビネータによる値伝搬」であり、
`is_set` は「ユーザーがコマンドラインで明示的に指定したか」を表す指標として独立を保つ。
結果として `target.get()` が `Some(v)` を返しつつ `target.is_set` が `false` という状態が生じうる。

**DR-037 との差分**: DR-037 は link を「Ref 共有（ポインタ付け替え）」として定義しているが、
v1 では post_hook による一回限りの値コピーとして実装する。Ref 共有は以降の全書き込みが連動するが、
値コピーはパース完了後の一回のみ。実用上は大半のケースで同等だが、セマンティクスは異なる。

### clone: v1 は alias のラッパー

DR-037 は clone を「新 Ref、フィルタ参照共有」と定義しているが、
v1 では alias のラッパーとして実装する。名前と is_set のみ独立、値は共有。

```moonbit
pub fn[T] Parser::clone(
  self : Parser, name : String, target : Opt[T],
) -> Opt[T]
```

**v1 の割り切り**: `self.alias(name, target)` を呼ぶだけ。
独立 cell を持つ完全な構造コピーは、ユースケースが出てきた時点で実装する。
clone の返り値は将来的に alias とは異なる内部構造になる可能性がある。

## 決定

### 実装順序

1. **adjust**: post_hook ベース、最小実装
2. **link**: post_hook ベース、source→target 値転送
3. **clone**: alias ラッパー（v1: 値共有、is_set 独立）

### v1 の制約

- clone の値は target と共有（alias と同じ）。名前と is_set のみ独立。
- adjust は `after_post` のみサポート。`before_pre` 等はユースケース出現時に追加。
- link は値コピー方式。Ref 共有ではない。

### DR-037 との差分

| 概念 | DR-037 の定義 | v1 実装 |
|------|--------------|---------|
| clone | 新 Ref + フィルタ参照共有 | alias のラッパー（is_set のみ独立） |
| link | Ref 共有（ポインタ付け替え） | post_hook による値コピー（一回限り） |
| adjust | フィルタチェーンの前後に挿入 | after_post のみ（post_hook ベース） |

adjust の `before_pre` / `before_accum` / `after_accum` は v1 ではスコープ外。
`after_post` で実用的な大半のケース（値の検証・変換）をカバーできる。
