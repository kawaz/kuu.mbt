---
title: repeat 付き positional の inline seq 子が行配列にならず last-wins で潰れる + none セルが 3 面へ漏れる
status: open
category: bug
created: 2026-07-29T09:26:29+09:00
last_read: 2026-07-29T17:33:44+09:00
open_entered: 2026-07-29T09:26:29+09:00
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

# repeat 付き positional の inline seq 子が行配列にならず last-wins で潰れる + none セルが 3 面へ漏れる

## 概要

repeat 付き positional の inline seq 子 (named group でなく `seq: [...]` 直書き) が行配列にならず、複数反復の結果が単一 kv へ last-wins で潰れる。同時に `type:none` の内部セルが effects / result / sources の 3 面すべてに漏れる。

実測 2026-07-29 (spec fixture `value-typing/none-exclusion-in-repeat-rows.json` の 2 case、未 push):

- got: `{rows={pair={keep=b,touch=y}}}` + `touch` の set 効果あり
- want: `{rows={pair=[{keep=a},{keep=b}]}}` + `keep` の効果のみ

## 背景

導出根拠:

- 反復宣言子だけが配列になる (DR-044)
- inline seq と ref は同じ構造の別の書き口 (DR-078 §1、`seq-parse/ref-template-parity.json` が pin)
- ref 版の行配列は `multiple-parse/last-wins-repeat-rows.json` で pin 済み
- none の 3 面除外は `value-typing/none-exclusion-under-scopes.json` (green) で pin 済み

つまり repeat が絡む経路でだけ、行構築と none 除外の両方が壊れている。inline seq という書き口固有の欠落であり、ref 版・non-repeat 版は既に正しく動作している。

## 受け入れ条件

- [ ] `value-typing/none-exclusion-in-repeat-rows.json` の 2 case が pass
- [ ] 姉妹 file `none-exclusion-in-renamed-repeat-rows.json` は export_key decode gap 解消後に pass (別 issue `2026-07-26-command-scope-export-key-none-cell-leak.md` 等の解消が前提)
