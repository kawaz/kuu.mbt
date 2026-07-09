---
title: post_filters reject の kind/argv_pos が未配線 (KParse ハードコード + at_pos=-1)
status: resolved
category: bug
created: 2026-07-09T11:46:03+09:00
last_read:
open_entered: 2026-07-09T11:46:03+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-09T11:58:20+09:00
discard_reason:
pending_reason:
close_reason: ["implemented","done:filter_err 新設 (ladder_err の KFilter 版) で apply_entity_filters の reject 2 箇所を置換、env/config seat の KParse は不変 (commit 671cef55)","done:at_pos は harness の resolve 呼び出し (do_resolve_pe/resolve_tree 3経路) に argv.length() を配線、resolve 層エラーは完了後位置=constraint と同規約","done:spec 側 fixture (count-parse/post-filter-range.json over-range, value-typing/post-filter-reject.json) で kind=filter + final position を pin 済み (spec commit c4d48573)、conformance 130/338/0","note:reason 細分化は Schema 実体化 (spec issue schema-materialization-and-reason-descriptors) の管掌のまま"]
blocked_by:
origin: 依頼元プロジェクト kuu (spec リポ)
---

# post_filters reject の kind/argv_pos が未配線 (KParse ハードコード + at_pos=-1)

## 概要

post_filters の reject が `{kind: parse, argv_pos: -1}` で報告される。DR-053 §2 / DR-066 §3 の期待は kind=filter。

## 背景

spec 側 fixture 実測 (2026-07-09、main = 4c02678f 世代) で判明:

- resolve.mbt:908 付近: apply_entity_filters の reject 報告が ladder_err 経由で `kind: KParse` をハードコード。KFilter は実装済みだが post_filters 経路に未配線
- resolve.mbt:1380 付近: resolve_scope/resolve_entity の at_pos がデフォルト -1 のまま伝播

fixture-batch2 worker の実測報告 (2026-07-09) に由来。

## 修正方針

- kind: KFilter へ (DR-053 §2「filter = a post_filter reject」の明文どおり)
- argv_pos: resolve 層エラーの既存規約に合わせ **final position (toks.length())** — ladder_err 自身のコメント「env/config seat errors surface after the path completed, the same conceptual point eval_constraints evaluates at」と同じ層の判断。呼び出し元が実際の toks.length() を渡すよう配線 (harness の resolve 呼び出し含む)
- reason の細分化 (filter_rejected → too_small/too_large 等) は本 issue の射程外 (Schema 実体化 = spec issue schema-materialization-and-reason-descriptors の管掌)

## 待ちの fixture

spec ws に未コミットで待機中:

- count-parse/post-filter-range.json の over-range-rejected
- value-typing/post-filter-reject.json

期待値 {kind: filter} は正、argv_pos は本修正の final position 仕様に合わせて調整して land 予定。

## 受け入れ条件

- [x] apply_entity_filters の reject 報告が kind: KFilter を返す
- [x] resolve_scope/resolve_entity の post_filters reject が正しい argv_pos (final position = toks.length()) を返す
- [x] spec ws 待機中の 2 fixture (count-parse/post-filter-range.json, value-typing/post-filter-reject.json) が期待通り green になる
