---
title: filters registry に regex_match を追加 (DR-040 語彙、正規表現エンジンの調達判断込み)
status: open
category: task
created: 2026-07-09T16:49:03+09:00
last_read:
open_entered: 2026-07-09T16:49:03+09:00
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

# filters registry に regex_match を追加 (DR-040 語彙、正規表現エンジンの調達判断込み)

## 概要

spec の filters 語彙には `regex_match` が明示されている (DR-009 の DSL 例 / DR-040
「狭める (拒否)」の `pre_filters: regex_match` / DESIGN.md §8.4) が、kuu.mbt の
`filters_registry()` は `trim` / `non_empty` / `in_range` / `increment` の 4 種のみで
`regex_match` が無い。

## 背景

moonbitlang/x 依存 (`.mooncakes/moonbitlang/x/`) に regex パッケージは含まれない
(codec/crypto/decimal/encoding/fs/json5/num/path/rational/stack/sys/time/uuid のみ、
2026-07-09 実査)。着手時に正規表現エンジンの調達判断が必要:

1. **サブセット自前実装** — DR-040 の用例レベル (anchor `^` `$` / 文字クラス `[a-z]` /
   量指定子 `+` `*` `?`) に限定。サブセット範囲を descriptor か doc で明文化する必要
2. **moonbit 生態系の regex ライブラリ調査** — mooncakes.io で regex を探す。存在と
   品質は未調査
3. **spec 側で regex_match の照合仕様を先に確定する DR が要る可能性** — どの regex
   方言か (RE2 風 / POSIX ERE / サブセット)。実装が先に方言を決めると spec が実装に
   引きずられる懸念

完了時は spec 側に `regex_match` の conformance fixture を追加する
(`fixtures/pre-filters/reject.json` は 2026-07-09 に `non_empty` ベースへ変更しており、
`regex_match` の輪郭 fixture は本 issue とセットで復活させる)。判別すべき輪郭:

- 一致受理
- 不一致 reject
- 部分一致と全体一致の区別
- メタ文字 escape

由来: pre_filters 配線 (issue `pre-split-filters-execution-wiring`) の実装中に
impl-prefilters worker が発見。fixture が `regex_match` を使っていたため mismatches=2
で発覚 → fixture を `non_empty` へ変更して配線本体と切り離した (spec commit
`f21d9621`)。

## 受け入れ条件

- [ ] 正規表現エンジンの調達方針 (上記選択肢 1〜3 のいずれか) を決定し記録する
- [ ] `filters_registry()` に `regex_match` を追加する
- [ ] spec 側 `fixtures/pre-filters/` に `regex_match` の conformance fixture を復活・追加する
- [ ] 上記 4 輪郭 (一致受理 / 不一致 reject / 部分一致と全体一致の区別 / メタ文字 escape) をテストで網羅する

## 2026-07-09 codex 設計提案の受領と監査所見

設計調査を codex (gpt-5.5) に read-only 委譲した。提案全文は
docs/findings/2026-07-09-regex-match-design-proposal.md。要点:

- **調達**: MoonBit 生態系に regex パッケージなし (moonbitlang/x@0.4.46 実査 + 公開検索) →
  内蔵 subset regex を採用案とする。対応: `^ $ / [a-z] 文字クラス / + * ? / literal / escape`。
  非対応メタ文字 (`. | ( ) { }`) は未 escape なら compile error (silent literal 化しない)。
  unanchored = 部分一致、全体一致は anchor で表現。規模見積り ~500 LOC 未満
- **spec 論点**: regex 方言は cross-host 再現性条件 (DR-040 §「regex 方言の一致」) なので
  新 DR で canonical subset 名 (`kuu_regex_min` 案) を固定すべき — **kawaz 裁定球**
- **colon 問題**: `split_filter_spelling` は全 colon 分割のため `regex_match:^https?://` が壊れる。
  codex 案は「regex_match のみ first-colon split」

監査所見 (team-lead): 採用案・fixture 輪郭案は支持。ただし colon 対応の「filter 名で分割規則を
変える特例」は DSL の一般規則を name 依存にする懸念があり、descriptor に arity/greedy-last-arg
を宣言させて分割を descriptor-driven にする代替案も比較検討したい (DR 起票時の論点に含める)。

次のアクション: kawaz に (1) kuu_regex_min の subset 範囲、(2) colon 対応 (name 特例 vs
descriptor-driven)、の 2 点を DR 議論球として提示してから実装着手。
