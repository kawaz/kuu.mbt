---
title: unbounded repeat{min:2} の min 未達で failure の errors が空になる (bounded は held error を emit)
status: open
category: bug
created: 2026-07-05T22:06:18+09:00
last_read:
open_entered: 2026-07-05T22:06:18+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (docs/decisions/DR-053, DR-065, docs/CONFORMANCE.md §2)
---

# unbounded repeat{min:2} の min 未達で failure の errors が空になる (bounded は held error を emit)

## 概要

unbounded な `repeat{min:2}` (max 無し) が min 未達 (argv `[a]` の 1 個のみ)
で failure になるケースで、slice の現行実装は `errors` が空のまま
failure を返す。

同型の min 未達でも bounded (`min:2, max:2`) は held error
(missing operand) を emit する (`phase14:71`)。差は `max` の有無だけで、
unbounded 側は `phase14:34` が「空 errors 前提の fail: no complete parse」
として凍結されている。

kuu spec (DR-053/065、`docs/CONFORMANCE.md` §2) は構造的必須の不成立
(= min 未達) で `missing_operand` の held error が必須と定めている。
`fixtures/repeat-parse/min2-standalone.json` (kawaz/kuu 側) は既に
仕様準拠の値 (`element`/`argv_pos`/`kind`/`reason`) で先行しているため、
parse runner がこの領域を転写した時点で divergence として顕在化する
見込み。

## 背景

同種の「failure の errors が空になる」問題は `2026-07-05-structural-failure-empty-errors.md`
(トークン枯渇・残余トークン系) で既に起票済み。本件は unbounded repeat の
min 未達というもう 1 つの経路で同じ症状 (held error 未捕捉) が出ている
ケース。

原因仮説 (裏取り前提のフラグ、実装判断は当事者セッションに委ねる):
無制限 repeat の Ref 再帰 lowering 経路が min 未達時の held ParseError を
落としており、有界 (BoundedTail) 経路は emit している。この仮説の裏取り
と、該当するなら「構造的失敗の ParseError 合成」という同種の修正が
必要か (= 2026-07-05 に `structural-failure-empty-errors` 系で行った修正
の再適用パターンに当たるか) は、このリポ側で確認してほしい。

一次資料:

- `kawaz/kuu` main の `docs/decisions/DR-053-parse-outcome-structure.md`
  (outcome union / 全保持の errors)
- `kawaz/kuu` main の `docs/decisions/DR-065-conformance-fixture-format.md`
  §3 (`kind` の割当規約)
- `kawaz/kuu` main の `docs/CONFORMANCE.md` §2 (failure の `errors` 形状)
- `kawaz/kuu` main の `fixtures/repeat-parse/min2-standalone.json`
  (仕様準拠の期待値、min 未達で held error あり)
- slice の `phase14:34` (unbounded repeat min 未達、現状は空 errors 前提で
  凍結)
- slice の `phase14:71` (bounded repeat min 未達、held error あり = 対比
  対象)

## 受け入れ条件

- [ ] unbounded `repeat{min:2}` の min 未達 (argv `[a]`) で、slice の
      failure が bounded 側と同様に held error (`missing_operand`) を
      `errors` に持つようになる
- [ ] `phase14:34` の期待値を仕様準拠 (空 errors 前提を撤回) に更新し、
      fixture runner / test が更新後の期待値で PASS する
- [ ] 原因仮説 (Ref 再帰 lowering 経路での held ParseError 欠落) の裏取り
      結果を本 issue または関連 DR/journal に残す
