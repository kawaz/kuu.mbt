---
title: Binding.link の名前が実体を表しておらず、spec の link と衝突している
status: open
category: design
created: 2026-07-26T20:01:40+09:00
last_read:
open_entered: 2026-07-26T20:01:40+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 自リポ TODO
---

# Binding.link の名前が実体を表しておらず、spec の link と衝突している

## 概要

`Binding.link : Int` の名前が実体 (global copy の escape 残段数) を表していない。
しかも `link` は spec 側で別の意味を持つ語なので、同じ struct に両方が並ぶと誤読を招く。

## 背景

`src/abi/value.mbt` の `Binding`:

```moonbit
link : Int // a link/global-copy binding (DR-042/007): the number of result-nesting levels it
//           still ESCAPES before settling at its declaring scope. 0 = a normal binding ...
```

`global` 宣言された要素が子スコープで発火したとき、結果を宣言元スコープまで浮上させる
必要がある。その「あと何段ネストを飛び越えるか」の残りカウンタ。ネストを 1 段組むたびに
1 減り、0 でそこに着地する。

- `0` = 通常の binding (各スコープラベルが前置される)
- `N>0` = 宣言より N 段下で発火した global。次の N 段はラベル前置をスキップして escape

**`link` という語がこの説明のどこにも出てこない。** DR-042/007 の global 機能の実装詳細。

### 何と衝突するか

`link` は spec で 2 つの別概念に使われている:

| 語 | 意味 | 出典 |
|---|---|---|
| `link:` 属性 | **値セルへの参照** — その入口は自前のセルを持たず、指定した名前の値セルに束ねられる (DR-029「1 実体 : N 参照」、参照ファミリー ref / link / alias) | DESIGN の共通ノード形、DR-057 |
| `link` source | **同じ値セルに複数の入口があるとき、どの入口から書かれたか** — 自分の入口なら `cli`、参照経由なら `link`。同じセルへの書き込みなので席は変わらず、ラダー同順位 | DR-031 / DR-098 §6 / DR-121 §4 |
| **`Binding.link`** | **global copy の escape 残段数** | DR-042/007 (実装内部) |

3 つ目だけが実装の内部フィールドで、他 2 つと無関係。

### 実害

DR-121 §4 で `Source` に `Link` を追加する作業が控えており、そのとき同じ struct に

```moonbit
source : Source  // Link かもしれない
link : Int       // global escape の残段数 (無関係)
```

が並ぶ。実際、2026-07-26 に統括が `Binding.link` を見て「DR-031 の link は実装済みか」と
一瞬誤読した。第三者が読めば同じ誤読をする。

`link` 属性と `link` source は「値セルへの参照」という 1 つの概念の宣言面と観測面であって
互いに整合している。無関係なのは `Binding.link` (global escape の残段数) だけ。

### 提案 (実体に沿った名前)

- `escape_levels`
- `pending_escape`
- `unnest_remaining`
- `levels_to_declaring_scope` (DR-042 の用語に最も近い)

いずれも「あと何段 escape するか」が読める。決めるのは実装側の判断。

### 実施タイミング

DR-121 §4 の link 実装 (`2026-07-26-link-source-tag-cli-collapse.md`) の前に片付けるのが望ましい。
後にすると、rename 対象と新規追加が同じ struct 内で混ざって差分が読みにくくなる。

### 関連

- `src/abi/value.mbt` の `Binding` 構造体
- `src/internal/engine/eval.mbt` (`b.link > 0` の分岐)
- `src/internal/engine/declaration.mbt:53` (`link_depth` — こちらも同系の命名)
- `src/abi/eval_constructors.mbt` (`link: 0` の初期化)
- DR-042 / DR-007 (global の宣言スコープ着地)
- `docs/issue/2026-07-26-link-source-tag-cli-collapse.md` (DR-121 §4 の link 実装)

## 受け入れ条件

- [ ] `Binding` のフィールド名が実体を表している
- [ ] doc コメントが「link」という語を使わずに機構を説明している
      (使うなら DR-042 の global escape の文脈であることを明示)
- [ ] `pkg.generated.mbti` の追随
- [ ] 既存テストが通る (`decoded=347 ran_cases=783 skipped=0 mismatches=0` / `500 passed`)
