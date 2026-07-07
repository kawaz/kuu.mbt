---
title: accum セルの export_key rename が未対応 (resolve 層の非対称)
status: open
category: design
created: 2026-07-07T23:36:14+09:00
last_read:
open_entered: 2026-07-07T23:36:14+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
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
