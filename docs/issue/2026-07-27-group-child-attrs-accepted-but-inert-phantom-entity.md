---
title: positional Group 子の repeat/optional/multiple が「通るが効かない」+ phantom accum entity が root に漏れる
status: open
category: bug
created: 2026-07-27T03:44:09+09:00
last_read: 2026-07-28T20:58:57+09:00
open_entered: 2026-07-27T03:44:09+09:00
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

# positional Group 子の repeat/optional/multiple が「通るが効かない」+ phantom accum entity が root に漏れる

## 概要

実測 (2026-07-27、survey-child-repeat)。`dec_positional_group` は inner を
`dec_positional` で再帰 decode するため child の `repeat`/`optional`/`multiple`
を受理するが、以下 2 点で意味論が伴わない:

1. **消費構造に効かない** — `lower_positional` の Group head は inner を
   `element_head` へ直送し `elem_repeat` を通さない
   (`src/internal/engine/lowering.mbt:1019-1062`)。3 属性とも通常 scalar と
   同じ 1 回消費として振る舞う。
2. **phantom accum entity が root scope に漏れる** — `ensure_entity_body` は
   child の `repeat`/`multiple` を見て accum entity を root scope に作るため、
   結果に仕様上存在しないはずのセルが混入する
   (`src/internal/engine/lowering.mbt:1225-1290`)。

## 背景

定義:

```json
{"positionals":[{"name":"group","repeat":{...},"positionals":[
  {"name":"x","repeat":...},{"name":"y"}
]}]}
```

args `[a, b]` を decode すると:

```json
{"group":[{"x":"a","y":"b"}], "x":[]}
```

root の `x:[]` は仕様上存在しないはずのセル。「decode を通すのに意味論が
効かない」は silent wrong answer で、`dec_or_leaf` 側の明示拒否より悪い状態。

対処方向 (裁定待ち、本 issue のスコープ外):

- (a) 短期: Group 子でもこれら 3 属性を明示 reject して `dec_or_leaf` と揃える
  (等価な definition-error)
- (b) 本命: child repeat/multiple の end-to-end 実装
  (issue `2026-07-26-dec-or-leaf-remaining-node-keys` の Phase 2-4 の一部として解消)

## 受け入れ条件

- [ ] (a) か (b) のどちらを先に入れるか裁定
- [ ] 選択した対処方向を実装し、上記の phantom セル漏れ・消費構造不整合が
      再現しないことをテストで確認

## 関連

- `docs/issue/2026-07-26-dec-or-leaf-remaining-node-keys.md` (調査結果の正本)
- `src/kuu/wire_decode.mbt` `dec_positional_group` (2791-2814)
- `src/internal/engine/lowering.mbt` (`lower_positional`, `ensure_entity_body`)
