---
title: DR-089 type:none / type 省略の decode・実装対応
status: resolved
category: task
created: 2026-07-11T09:20:32+09:00
last_read: 2026-07-11T09:25:36+09:00
open_entered: 2026-07-11T09:20:32+09:00
wip_entered: 2026-07-11T09:26:22+09:00
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-11T10:02:00+09:00
discard_reason:
pending_reason:
close_reason: ["dr/DR-089","implemented"]
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

- [x] decoder が type 省略 と `type: none` 明示の両方を受理する
- [x] none node の entity 表現が実装されている (値セルなし、committed/selected メタ保持)
- [x] 消費が構造どおりに動作する (純トリガ / repeat+filter の食って捨てるパターン)
- [x] シンプルモードの結果に none node が非掲載であることを確認
- [x] none を requires 目的語にした宣言が definition-error として検出される (kind は invalid-range 系の既存語彙から選定)
- [x] committed 基準制約 (conflicts/exclusive、requires トリガ側) に none node が正しく参加する
- [x] spec fixture (純トリガ / none×repeat / definition-error) が spec 側で手配され、fixture green
- [x] conformance mismatches=0 / skipped=0

## 解決

commit ed4dee87 で TNone 実装完了:

- decoder の type 省略 / 明示 `type: none` を受理 (旧 type 必須と positional の TStr 既定を撤廃)
- 純トリガ (long sugar)
- NoneCell により result / sources / effects を全非掲載 (観測は ParserContext / explains 層。effects 非掲載は team-lead 裁定)
- committed 基準制約への参加
- requires 目的語・env/config_key/inherit 宣言は定義時 definition-error

検証: spec fixture 3 本 6 case (spec 6028cccb) green、conformance decoded=182 / ran_cases=472 / skipped=0 / mismatches=0、moon test 227 本。
