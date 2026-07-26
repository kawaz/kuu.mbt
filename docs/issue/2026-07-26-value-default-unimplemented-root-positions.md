---
title: value:/default_fn 以外の位置 — option root / positional / command node の value: が全面未実装
status: open
category: bug
created: 2026-07-26T22:23:57+09:00
last_read:
open_entered: 2026-07-26T22:23:57+09:00
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

# value:/default_fn 以外の位置 — option root / positional / command node の value: が全面未実装

## 概要

or/seq child の value:/default: は 2026-07-26 に実装済み (literal_value resident)。しかし
option root / positional root / command node の `value:` は依然 unsupported key で弾かれる
(survey 実測 2026-07-26: 5 配置中 3 配置が malformed_definition のまま)。

## 背景

spec 上は schema/wire.schema.json `$defs.node` の同型規定 + DESIGN §5.2 で合法。実装には
ElementDef の literal 経路 (is_literal) を root 位置へ広げる設計判断が要る (root の default:
はラダー席なので、value: だけを literal にする位置別解釈になる — DR-018 配置原理)。また
schema の value は任意 JSON だが json_to_value が scalar のみという型差も未解決。

関連:
- src/kuu/wire_decode.mbt dec_option / dec_positional / dec_command
- src/internal/engine/lowering.mbt element_head

## 受け入れ条件

- [ ] option root / positional root / command node で value: が受理される (or/seq child と同型の literal 扱い)
- [ ] root の default: (ラダー席) との位置別解釈の違いが spec (DR-018 配置原理) と整合する形で実装される
- [ ] json_to_value の scalar-only 制約と schema の value: 任意 JSON の型差が解決される (または明示的にスコープ外として文書化される)

## TODO

<!-- wip 時のみ -->
