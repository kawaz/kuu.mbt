---
title: separator 付き multiple 要素の env 値が separator 分割されない (DR-049 乖離)
status: open
category: bug
created: 2026-07-09T16:56:15+09:00
last_read:
open_entered: 2026-07-09T16:56:15+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: impl-prefilters worker (pre_filters 配線中)
---

# separator 付き multiple 要素の env 値が separator 分割されない (DR-049 乖離)

## 概要

DR-049 §2 は「env から来た値は string であり、要素の pieceProcessor を
通る。multiple 要素なら separator 分割も効く (発火 1 回の 1 引数と同じ
扱い)」と規定するが、`resolve_entity_raw` の env seat は
`env_map.get(k)` の生 string を `env_value` に渡すだけで separator 分割
を行わない。

## 背景

再現の輪郭 (未実測、コード確認のみ):

```
TAGS="a,b,c"
```

+ `multiple {accumulator: append, separator: ","}` で `["a","b","c"]`
にならず単一 piece 扱いになるはず。

対処: env seat で separator 分割 → 各 piece に pieceProcessor
(pre_filters → parse) → accumulator 畳みの経路を通す。issue
`separator-non-string-type-parse-gap` (SepArg 型 parse 欠如) と設計が
絡む可能性があるため着手時に相互参照。spec 側に env × separator の
conformance fixture 追加も必要。

由来: impl-prefilters worker が pre_filters 配線中に確認 (2026-07-09)。

## 受け入れ条件

- [ ] env seat の separator 付き multiple 要素が分割 → pieceProcessor
      → accumulator の経路を通る実装になっている
- [ ] env × separator の conformance fixture が spec 側に追加されている
- [ ] 上記 fixture が通ることを確認

## TODO

<!-- wip 時のみ -->

- [ ] 着手時に `separator-non-string-type-parse-gap` issue と設計の
      重なりを確認する
