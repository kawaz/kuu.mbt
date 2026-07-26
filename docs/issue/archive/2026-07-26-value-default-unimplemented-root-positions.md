---
title: value:/default_fn 以外の位置 — option root / positional / command node の value: が全面未実装
status: resolved
category: bug
created: 2026-07-26T22:23:57+09:00
last_read:
open_entered: 2026-07-26T22:23:57+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-27T02:03:49+09:00
discard_reason:
pending_reason:
close_reason: ["implemented:option root / positional root の value: を実装 (commit 4da51dd6)、child value: とは別機構 (const_values carrier)", "spun-off:command node の value: は carrier 不在 + 意味論未規定のため別 issue へ分離 (統括承認待ちで起票済み)"]
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

- [x] option root / positional root で value: が受理される — ただし or/seq child と「同型の literal 扱い」ではなく別機構。child の value: は消費文法上のノード (`is_literal` + `literal_value`) だが、root の value: は消費文法に一切現れずセル初期化位相にだけ座る (DESIGN §11.4「const は席ではないので序列に参加しない」)。carrier も別 (`const_values`)。command node は carrier 不在 + 意味論未規定のため別 issue へ分離 (統括承認待ちで起票済み)
- [x] root の default: (ラダー席) との位置別解釈の違いが DR-018 配置原理と整合 — 実効位置は cli > env > config > inherit > const > default。上位席は「供給」なので const を上書きし、default は「無い時に埋める」充填なので const が居るセルに到達しない
- [x] json_to_value の scalar-only 制約 — scalar のみ対応、非 scalar (object/array literal) は decode で明示エラー。全 JSON 対応 (Value への複合型追加) は明示的にスコープ外

追加した definition-error gate 2 本:
- 値セルを持たない構造子 wrapper (or/seq) への value: → invalid-range
- scalar セルへの配列 literal → invalid-range (default 側と同じ形検査)

検証: KUU_FIXTURES 付き moon test で 538 pass / mismatches=0、just lint green (fresh clean run)。
spec fixture 3 本 (fixtures/value-sources/const-root-*.json) を kawaz/kuu へ commit 済み
(push は統括の lockstep window 待ち)。
