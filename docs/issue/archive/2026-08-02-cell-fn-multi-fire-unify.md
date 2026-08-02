---
title: cell fn の多重実行の一本化 (DR-114「発火時に 1 回」との乖離)
status: resolved
category: bug
created: 2026-08-02T15:14:10+09:00
last_read:
open_entered: 2026-08-02T15:14:10+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-08-02T21:31:00+09:00
discard_reason:
pending_reason:
close_reason: ["finding/2026-08-02-firing-record-unification", "implemented"]
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
  踏み込むため、**W2-9 (観測面の仕上げ) の観測面設計に統合する** (統括承認 2026-08-02 —
  W2-9 委譲時に統括側がスコープへ組み込む。本 issue はその設計入力の正本)。

## W2-9 での設計確定 (実装は後続窓)

W2-9 で一本化設計を確定した。要点:

- **FiringRecord 方式**: 勝ち枝確定後に 1 回だけ fold を実行し、発火ごとに record
  (`{ 遷移結果 / 解決済み residual segment 列 / 座単位 provenance }`) を残す。effects 射影と
  resolve 相の CLI seat 解決は、この record の**消費者**になる (= 独立実行をやめる)
- **値残余セル分**: W2-8 branch fold の枝内実行結果を勝ち枝から引き継ぎ、再実行しない
- **配達席の設計要件 (W2-9 監査 M2 で訂正)**: Binding は derive(Eq) 全 field で、裁定前の
  dedup は Array[Binding] 構造等価 = DR-038 identity の実装そのもの。裁定前に値依存の stamp
  を Binding へ付けると非決定 fn の値差で同一効果列が別経路化する — 「optional stamp だから
  不干渉」は成立しない。FiringRecord は (a) Binding の Eq の外の side payload (枝に併走する
  branch payload) として運ぶか、(b) dedup を明示的な effect identity projection (identity
  参加 field だけの射影キー) に変えるか、のいずれかを設計要件とする。op/operand 不変
  (DR-045 綴り保持) の要件は従来どおり。W2-9 の `source_shadow` は resolve 相 (dedup 後) のみ
  Some という不変条件で安全 (wbtest pin 済み) であり、裁定前 stamp の前例にはならない
- **env/config 供給残差** (W2-4 findings §3.2): parse 入口の optional Supplies
  (env/config provider) で閉じる。未供給呼び出しは現行挙動を維持
- **resolve 相の残余分岐**: 最終防衛線として保持 (削らない)

設計正本は `docs/findings/2026-08-02-w2-9-observation-finish.md` の「実行一本化の設計」節。
W2-9 で実装しなかった理由 (公開 API 変更が観測面と独立に切れない、危険域は現 corpus で未発火)
も同 findings 参照。

## 受け入れ条件

- [x] 発火 1 件につき cell fn 実行が 1 回になる引き渡し設計を決める (effects 射影分も含む)
- [x] DR-038 経路同一性 / DR-045 effects 観測を壊さないことを wbtest で示す
- [x] 既存 tests / conformance 889 cases 不変

## 関連

- `docs/findings/2026-08-02-w2-8-branch-local-fold.md` (M2 段階化の判断記録)
- `docs/findings/2026-08-02-w2-4-fold-unification.md` §3.2 (project_effects の供給問題)

## TODO

<!-- wip 時のみ -->
