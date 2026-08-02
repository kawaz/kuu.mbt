---
title: duplicate raw command の複数入場で ordinal marker が occurrence を区別できない
status: open
category: bug
created: 2026-08-02T20:18:00+09:00
last_read:
open_entered: 2026-08-02T20:18:00+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 2026-08-02-dup-label-scope-resolve-gap
---

# duplicate raw command の複数入場で ordinal marker が occurrence を区別できない

## 概要

duplicate raw command で同じ raw command を一読解中に複数回入場する場合
(例: `go --a x go --b y` のように `go` を go1/go2 として複数回呼ぶ)、
同一 raw scope path に ordinal marker が複数並んでしまい、単一 ordinal
lookup が全 binding を一方の枝 (どちらか片方の入場 occurrence) へ寄せて
しまう。

期待挙動: 各 duplicate raw command の入場 occurrence ごとに binding を
正しく帰属させ、resolve / result / sources / effects / constraints が
それぞれの command 枝へ正しく射影されること。

表現力削減 (= 複数 occurrence をひとつに握りつぶす、ordinal を諦める等)
は禁止。marker を区間化する (occurrence の開始/終了を明示する) か、
occurrence identity を導入して各 binding が属する入場 occurrence を
一意に特定できるようにする対応が必要。

## 背景

spec リポ側の label scope resolve gap 調査 (2026-08-02-dup-label-scope-resolve-gap)
から派生。duplicate raw command の複数入場自体は仕様上合法な操作だが、
実装 (kuu.mbt) 側の ordinal marker 機構が「同一 raw scope path に複数回
入場する」ケースを想定しておらず、単一 ordinal lookup では occurrence の
区別がつかない。

## 受け入れ条件

- [ ] go1 (1 回目の `go` 入場) の binding が go1 の resolve/result/sources/effects/constraints に正しく射影される
- [ ] go2 (2 回目の `go` 入場) の binding が go2 側に正しく射影される (go1 側に誤って寄らない)
- [ ] 表現力を落とさない (全 occurrence を区別可能なまま保持する)

## TODO

<!-- wip 時のみ -->
