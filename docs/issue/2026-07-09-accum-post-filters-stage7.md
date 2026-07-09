---
title: accum セルの post_filters (DR-009 段 7、累積後 Acc→Acc) の配線
status: open
category: design
created: 2026-07-09T17:11:11+09:00
last_read:
open_entered: 2026-07-09T17:11:11+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: accum-filters-recon 調査 (2026-07-09、4 次元並列) / issue accum-entity-filters-wiring からの段 7 切り出し
---

# accum セルの post_filters (DR-009 段 7、累積後 Acc→Acc) の配線

## 概要

accum セルへの `post_filters` (DR-009 段 7、累積後の最終値 Acc→Acc への self-map) を配線する。build_result 層の設計変更が前提になる。

## 背景

issue `accum-entity-filters-wiring` (2026-07-09) から段 7 部分を切り出した。post_filters の「累積後適用」はエンティティ / Binding 単位の `apply_entity_filters` では原理的に実現できない。累積後の配列が組み上がるのは build_result の ACCUMULATE fold であり (`resolve.mbt` L364-385)、apply_entity_filters は個々の要素処理時点でしか走らないため、畳み終わった後の値に対して filter をかける経路が存在しない。

配線には以下が必要:

- `AccumCell` 構造体 (現状 path / name / collector のみ) に post_filters を運ぶフィールド拡張
- build_result 側での `apply_filter_chain` 呼び出し追加 (collector と同じ位置。build_result → filters.mbt のモジュール依存が新たに増えるため、設計上の可否確認込み)
- 配列相当の filter (sort / unique / T[]→T[] 系) が現状 registry に無い — post_filters at accum を検証する fixture はこれらが揃うまで書けない
- 適用順序は accumulator → collector → post_filters (DR-040 の count 上限例から導出可能: post_filters は「畳んだ最終値 U への self-map」)

由来: accum-filters-recon 調査 (2026-07-09、4 次元並列)。spec 側の関連 issue: `design-6-2-piece-post-label-collision` (post_filters ラベル衝突 — fixture 文言はその解消後の語彙に揃えること)。

## 未裁定の論点 (着手時に kawaz 確認 or 導出)

- [ ] post_filters を配列全体に通すか要素ごとか (DR-009 段 7「累積後の最終値」の解釈 — collector 後の U への self-map 解釈なら全体で一意)
- [ ] Empty op (累積クリア) 後の空配列に post_filters を通すか
- [ ] 実装層は build_result 拡張で確定か (他の層に置く選択肢が残っていないか)

## 受け入れ条件

- [ ] 未裁定の論点 3 点が裁定される (kawaz 確認または一次資料からの導出)
- [ ] `AccumCell` への post_filters 配線が実装され、build_result 側で collector 後に `apply_filter_chain` が呼ばれる
- [ ] 配列相当の filter (sort / unique 等) が registry に揃い、post_filters at accum を検証する fixture が書ける
- [ ] fixture のラベル文言が `design-6-2-piece-post-label-collision` の解消後の語彙と整合する
