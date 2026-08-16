---
title: union/tuple セル fold・ledger・identity の再設計 (A1 + C-1検査脱落 + 関連 統合)
status: open
category: design
created: 2026-08-16T14:11:16+09:00
last_read:
open_entered: 2026-08-16T14:11:16+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ) 全コードレビュー
---

# union/tuple セル fold・ledger・identity の再設計 (A1 + C-1検査脱落 + 関連 統合)

## 概要

kuu.mbt 全コードレビュー 2026-08-16 (領域別 8 並列) にて、union/tuple セルの DR-138 §6 実装が「単相との非対称」を複数領域で系統的に発生させていることが判明。個別 patch では非対称が再生産されるため、fold・ledger・identity を1本の設計 issue として再設計するのが妥当。

## 背景

### 統合元の指摘

#### A1 (branch_fold/cell_fold): union セル fn 実行の一本化欠如 (3件マージ)

- 場所: cell_fold.mbt:1029-1064 / branch_fold.mbt:304-357, 695-738
- (a) 値残余書きで fn が variant 数だけ再実行され枝別 old を見る (DR-138 §6b-1/3 違反、自コメントとも矛盾)
- (b) FiringLedger 未記録で parse相 + front_door淘汰 + effects射影の位相跨ぎ複数回実行
- (c) whole-cell only union で effects の old (単相fold) と result の old (momentary_observed) が食い違う
- 純関数では conformance で検出不能

#### C-1 (branch_fold/cell_fold): ガード欠落

- 場所: branch_fold.mbt:297-357 + cell_fold.mbt:1083
- union/単相 tuple セルで DR-127 §3/§3.2/§4.1/§4.2 の検査 (空座 ctx.old Reject / Sentinel Reject / fn出力適合 / SeatFault綴り) が丸ごと脱落
- 値残余経路の FnFailed/SeatFault 黙殺 (whole-cell は WriteFailed を返す非対称)
- 黙殺→WriteFailed 部分は即修相当だが、検査脱落の全面統合は本 issue に含める

#### 関連 (統合報告 P2 領域横断パターンより)

- R3-2/3 (resolve.mbt): union経路の非対称
- R4 m2/m3/m8: 関連する branch_fold/cell_fold の細部
- R6 F5 (front_door.mbt): union cull 呼び出し周辺の非対称

### 共通根本原因 (統合報告 P2)

1. `cull_union_cell` へ委譲した後 `continue` する構造が単相側の検査群を素通しにする
2. FiringLedger/席identity/tie判別が union経路で別定義になっている

### 対処方針

個別 patch ではなく、fold・ledger・identity を1本の設計として再構成する必要がある。アーキテクチャ級の変更。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] union/tuple セルの fn 実行が単相と同じく一本化される (variant 数分の再実行を排除)
- [ ] FiringLedger が union 経路でも記録され、位相跨ぎ複数回実行が解消する
- [ ] DR-127 §3/§3.2/§4.1/§4.2 の検査群が union/単相 tuple セルでも単相と同等に適用される
- [ ] 関連指摘 (R3-2/3, R4 m2/m3/m8, R6 F5) が本設計の中で解消または個別 issue へ切り出される
