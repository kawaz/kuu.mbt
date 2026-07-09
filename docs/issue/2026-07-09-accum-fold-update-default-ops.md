---
title: build_result の ACCUMULATE fold が Update / Default op を解釈しない (実装未対応)
status: open
category: task
created: 2026-07-09T21:38:57+09:00
last_read:
open_entered: 2026-07-09T21:38:57+09:00
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

# build_result の ACCUMULATE fold が Update / Default op を解釈しない (実装未対応)

## 概要

`build_result` の ACCUMULATE 分岐 (`resolve.mbt` L354 付近、段 6 accumulator fold) は
Empty (クリア) と Unset (クリア + uncommitted 化 → sources=default、issue
`accum-filters-non-set-op-semantics` のサイクルで対応) を解釈するが、Update / Default
op は未解釈で placeholder 値 (`VBool(false)`) が累積配列に混入する。

- **Update**: old (その時点の累積状態) に transform を適用して書く (DR-077 §1 +
  DR-045/015 の合成で意味論は既に決まっている — 「未定義」ではなく実装未対応)。
  transform の型 (`T => T`) と累積状態 (`T[]`) の不一致は実行時 Err で自然に決まる。
  update 適用結果は filters (段 5) → post_filters (段 7) を通る (DR-077 §1
  「old → transform → filters → cell」、PIPELINE §3.2)
- **Default**: 明示の default 選択 (committed=true) — accum セルでは default 値
  ([] または宣言 default) へ戻す

## 背景

issue `accum-filters-non-set-op-semantics` の実装中 (2026-07-09) に impl-prefilters
worker が段 6 の op 未解釈として確認。同 issue は段 5 (filters 適用条件) + Unset fold
のみをスコープとし、Update/Default fold は本 issue に切り出した。

## 受け入れ条件

- [ ] ACCUMULATE fold で Update op が old + transform で正しく処理される
- [ ] ACCUMULATE fold で Default op が明示 default (committed=true) として処理される
- [ ] Update 適用結果が filters (段5) → post_filters (段7) を通る
- [ ] transform の型不一致が実行時 Err として自然に検出される
- [ ] spec 側に accum × update / accum × default 発火の conformance fixture が整備されている

## TODO

<!-- wip 時のみ -->

- [ ] spec 側の conformance fixture を先行整備 (発火の綴り・old の初期値・型不一致 Err の輪郭)
- [ ] 段 7 (累積後 post_filters、issue `accum-post-filters-stage7`) と実装箇所が近いため同時着手を検討
