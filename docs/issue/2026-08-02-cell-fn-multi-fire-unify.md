---
title: cell fn の多重実行の一本化 (DR-114「発火時に 1 回」との乖離)
status: open
category: bug
created: 2026-08-02T15:14:10+09:00
last_read:
open_entered: 2026-08-02T15:14:10+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ)
---

# cell fn の多重実行の一本化 (DR-114「発火時に 1 回」との乖離)

## 概要

DR-114 は cell fn を発火時に 1 回呼ぶ規範だが、現行実装は同じ発火を **3 者が独立に実行**する:

1. effects 射影 (`src/kuu/front_door.mbt` の `projected_effect` — parse 相の公開 API)
2. 枝ローカル効果列 fold (`src/internal/engine/branch_fold.mbt` — DR-127 §4.2、裁定前)
3. resolve 相の CLI seat 解決 (`src/kuu/resolve.mbt` の `resolve_entity_raw`)

1 と 3 は W2-8 以前からの既存二重実行で、W2-8 (2) が 1 回を足した。3 者とも共有 fold
(`src/internal/fold/cell_fold.mbt` の `fold_seat_effect`) を呼ぶが、呼び出し自体は独立。

## 危険域

**value_residual セル × 非決定 Value fn** — fold の枝選別 (ctx.old 依存判定 / 構造適合検査)
に使った値と、resolve 相が最終的に座へ書く値が乖離しうる。builtin の Value fn (incr / unset 等)
は old に対して決定的で、現 corpus (conformance 889 cases + wbtest) に非決定 fn は無い —
現時点で観測可能な乖離は発火していない。露出するのは第三者 resident が uuid / 乱数 / 時刻等の
fn を登録した場合。

## 設計上の制約 (W2-8 監査時の整理)

- fold 結果を勝ち枝へ引き渡す「席」が無い — `parse_tree` の Success payload は
  `Array[Binding]`。binding の書き換え (Invoke → Set(値)) は DR-038 の経路同一性 (op は
  効果列 key の一部) と DR-045 の effects 観測 (op=invoke の綴り) を壊すため不可。
- 公開 API 拡張は resolve / front_door / conformance runner を跨ぐ。effects 射影 (1) も
  排さないと DR-114「1 回」には届かない。
- `project_effects` の env/config 供給問題 (W2-4 findings §3.2) と同じ公開 API 判断に
  踏み込むため、**W2-9 (観測面の仕上げ) の窓で一体設計する**のが妥当 (W2-8 統括合意)。

## 受け入れ条件

- [ ] 発火 1 件につき cell fn 実行が 1 回になる引き渡し設計を決める (effects 射影分も含む)
- [ ] DR-038 経路同一性 / DR-045 effects 観測を壊さないことを wbtest で示す
- [ ] 既存 tests / conformance 889 cases 不変

## 関連

- `docs/findings/2026-08-02-w2-8-branch-local-fold.md` (M2 段階化の判断記録)
- `docs/findings/2026-08-02-w2-4-fold-unification.md` §3.2 (project_effects の供給問題)

## TODO

<!-- wip 時のみ -->
