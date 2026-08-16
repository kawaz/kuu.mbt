---
title: absent vs null (momentary old) の spec 語彙統一裁定
status: open
category: design
created: 2026-08-16T14:16:55+09:00
last_read:
open_entered: 2026-08-16T14:16:55+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt 全コードレビュー
---

# absent vs null (momentary old) の spec 語彙統一裁定

## ⚠ spec 裁定待ち

## 概要 (R4 m4)

union/tuple セルの effects 側 old 表現について、absent と null (momentary_observed) の使い分けが spec 語彙として統一されていない。

## 背景

- wbtest が absent 側の挙動を pin 済み
- spec (DR-138 等) の語彙が absent vs null をどちらで規定するか統一されていない

## 裁定が必要な点

absent vs null (momentary old) のどちらを正とするか、spec語彙の統一裁定が必要。union fold/ledger/identity 統合再設計 issue (2026-08-16-union-fold-ledger-identity-redesign) と関連領域が重なるため、着手時は同issueとの整合を確認する。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] absent vs null (momentary old) の spec 語彙が DR で統一裁定される
