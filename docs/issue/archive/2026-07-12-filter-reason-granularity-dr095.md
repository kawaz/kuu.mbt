---
title: filter 失敗 reason の細粒度化 — filter_rejected 潰しを DR-095 の descriptor 宣言に追従
status: resolved
category: task
created: 2026-07-12T01:31:44+09:00
last_read:
open_entered: 2026-07-12T01:31:44+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-12T04:44:44+09:00
discard_reason:
pending_reason:
close_reason: ["implemented: FilterDescriptor に reasons 宣言追加、apply_filter_chain の Err を (reason, message) 化 (kuu.mbt commit 46466cf9)","implemented: non_empty→empty_value / in_range→too_small・too_large / regex_match→pattern_no_match の細粒度 emit、宣言外の防御的失敗は filter_rejected fallback","implemented: emit ⊆ 宣言集合の subset 不変を wbtest で固定","done: spec fixture 側も 10 pin + why を DR-095 語彙へ更新 (spec commit 175c9795)、pin bump 73c014e2、CI success 確認済み","done: conformance 194/503/0/0、moon test 300 本、SCH-Q4a の導出裁定は実装まで完遂"]
blocked_by:
origin: kuu (spec リポ)
---

# filter 失敗 reason の細粒度化 — filter_rejected 潰しを DR-095 の descriptor 宣言に追従

## 概要

`apply_filter_chain` (`src/core/filters.mbt`、`pub fn apply_filter_chain` 内、`Err(("filter_rejected", msg))` の行) は、組み込み filter が返す全ての `Err` を `filter_rejected` という単一 reason に潰している。spec 側の DR-095 は組み込み filter の reason を descriptor 単位で確定済み (例: `in_range` → `too_small`/`too_large`、`regex_match` → `pattern_no_match`、`non_empty` → `empty_value`)。この宣言に追従する形で reason を細粒度化する。

## 背景

- spec は DR-095 で filter ごとの reason 集合を descriptor レベルで宣言している。実装側 (`apply_filter_chain`) は各 filter の `Err` を区別せず `filter_rejected` 1 種類に潰しており、宣言と実装が乖離している。
- fixture 上は reason が optional 検証のため、現状で conformance が非準拠になっているわけではない。ただし細粒度化しないと、typo 検出・完備チェック (DR-066 §2) が本来の意味で機能しない。
- 導出裁定 SCH-Q4a: spec-as-core 原則 + ドラフト期の破壊変更許容から導出した裁定 (kawaz の明示裁定はまだ無いので、着手前に温度感確認を推奨)。`FilterDescriptor` に `reasons` を追加し、各 filter の `run` の `Err` arm を `(reason, message)` を返す形に変更する破壊的変更で spec に追従する方針。
- 前提: 同一 workspace で走行中の impl-required (DR-093 required 実装) が完了した後に着手する (1 workspace 1 writer の運用ルールのため)。

## 受け入れ条件

- [ ] `FilterDescriptor` (descriptor 定義箇所) に `reasons` フィールドを追加する
- [ ] 組み込み filter の `run` が emit する reason が DR-095 の宣言集合の subset になっている
- [ ] conformance テストが green

## 関連

- spec 側 DR-095 §5 (組み込み filter の reason 宣言)
- spec 側 DR-066 §2 (reason の typo 検出・完備チェック)
- spec 側 DR-094
- SCH-Q4a (導出裁定、kawaz 未確認)

## TODO

<!-- wip 時のみ -->
