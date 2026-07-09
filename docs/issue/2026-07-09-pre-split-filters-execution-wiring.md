---
title: pre_split_filters の実行配線 (decode 済み・未配線)
status: open
category: task
created: 2026-07-09T10:25:35+09:00
last_read:
open_entered: 2026-07-09T10:25:35+09:00
wip_entered:
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

filters registry 基盤 (commit 7f1b0c96) で ElemDef / fixture decode に pre_split_filters キーは追加済みだが、実行配線が無い。DR-009 の段 2 (分割前の raw string 全体への string→string 適用、trim / regex_match 等) は、値プリミティブがトークンを消費する全箇所 (eval.mbt の各評価アーム、matcher.mbt の eq-split / short-combine) への配線が必要で影響範囲が広い。

## 背景

issue filters-registry-foundation (2026-07-09) の受け入れ条件②「DR-009 の 3 段 chain (pre_split / each / post) の宣言 decode と実行配線ができている」のうち、decode は済んだが実行配線が残っている。dr066-path worker の報告より。

## 受け入れ条件

- [ ] トークン消費 → type.parse の間に pre_split_filters 適用点を一元化できる縫い目を探す (消費箇所ごとに散らすと漏れる)
- [ ] wbtest + conformance fixture (trim 適用の輪郭) が揃っている

## TODO

<!-- wip 時のみ -->
