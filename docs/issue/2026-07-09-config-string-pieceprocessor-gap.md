---
title: config の string 値が pieceProcessor (pre_filters → parse) を通らない (DR-050 乖離)
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

# config の string 値が pieceProcessor (pre_filters → parse) を通らない (DR-050 乖離)

## 概要

DR-050 §値の型は「string → CLI / env と完全に同一の全段 pipeline
(pre_filters → parse → post_filters、DR-034 / DR-049)」と規定するが、
`config_to_value` (`value.mbt`) は pre_filters を一切通さない。

## 背景

env 経路は 2026-07-09 の pre_filters 配線 (commit 321f542c) で
`env_value` に適用点を得たが、config の string 値経路は未配線のまま。

再現の輪郭 (未実測、コード確認のみ):

```json
{"port": " 8080 "}
```

のような string 供給で pre_filters の trim が効かず parse reject に
なるはず。

対処: config の string 値も env_value 相当の窓口 (pre_filters → 型 parse)
を通す。spec 側に config string × pre_filters の conformance fixture
追加も必要。

由来: impl-prefilters worker が pre_filters 配線中に確認 (2026-07-09)。

## 受け入れ条件

- [ ] config の string 値が env_value と同じ pre_filters → parse
      pipeline を経由する実装になっている
- [ ] config string × pre_filters の conformance fixture が spec 側に
      追加されている
- [ ] 上記 fixture が通ることを確認

## TODO

<!-- wip 時のみ -->
