---
title: pre_split_filters の実行配線 (decode 済み・未配線)
status: wip
category: task
created: 2026-07-09T10:25:35+09:00
last_read:
open_entered: 2026-07-09T10:25:35+09:00
wip_entered: 2026-07-09T15:32:44+09:00
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 依頼元プロジェクト kuu (spec リポ)
---

# pre_split_filters の実行配線 (decode 済み・未配線)

## 概要

filters registry 基盤 (commit 7f1b0c96) で ElemDef / fixture decode に pre_split_filters キーは追加済みだが、実行配線が無い。

**2026-07-09 裁定 (spec 一次資料で確定)**: 現実装の `pre_split_filters` は旧名・旧意味論 (DR-009 の「分割前全体」)。spec 正本 (wire.schema.json / DESIGN.md §6.2 / DR-034 / DR-062) は **`pre_filters`** に改名済みで、適用位置は **separator 分割後の各 piece 単位・type.parse 直前** (pieceProcessor の pre 相)。single は長さ 1 縮退で同じ管。spec 側の旧記述残骸 (PIPELINE.md) は spec commit 3631b211 で追従済み。

よって本 issue の作業は (a) rename (ElemDef / decode キーとも pre_filters へ)、(b) 各 piece の parse 直前への FilterChain[String,String] 配線、の 2 本。

## 背景

issue filters-registry-foundation (2026-07-09) の受け入れ条件②「DR-009 の 3 段 chain (pre_split / each / post) の宣言 decode と実行配線ができている」のうち、decode は済んだが実行配線が残っている。dr066-path worker の報告より。

## 受け入れ条件

- [ ] ElemDef / fixture decode のキーが spec 正本どおり `pre_filters` に rename されている
- [ ] piece 確定 → type.parse の間に pre_filters 適用点が漏れなく通っている (eval 4 関数の値アーム + matcher の eq-split / short_val 経路 + sep_binds 分割後の各 piece)。漏れの機械検査 (grep 条件) を報告に添える
- [ ] reject は kind=filter (Held/KFilter) で表面化する
- [ ] wbtest + conformance fixture (per-piece 判別 / parse 救済 / reject / single 縮退 / eq-split / short / env の輪郭) が揃っている

## TODO

<!-- wip 時のみ -->
