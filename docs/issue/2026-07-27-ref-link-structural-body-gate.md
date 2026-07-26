---
title: ref+link / structural body (or/seq/Group) + link が invalid-range で塞がれている (spec 上は合法、解除条件付き)
status: open
category: design
created: 2026-07-27T00:29:04+09:00
last_read:
open_entered: 2026-07-27T00:29:04+09:00
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

# ref+link / structural body (or/seq/Group) + link が invalid-range で塞がれている (spec 上は合法、解除条件付き)

## 概要

DR-029 は ref (定義継承) と link (値同期) を直交と規定し併用は合法。しかし
2026-07-26 の link source 実装では、link 要素の body が Cell (単純値) でない
場合 — ref 参照、inline or/seq、positional Group — を pre-fixpoint の
definition-error invalid-range で明示拒否した (silent wrong answer 回避の
一時 gate、wbtest pin 済み)。

## 背景

理由: ref は template leaf 名 + Scoped を生成するため、bare-cell route の
key==entry name 一致で target へ写せない。

解除条件:
- (a) 単一 leaf の参照側 wrapper scope 除去 + leaf identity から target への route
- (b) 複合 ref/or/seq 用に複数 child Binding を 1 つの target 値として運ぶ
  aggregate carrier 設計 (単純な全 Binding rename は操作列/結果型を壊す)

両系統の実装後、ref+link invalid-range wbtest を合法成功テストへ置換する。

関連: `src/internal/engine/lowering.mbt` の gate、DR-029。

## 受け入れ条件

- [ ] 単一 leaf 参照側の wrapper scope 除去 + leaf identity → target route が実装されている (解除条件 a)
- [ ] 複合 ref/or/seq 用の aggregate carrier 設計が実装されている (解除条件 b)
- [ ] ref+link の invalid-range wbtest が合法成功テストへ置換されている

## TODO

<!-- wip 時のみ -->
