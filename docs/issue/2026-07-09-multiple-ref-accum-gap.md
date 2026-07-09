---
title: multiple×ref の accumulator 未配線で配列結果を作れない
status: open
category: bug
created: 2026-07-09T23:04:07+09:00
last_read:
open_entered: 2026-07-09T23:04:07+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ)
---

# multiple×ref の accumulator 未配線で配列結果を作れない

## 概要

multiple×ref の組合せが decoder で受理されるのに accumulator が配線されず、
仕様通りの配列結果を作れない (codex レビュー 2026-07-09 指摘 2、
ref-template-result-shape サイクル中に検出)。

## 背景

現象: `ensure_entity_body` が ref_target 持ち要素の entity 登録を常にスキップ
するため (installer.mbt 1062-1075 付近、ref-template result 修正で導入)、
multiple:true の ref 要素に accumulator が付かない。option ref の非 repeat
経路は `Scoped(e.name, elem_head(e))` のみなので、複数回発火すると
build_result の scalar last-wins に落ち、配列累積にならない。decoder は
option/positional の multiple と ref の同時指定を受理する
(json_conformance_wbtest.mbt 2215-2218 / 2366-2372 付近) ため、現状入力で
到達可能。

正本の根拠: spec DESIGN §6.1 (multiple 宣言要素の結果は配列)。ただし
multiple×ref の row 累積の詳細意味論 (row 配列に append か等) は spec
fixture 未整備で、spec 側 issue (kawaz/kuu の
ref-nested-consumption-fixture-gap、同日起票) と対。

対応方針: spec 側の fixture 裁定を待ってから実装。それまで decoder で
multiple×ref を明示 reject して黙った誤動作を防ぐ選択肢もある (要判断)。

## 受け入れ条件

- [ ] spec 側で multiple×ref の意味論が fixture 化される (spec issue 参照)
- [ ] accumulator が ref 要素にも配線され row が累積される (または明示 reject)
- [ ] conformance green
