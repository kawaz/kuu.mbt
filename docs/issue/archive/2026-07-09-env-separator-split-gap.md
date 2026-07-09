---
title: separator 付き multiple 要素の env 値が separator 分割されない (DR-049 乖離)
status: resolved
category: bug
created: 2026-07-09T16:56:15+09:00
last_read: 2026-07-09T23:41:25+09:00
open_entered: 2026-07-09T16:56:15+09:00
wip_entered: 2026-07-09T23:29:15+09:00
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-09T23:55:00+09:00
discard_reason:
pending_reason:
close_reason: ["DR-049 §2 どおり env seat の separator 分割 → pieceProcessor → accumulator を実装 (commit cbd42917d7b9278393fe400cf7883cc9b2e7baeb、push 後 SHA)。spec fixture fixtures/multiple-parse/env-separator-split.json (spec commit 93efbcf8e445b75ed871844baf1e33c05e9d3d4c) 追加済み・全 case green。受け入れ条件 3 点すべて達成。TODO にあった separator-non-string-type-parse-gap との重なりは前サイクルで SepArg 型 parse 実装済みのため解消済みだった。conformance: decoded=150 / ran_cases=382 / skipped=0 / mismatches=0、moon test 167 本全 pass、codex レビュー指摘なし。"]
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
