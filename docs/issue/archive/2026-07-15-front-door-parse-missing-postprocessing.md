---
title: front_door.parse が conformance 後段処理 (apply_requires_filter / promote_collision_ambiguous) を通さず spec 非準拠 outcome を返す
status: resolved
category: bug
created: 2026-07-15T20:20:54+09:00
last_read:
open_entered: 2026-07-15T20:20:54+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-16T13:49:37+09:00
discard_reason:
pending_reason:
close_reason: ["dr/MDR-005-front-door-api","implemented"]
blocked_by:
origin: kuu-cli PoC codex レビュー (統括起票)
---

# front_door.parse が conformance 後段処理 (apply_requires_filter / promote_collision_ambiguous) を通さず spec 非準拠 outcome を返す

## 概要

kuu-cli PoC の codex レビュー (2026-07-15) で発覚した dogfooding 発見の第 2 弾
(ekmap issue と同種の玄関 API gap)。`front_door.parse`
(`src/core/front_door.mbt:118-120`) は `parse_tree` の薄い wrapper だが、
conformance runner の本経路 (`json_conformance_wbtest.mbt:2923-2924` の
`run_case`) は `parse_tree` の結果に `apply_requires_filter` →
`promote_collision_ambiguous` を直列適用してから expect と比較している。
この 2 つの後処理は DR-053 の outcome 意味論の一部 (requires の経路成立
フィルタ / collision の ambiguous 昇格) であり、通さない `front_door.parse`
は spec 非準拠の outcome を返す。

MDR-005 は「正面玄関 3 契約は spec 語彙と一致」を謳うので、これは
front_door 側の実装漏れ。

## 背景

実害は codex レビューが kuu-cli バイナリで実機確認済み:

- `export-key/collision.json` — expected `ambiguous` のところ `success` を返す
- `inheritable-parse/basic.json` — expected `sub.ttl=30` のところ `sub:{}` を返す

さらに値源ラダー resolve (`inheritable` の `sub.ttl=30` が落ちる件) も
後段に含まれる可能性がある — `run_case` が `parse_tree` 後に何を適用して
いるかの全列挙が先。

同レビューで warnings の wire 射影 (`@depr:port` sentinel が effects に漏れ、
warnings が object 配列でない) も kuu-cli 側で指摘されており、
binds → warnings/effects 分離の射影素材 (conformance runner の該当処理) への
`front_door` 到達性も本 issue のスコープで検討する。

## 受け入れ条件

- [x] `run_case` の後段処理を全列挙し、DR-053 意味論に属するもの (vs
      fixture 比較のための射影) を区別する
      (裁定: apply_requires_filter = DR-047 §5 / promote_collision_ambiguous =
      DR-021 → DR-073 は parse 相に内包、値源ラダーは DR-104 §5 の相区分に
      忠実な独立関数 `resolve` として新設、2 段構成)
- [x] DR-053 意味論に属する後段を `front_door.parse` に取り込む
      (conformance runner は `front_door.parse` に乗り換えて二重適用を解消)
      (commit b3feaf0a: parse 拡張 + resolve 新設 + is_sentinel/warnings_structured
      の pub 化、commit 70fe5670: conformance runner 乗り換え、MDR-005 追記)
- [x] kuu-cli の実バイナリで `export-key/collision.json` → `ambiguous` /
      `inheritable-parse/basic.json` → `sub.ttl=30` を確認
      (kuu-cli commit 5c954b58、warnings 構造化 + `@depr` sentinel 除去も確認)
- [x] moon test 全 green + conformance mismatches=0
      (moon test 350/350、新規 wbtest 3 本。conformance decoded=272/ran_cases=661/
      skipped=0/mismatches=0 — runner 乗り換えで数字不変 = 新旧同値性の証明)

## TODO

<!-- wip 時のみ -->
