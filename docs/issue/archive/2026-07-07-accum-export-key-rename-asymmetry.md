---
title: accum セルの export_key rename が未対応 (resolve 層の非対称)
status: resolved
category: design
created: 2026-07-07T23:36:14+09:00
last_read:
open_entered: 2026-07-07T23:36:14+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-10T22:14:47+09:00
discard_reason:
pending_reason:
close_reason: ["implemented: kuu.mbt commit 09ae9d92 で accum_cells / CmdSat scope label / proj_sources に exposed_key_of (DR-052 §1 の解決規則) を適用し、export_key rename 付き accum セルが fold 照合に失敗して last-wins scalar へ縮退するバグと、sources 射影の rename 非対応 (同根、rename.json が sources 未検証で潜伏) を解消。spec fixture export-key/rename-multiple.json 3 case (spec 70890eb1、null 透過×accum と 0 発火 [] の rename キー出力を含む) で pin。conformance decoded=177 / ran_cases=461 / skipped=0 / mismatches=0、moon test 209 本。"]
blocked_by:
origin: resolve-port3 の移植報告からの申し送り
---

# accum セルの export_key rename が未対応 (resolve 層の非対称)

## 概要

`src/core/resolve.mbt` (ab4b5444) にて、`default_cells` は `apply_export_to_defaults`
で `export_key` マップ済みのキーを渡すのに対し、`accum_cells` はマップせず素の name を
渡している非対称がある (slice の `helpers_wbtest.mbt` の呼び出しパターンに合わせた移植)。

accum セル (flatten/append) を持つ要素に `export_key` rename が付いた場合、named 側の
キーとの突き合わせが不整合になる可能性がある。

## 背景

resolve-port3 の移植作業中に発見。現行 38 tests はこのケース (`export_key` ×
accum セルの組合せ) を踏んでおらず、顕在化していない。installer 統合 (Task 4) か
conformance 実食 (Task 5) で `export_key` × multiple/repeat の fixture を食わせた時に
顕在化しうる。

## 受け入れ条件

- [ ] `accum_cells` にも `export_key` マップを適用するか、非対称のままで正しい理由を
      文書化するかを決定する
- [ ] 決定に応じて実装修正 or 設計意図のコメント追記を行う
- [ ] `export_key` × accum セル (flatten/append) の組合せを検証するテストケースを追加する

## TODO

<!-- wip 時のみ -->
