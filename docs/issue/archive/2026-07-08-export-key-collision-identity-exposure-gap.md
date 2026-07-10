---
title: find_export_collisions が identity 露出 (ek 未登録) 由来の衝突を見逃す
status: resolved
category: design
created: 2026-07-08T12:11:39+09:00
last_read:
open_entered: 2026-07-08T12:11:39+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-10T21:50:19+09:00
discard_reason:
pending_reason:
close_reason: ["implemented: kuu.mbt commit 6de458e8 で exposed_key_of による解決規則一元化 (find_export_collisions が mapped 同士しか見ず apply_export_keys と別規則だった不整合の解消、build_interpretations / promote_collision_ambiguous の drop 判定も統一)。導出根拠: DR-052 §1 (未指定 = name 由来キーで露出という解決値、null のみ透過) + DESIGN §15.5 (衝突基準は解決後の露出キー一致、経路非区別)。spec fixture export-key/collision-identity.json 3 case (spec 6b59dc91) で pin、conformance decoded=176 / ran_cases=458 / skipped=0 / mismatches=0、moon test 205 本 (identity×identity 非衝突の対極 wbtest 込み)。"]
blocked_by:
origin: kuu (spec リポ) の Batch-2 監査 (commit c7bdbe1f)
---

# find_export_collisions が identity 露出 (ek 未登録) 由来の衝突を見逃す

## 概要

`find_export_collisions` (src/core/resolve.mbt) は ExportKey (`ek`) が登録済みの
binding 同士の co-exposure しか検出しない。`ek.get` が `None` を返す binding
(= identity 露出、自然名がそのまま露出しているケース) はグルーピング対象外になる
ため、以下のケースを見逃す:

- identity 露出の entity と、別 entity の mapped export_key が同じ露出 key に
  衝突するケース
- `promote_collision_ambiguous` のドロップ判定も同様に mapped 側の binding しか
  見ておらず、identity 露出側は判定対象に入らない

## 背景

Batch-2 (c7bdbe1f) の監査で発見。fixture (`export-key/collision.json`) は現状
「両方 mapped の co-exposure」しか固定しておらず、mapped export_key と identity
(自然名) 露出との衝突が仕様上 collision に含まれるべきかどうかが fixture からは
判定できない。DR-052 / DR-073 が export-key の衝突判定範囲を規定しているはずだが、
identity 露出込みのケースまで明示しているかは未確認 (精読要)。

## 受け入れ条件

- [ ] DR-052 / DR-073 (spec リポ側) を精読し、identity 露出 (ek 未登録) と
      mapped export_key の衝突が「collision」として扱われるべき仕様かを確認する
- [ ] 含まれる場合: `find_export_collisions` を identity 露出込みの grouping に
      拡張し、`promote_collision_ambiguous` のドロップ判定も同様に拡張する。
      あわせて fixture (`export-key/collision.json` 等) に mapped vs 自然名の
      衝突ケースを追加する (spec 側 fixture 追加が必要な場合はそちらも)
- [ ] 含まれない場合: 本 issue を `discarded` として close し、理由 (= 仕様上
      対象外と判断した DR の根拠) を close_reason に記録する

## TODO

<!-- wip 時のみ -->

## 追記 (2026-07-08): id 裁定との関係

kawaz の同日裁定「内部 id は #{seq} 系で user ns と分離」は**本 issue とは別軸** — 本 issue は「ユーザ宣言の export_key vs 別要素の自然名」で、両方ユーザ宣言の露出 key の衝突。team-lead の意見は「露出面で同じ key を 2 実体が主張する事実は mapped か natural かに依らず collision に含めるべき (find_export_collisions を露出 key で一様に group する)」だが、この含否自体は未裁定のまま。DR-052/073 精読 + spec 判断が受け入れ条件である点は不変。

