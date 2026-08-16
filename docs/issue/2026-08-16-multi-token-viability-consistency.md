---
title: 多トークン値スロットの viability 非一貫
status: open
category: design
created: 2026-08-16T14:14:07+09:00
last_read:
open_entered: 2026-08-16T14:14:07+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)
---

# 多トークン値スロットの viability 非一貫

## ⚠ spec 裁定待ち

## 概要 (C-4)

多トークン値スロットの viability が失敗様式で非一貫。

## 詳細

- 場所: src/internal/engine/eval.mbt:2578
- 2個目照合失敗 = viable (failure) 扱い
- 枯渇 = not viable (素通し success) 扱い
- この2つの失敗様式の扱いが非一貫

## 裁定が必要な点

DR-097 字面と DESIGN L438 のどちらに揃えるかの裁定が必要 (実測済み)。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] DR-097 と DESIGN L438 のどちらに揃えるか裁定する
- [ ] eval.mbt:2578 の viability 判定を裁定結果に合わせて修正する
