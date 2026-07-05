---
title: unbounded repeat{min:2} の min 未達で failure の errors が空になる (bounded は held error を emit)
status: open
category: bug
created: 2026-07-05T22:06:18+09:00
last_read:
open_entered: 2026-07-05T22:06:18+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (docs/decisions/DR-053, DR-065, docs/CONFORMANCE.md §2)
---

# unbounded repeat{min:2} の min 未達で failure の errors が空になる (bounded は held error を emit)

## 概要

unbounded な `repeat{min:2}` (max 無し) が min 未達 (argv `[a]` の 1 個のみ)
で failure になるケースで、slice の現行実装は `errors` が空のまま
failure を返す。

同型の min 未達でも bounded (`min:2, max:2`) は held error
(missing operand) を emit する (`phase14:71`)。差は `max` の有無だけで、
unbounded 側は `phase14:34` が「空 errors 前提の fail: no complete parse」
として凍結されている。

kuu spec (DR-053/065、`docs/CONFORMANCE.md` §2) は構造的必須の不成立
(= min 未達) で `missing_operand` の held error が必須と定めている。
`fixtures/repeat-parse/min2-standalone.json` (kawaz/kuu 側) は既に
仕様準拠の値 (`element`/`argv_pos`/`kind`/`reason`) で先行しているため、
parse runner がこの領域を転写した時点で divergence として顕在化する
見込み。

## 背景

同種の「failure の errors が空になる」問題は `2026-07-05-structural-failure-empty-errors.md`
(トークン枯渇・残余トークン系) で既に起票済み。本件は unbounded repeat の
min 未達というもう 1 つの経路で同じ症状 (held error 未捕捉) が出ている
ケース。

なお `path-search/complete-path-count.json::case#3` (argv `[x, 5, z]` の残余
トークン `z` で failure、`errors` に `b@1/parse` の held error が期待される)
も**同じ held-error 未捕捉が根**で、slice の `known_divergences()` では本件
(`repeat-parse/min2-standalone.json::case#1`) と同一の「held-error gap
(DR-053 §2)」コメント配下に co-list されている。残余トークン経路という点では
`structural-failure-empty-errors` 寄りだが、held ParseError を落とす根因は共通
なので、この領域の修正は両経路をまとめて裏取り・是正すると良い。

原因仮説 (裏取り前提のフラグ、実装判断は当事者セッションに委ねる):
無制限 repeat の Ref 再帰 lowering 経路が min 未達時の held ParseError を
落としており、有界 (BoundedTail) 経路は emit している。この仮説の裏取り
と、該当するなら「構造的失敗の ParseError 合成」という同種の修正が
必要か (= 2026-07-05 に `structural-failure-empty-errors` 系で行った修正
の再適用パターンに当たるか) は、このリポ側で確認してほしい。

一次資料:

- `kawaz/kuu` main の `docs/decisions/DR-053-parse-outcome-structure.md`
  (outcome union / 全保持の errors)
- `kawaz/kuu` main の `docs/decisions/DR-065-conformance-fixture-format.md`
  §3 (`kind` の割当規約)
- `kawaz/kuu` main の `docs/CONFORMANCE.md` §2 (failure の `errors` 形状)
- `kawaz/kuu` main の `fixtures/repeat-parse/min2-standalone.json`
  (仕様準拠の期待値、min 未達で held error あり)
- slice の `phase14:34` (unbounded repeat min 未達、現状は空 errors 前提で
  凍結)
- slice の `phase14:71` (bounded repeat min 未達、held error あり = 対比
  対象)

## 受け入れ条件

- [x] unbounded `repeat{min:2}` の min 未達 (argv `[a]`) で、slice の
      failure が bounded 側と同様に held error (`missing_operand`) を
      `errors` に持つようになる
- [x] `phase14:34` の期待値を仕様準拠 (空 errors 前提を撤回) に更新し、
      fixture runner / test が更新後の期待値で PASS する
      (phase14 の `["a"]` = `fail:missing operand for f` へ更新)
- [x] 原因仮説 (Ref 再帰 lowering 経路での held ParseError 欠落) の裏取り
      結果を本 issue または関連 DR/journal に残す (下記「真因・修正」)

## 真因・修正 (裏取り済)

**真因**: 仮説どおり Ref 再帰 lowering 経路が min 未達時の held を落としていた。
unbounded `repeat{min:N}` は `min-1` 個の mandatory StrArg (spine 上、`scope_consume`
で処理 = 枯渇時 held を emit) + `Ref` tail に unroll される。min-th の mandatory head は
Ref の `consume_head` を通るが、`consume_head` は StrArg/NumArg/SepArg の**トークン枯渇時に
`[]` (silent Reject) を返し held を emit しなかった**。bounded (BoundedTail) 側は mandatory
head が全て spine 上の StrArg (`scope_consume`) なので held を emit していた — この非対称が
`fail:no complete parse` (空 errors) の正体。

**修正**:
1. `consume_head` に枯渇時 (`pos >= toks.length()`) の missing_operand held を追加
   (`scope_consume` の StrArg と同型、共通 helper `pe_missing`)。これで Ref tail の
   min-th mandatory head も held を emit。
2. **min 超過分の leak 対策**: `Ref`/`BoundedTail` の "more" (optional 追加 rep) 枝が枯渇
   すると同 held が spurious に出る (min2-trailing で `{src@2,dst@2}` になる回帰を観測)。
   `drop_optional_missing` で「rep が 1 つ成功した後の more 枝から、その rep 要素自身の
   missing_operand を除去」する (最小は既に満たされているので optional rep の枯渇は
   停止シグナルであってエラーではない)。mandatory head の held (consume_head が Accept
   なしで Held を返す経路) は more を通らないので除去されない。
3. `scope_consume` の NumArg/SepArg にも枯渇時 held を追加 (StrArg のみ持っていた) —
   これが `path-search/complete-path-count.json::case#3` (2nd positional `b` が number、
   トークン枯渇で `{b@1/parse}`) を解消。

**解消した divergence**: `repeat-parse/min2-standalone.json::case#1` (`{f@1/parse}`) と
`path-search/complete-path-count.json::case#3` (`{b@1/parse}`) の両方。台帳から除去済み。
`repeat-parse/exact-count.json` (bounded 対比) 等の repeat 系 fixture は全 green 維持。

**副作用 (許容)**: min:0 repeat は現状 ≥1 に lower される既存 gap
(`ambiguous-receptacles`, DR-043 取り分・別 issue) があり、その失敗メッセージが
`no complete parse` → `missing operand` に変わった (失敗である事実・divergence key は不変、
台帳コメントを追従更新)。`phase10` の greedy backtrack テストは、全保持 (DR-053 §2) で
max-argv_pos の held が primary になる仕様に沿い `missing operand for ys` へ更新。
