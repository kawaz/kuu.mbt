---
title: separator 付き multiple の非 string 型が型 parse を経由しない (SepArg = VStr 固定)
status: open
category: bug
created: 2026-07-09T16:18:40+09:00
last_read:
open_entered: 2026-07-09T16:18:40+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: impl-prefilters worker (pre_filters 配線の設計調査中)
---

# separator 付き multiple の非 string 型が型 parse を経由しない (SepArg = VStr 固定)

## 概要

`src/core/installer.mbt` の `elem_head` (L762-770 付近) の separator 分岐は
`e.ty` を見ず、separator が `Some` なら無条件で `SepArg` (piece を常に
`VStr` で bind) を構築する。このため `multiple` + `separator` + 非 string 型
(number / int / float / bool) の組み合わせで、各 piece が型 parse
(DR-034 pieceProcessor の parse 相) を一切経由せず string のまま cell に
入る。spec 上は piece ごとに pre → parse → post を通るべき (DR-034 §6.2)。

## 背景

再現の輪郭 (未実測、grep 根拠のみ):

```json
{"name":"ns","type":"number","multiple":{"accumulator":"append","separator":","}}
```

に `"1,2"` を渡すと `[1,2]` (VNum) ではなく `["1","2"]` (VStr) になるはず。
conformance fixture も number×separator の組み合わせが未整備
(`fixtures/multiple-parse/` は string のみ)。

対処案: `SepArg` に型情報 (`Ty` + `int_round` 等の config) を運搬し、piece
ごとに型 parse を通す。pre_filters 配線 (issue
`2026-07-09-pre-split-filters-execution-wiring`) の sep_binds 改修と隣接
するが、スコープ膨張を避けるため別 issue とする。spec 側に判別 fixture
(number×separator) の追加も必要。

由来: 2026-07-09 impl-prefilters worker が pre_filters 配線の設計調査中に
grep で発見 (実測未)。

## 受け入れ条件

- [ ] `multiple` + `separator` + 非 string 型の組み合わせで、各 piece が型
      parse を経由する実装になっている (grep + 実測で確認)
- [ ] number×separator 等の conformance fixture が spec 側に追加されている
- [ ] 上記 fixture が通ることを確認

## TODO

<!-- wip 時のみ -->
