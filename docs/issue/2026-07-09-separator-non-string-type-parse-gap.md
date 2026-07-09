---
title: separator 付き multiple の非 string 型が型 parse を経由しない (SepArg = VStr 固定)
status: open
category: bug
created: 2026-07-09T16:18:40+09:00
last_read:
open_entered: 2026-07-09T16:18:40+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: impl-prefilters worker (pre_filters 配線の設計調査中)
---

# separator 付き multiple の非 string 型が型 parse を経由しない (SepArg = VStr 固定)

## 概要

`src/core/installer.mbt` の `elem_head` (L762-770 付近) の separator 分岐は
`e.ty` を見ず、separator が `Some` なら無条件で `SepArg` (piece を常に
`VStr` で bind) を構築する。このため `multiple` + `separator` + 非 string 型
(number / int / float / bool) の組み合わせで、各 piece が型 parse
(DR-034 pieceProcessor の parse 相) を一切経由せず string のまま cell に
入る。spec 上は piece ごとに pre → parse → post を通るべき (DR-034 §6.2)。

## 背景

再現の輪郭 (未実測、grep 根拠のみ):

```json
{"name":"ns","type":"number","multiple":{"accumulator":"append","separator":","}}
```

に `"1,2"` を渡すと `[1,2]` (VNum) ではなく `["1","2"]` (VStr) になるはず。
conformance fixture も number×separator の組み合わせが未整備
(`fixtures/multiple-parse/` は string のみ)。

対処案: `SepArg` に型情報 (`Ty` + `int_round` 等の config) を運搬し、piece
ごとに型 parse を通す。pre_filters 配線 (issue
`2026-07-09-pre-split-filters-execution-wiring`) の sep_binds 改修と隣接
するが、スコープ膨張を避けるため別 issue とする。spec 側に判別 fixture
(number×separator) の追加も必要。

由来: 2026-07-09 impl-prefilters worker が pre_filters 配線の設計調査中に
grep で発見 (実測未)。

## 受け入れ条件

- [ ] `multiple` + `separator` + 非 string 型の組み合わせで、各 piece が型
      parse を経由する実装になっている (grep + 実測で確認)
- [ ] number×separator 等の conformance fixture が spec 側に追加されている
- [ ] 上記 fixture が通ることを確認

## TODO

<!-- wip 時のみ -->

## 2026-07-09 追記: option 経路では separator 分割自体が未配線 (より根本的な欠落)

accum×filters(each) 配線 (issue accum-entity-filters-wiring) の実装中に impl-prefilters worker が発見。
SepArg を構築する elem_head は **positional 面の lowering 専用** (呼び出し元は def.positionals ループ /
repeat head / BOr/BGroup 内部のみ)。long/short option (greedy face) の value slot は inst_long /
inst_short が value_prim を直接呼び (installer.mbt L1143 付近)、e.separator を一切参照しない。

つまり multiple + separator を option として宣言すると分割が全く起きず、`--ports 5,500` は
"5,500" がそのまま NumArg parse に渡って not_a_number になる (実測: fixtures/multiple-parse/
filters-each.json::separator-piece-rejects-whole の mismatch、got=parse/not_a_number)。

本 issue の対処は 2 段になる:
1. inst_long / inst_short に separator 分岐を追加し option 経路でも SepArg (相当) を構築する
2. SepArg に型情報を運搬して piece ごとに pre_filters → 型 parse を通す (当初起票分)

conformance fixture: multiple-parse/filters-each.json::separator-piece-rejects-whole が
本 issue 解決までの known divergence として ledger 登録される (fixture の意図は変えない)。
number×separator の成功系 fixture (spec 側) も本 issue 解決時に追加する。

## 2026-07-09 追記 2: 対処 2 段の連鎖を実測確認 (段 1 単独適用は不可)

impl-prefilters worker が段 1 (option 経路の separator 配線) を試験実装して確認した実測:
value_prim に `separator? : String?` を追加して SepArg 構築を一元化する修正 (アプローチ自体は
有効、elem_head の独自分岐も一本化できる) を入れると、`--ports 5` (separator 宣言あり・分割
不要の単発トークン) も SepArg 経由になり、**段 2 (SepArg の型 parse 欠如) が即座に露呈**して
VStr("5") が number filter (in_range) に渡り成功系まで壊れる。

つまり段 1 と段 2 は片方だけ適用できない (段 1 のみ → 成功系 regression / 段 1 なし → option で
分割自体が起きない)。**本 issue の着手時は 2 段を同一サイクルで一括実装すること**。
Binding.at_pos (accum-entity-filters-wiring サイクルで導入予定) が入っていれば、separator piece
群の argv_pos (同一トークン位置) はそのまま乗る。

検証環境: multiple-parse/filters-each.json の 3 case が本 issue の判別 fixture として機能する
(段 1+2 完了で case 3 が GREEN、成功系 case 1 が regress しないことも同 fixture で確認可能)。
number×separator の成功系 fixture (spec 側) の追加も本 issue の受け入れ条件に含める。
