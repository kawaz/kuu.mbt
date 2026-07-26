---
title: has_commands 分岐そのものを廃止し sources 射影を flat/tree で統一する
status: open
category: design
created: 2026-07-26T13:22:20+09:00
last_read:
open_entered: 2026-07-26T13:22:20+09:00
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

# has_commands 分岐そのものを廃止し sources 射影を flat/tree で統一する

## 概要

`result_sources` (`src/kuu/resolve.mbt`) は `has_commands(sc)` で
`collect_sources_flat` / `collect_sources_tree` に実装を分岐している。
先行 issue `2026-07-25-sources-projection-skips-export-key-under-commands`
(export_key 未適用バグ) の修正でキー体系の差は解消したが、以下 2 点の差分は
意図的に残された (根治は別立てとする判断):

1. **未発火セルの default フォールバック**: flat 経路にはあるが tree 経路には
   元々存在しない、という前提だったが、修正後は accum セル分だけ tree 側にも
   フォールバックを追加した (0 回発火 accum セルの対応)。flat / tree 双方の
   フォールバック実装が別コードパスのまま並存している
2. **path を常に `[]` にする挙動**: tree 経路は command を持たない定義でも
   `has_commands` が false なら flat を通るため顕在化しないが、
   `front_door.mbt` の `interpretation_has_source` は「全 path が空なら
   flat とみなす」ヒューリスティック (`flat_projection`) で tree/flat を
   事後判別しており、この判別ロジック自体が両経路併存の負債

## 背景

先行 issue の export_key 修正で「透過ラベルを落とす」変更を入れたため、
「command を持つのに全 path が空」という状態が新たに成立しうるようになった
(透過昇格された scope は path セグメントを残さないため)。現状の ambiguous 系
fixture はどれも command を持たないため未露見だが、`interpretation_has_source`
の `flat_projection` ヒューリスティックが誤判定するリスクが増えている。

根治には `sources` の path 軸の意味論を flat/tree で統一する設計判断が要る
(= 「先食い/背骨」等の既存 DR 系との整合を検討する必要がある)。単純な
実装統合ではなく設計判断を伴うため、先行 issue から切り出して別立てとした。

## 該当箇所

- `src/kuu/resolve.mbt` の `result_sources` / `collect_sources_flat` /
  `collect_sources_tree`
- `src/kuu/front_door.mbt` の `interpretation_has_source`
  (`flat_projection` ヒューリスティックによる事後判別)

## 受け入れ条件

- [ ] `has_commands` 分岐の要否を設計判断として決める (統一する/しない)
- [ ] 統一する場合、`interpretation_has_source` の `flat_projection`
      ヒューリスティックが不要になることを確認する

## 関連

- 先行 issue: `docs/issue/archive/2026-07-25-sources-projection-skips-export-key-under-commands.md`
  (export_key 未適用バグの修正元、本 issue はそこからの切り出し)
