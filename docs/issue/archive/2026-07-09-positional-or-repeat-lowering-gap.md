---
title: positional × or × repeat の wire lowering ギャップ — string 枝が並列生成されない
status: resolved
category: bug
created: 2026-07-09T10:36:42+09:00
last_read:
open_entered: 2026-07-09T10:36:42+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-09T10:56:19+09:00
discard_reason:
pending_reason:
close_reason: ["implemented:fe59837d","finding:BOr が elem_repeat を無視していた実装漏れを lower_repeat_head 抽出で BCell/BOr 共用化し根治","done:DR-043 の Or head 適用は既存裁定の同型適用のため新規裁定不要","done:付随して harness failure 分岐の resolve 層欠落も同一コミットで修正"]
blocked_by:
origin: spec リポ (kawaz/kuu) の fixture-batch worker
---

# positional × or × repeat の wire lowering ギャップ — string 枝が並列生成されない

## 概要

positional `{name:"hlcolors", repeat:{min:1}, or:[{seq:[r,g,b] (3 数値)}, {type:"string", name:"colorname"}]}` の wire 定義で、slice の手組 `Or([Seq(rgb), StrArg(name)])` では成立する挙動が wire form の lowering で再現しない。数値 or 枝は認識されるが string or 枝が並列生成されていない疑いがある。

## 背景

fixture 試作時に実機観測 (2026-07-09):

- argv `["red","blue"]` → 期待 success `{colorname:["red","blue"]}` が **fail: unexpected token** (string 枝が反応しない)
- argv `["255","0","0"]` → 期待 ambiguous 2 (rgb 1 反復 vs name 3 反復) が **rgb 枝のみで success** (ambig 不発)

option × or (repeat なし) の `fixtures/path-search/variable-arity-ambiguous.json` は PASS するため、positional × or × repeat の組み合わせ固有の問題。structural-or builder (MDR-004) の positional 側波及の可能性がある。

ブロックしているもの: spec の audit 漏れ 2 件の fixture 化 (phase4:114 = 共有 or-template repeat の ambiguity, phase10:64 = 取り分選好の or 非侵食性)。spec 側 `findings/2026-07-09-distill-1to1-coverage-audit.md` 参照。

試作 fixture は削除済みのため conformance への影響なし (fixture-batch worker の audit 第二段報告、2026-07-09 由来)。

## 進め方

まず slice 相当の手組 Node で RED を再現 → wire lowering (installer) の or × repeat 経路を調査。裏取りしてから採否を決めること (fixture 試作の観測は spec リポ側ワーカー由来で、再現構成の詳細は上記 findings と本文の定義断片から復元可能)。

## 受け入れ条件

- [ ] slice 手組 Node で RED (期待通りの挙動) を再現する最小テストを作成
- [ ] wire lowering (installer) の or × repeat 経路で string 枝が並列生成されない原因を特定
- [ ] 原因に応じて修正、または設計上の制約として文書化
- [ ] phase4:114 / phase10:64 の fixture 化がブロック解除される
