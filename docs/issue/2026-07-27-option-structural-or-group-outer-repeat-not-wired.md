---
title: option structural Or/Group の outer repeat が受理されるが消費構造へ配線されない
status: open
category: bug
created: 2026-07-27T21:01:30+09:00
last_read:
open_entered: 2026-07-27T21:01:30+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: missing_operand 位相化の実装監査
---

# option structural Or/Group の outer repeat が受理されるが消費構造へ配線されない

## 概要

option 自身が structural `Or` または `Group` で outer `repeat` / `optional` を宣言すると、decode と entity/accumulator 構築は受理する一方、`inst_long` の `Or`/`Group` arm は `elem_repeat(e)` を呼ばず通常の単発 satellite を生成するため、宣言が accepted-but-ignored になる。

## 背景

missing_operand 位相化の実装監査で見つかった、定義は受理されるが CLI 消費に反映されない silent wrong answer の一種。

## 実装エビデンス

- `src/internal/engine/lowering.mbt:1590-1627`: `inst_long` の `Or` arm は `Scoped(e.name, Or(...))`、`Group` arm は `seq_value_node(e, items)` をそのまま `add_entry_greedy` し、Cell/ref arm のような `elem_repeat(e)` / `lower_repeat_head` / `GreedyRepeat` 経路を通らない。
- `src/internal/engine/lowering.mbt:3532-3558`: `collect_zero_progress` は `def.positionals` と commands の再帰だけを走査し、`def.options` の outer repeat head を検査しない。配線修正時に zero-progress option repeat が guard を迂回する。

## 影響

定義は受理され accumulator/entity も repeat 前提の形を持ち得るのに、CLI 消費は単発のままになる。definition-error にならない silent wrong answer。

## 受け入れ条件

- [ ] option structural `Or` / `Group` の outer repeat が Cell/ref と同じ repeat spine 契約へ配線される。
- [ ] repeat/optional の min/max/is_lazy が実際の消費回数・選好へ反映される。
- [ ] option outer repeat も `collect_zero_progress` 相当の検査対象になる。
- [ ] Or と Group の単発 baseline、bounded/unbounded、zero-progress を fixture/wbtest で固定する。

## 関連

- `docs/issue/2026-07-26-dec-or-leaf-remaining-node-keys.md`
- `docs/issue/2026-07-27-group-child-attrs-accepted-but-inert-phantom-entity.md`

観測と該当箇所は実物確認済み。実装方針は既存 repeat spine と option greedy の責務を再確認してから決めること。
