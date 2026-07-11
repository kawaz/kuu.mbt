---
title: DR-089 type:none / type 省略の decode・実装対応
status: open
category: task
created: 2026-07-11T09:20:32+09:00
last_read:
open_entered: 2026-07-11T09:20:32+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 依頼元プロジェクト (kuu spec リポ)
---

# DR-089 type:none / type 省略の decode・実装対応

## 概要

spec DR-089 (spec commit 94f208e7) が type 省略 = none (値空間が空の node、消費は構造の関心で直交) を確定した。kuu.mbt 側でこの決定に対応する実装変更一式を行う。

## 背景

DR-089 により以下が確定している:

1. decoder の「values/or/ref が無い限り type 必須」を撤廃し、省略と `"none"` 明示の両方を受理する
2. none node の entity 表現 (値セルなし、committed/selected メタは ParserContext 相当に保持)
3. 消費は構造どおり (消費 0 の純トリガ / repeat + filter の食って捨てる)
4. 結果 (シンプルモード) 非掲載
5. none を requires 目的語にした宣言は definition-error (DR-089 §4、kind は invalid-range 系の既存語彙から選定)
6. committed 基準制約 (conflicts/exclusive、requires トリガ側) への参加

spec fixture (純トリガ / none×repeat / definition-error) は DR-089 波及節に記載されている。実装と同サイクルで spec 側に fixture 手配を依頼する必要がある。

関連: DR-089 / spec issue `typeless-option-default-semantics` (close 済み、経緯として参照)

## 受け入れ条件

- [ ] decoder が type 省略 と `type: none` 明示の両方を受理する
- [ ] none node の entity 表現が実装されている (値セルなし、committed/selected メタ保持)
- [ ] 消費が構造どおりに動作する (純トリガ / repeat+filter の食って捨てるパターン)
- [ ] シンプルモードの結果に none node が非掲載であることを確認
- [ ] none を requires 目的語にした宣言が definition-error として検出される (kind は invalid-range 系の既存語彙から選定)
- [ ] committed 基準制約 (conflicts/exclusive、requires トリガ側) に none node が正しく参加する
- [ ] spec fixture (純トリガ / none×repeat / definition-error) が spec 側で手配され、fixture green
- [ ] conformance mismatches=0 / skipped=0

## TODO

<!-- wip 時のみ -->
