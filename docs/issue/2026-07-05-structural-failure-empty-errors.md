---
title: トークン枯渇・残余の failure で errors が空になる — held-error が構造的必須不成立/残余トークンを捕捉しない (DR-053/065)
status: open
category: bug
created: 2026-07-05T13:20:09+09:00
last_read:
open_entered: 2026-07-05T13:20:09+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (docs/CONFORMANCE.md §2, DR-053/065/066)
---

# トークン枯渇・残余の failure で errors が空になる — held-error が構造的必須不成立/残余トークンを捕捉しない (DR-053/065)

## 概要

`fixtures/dd/basic.json` の case 3・5 (トークン枯渇 = 構造的必須の不成立、
`reason: missing_operand`) と case 4 (残余トークン、
`reason: unexpected_token`) は、いずれも完全経路 0 本で `outcome: failure`
になるが、slice の現行実装ではこの 2 パターンで `errors` 配列が **空**
のまま failure が返る。

kuu spec (`docs/CONFORMANCE.md` §2 の failure 形状、および DR-053/065) は
failure の `errors` に少なくとも 1 件の Error
(`element` 省略可 = スコープレベル、`argv_pos` = 残余先頭 or
`argv.length`、`kind: parse`) が入ることを前提にしている。この前提が
崩れているため、`fixtures/dd/basic.json` の case 3/4/5 は現状 slice で
仕様準拠の検証が成立しない (failure という outcome の大枠は一致するが、
errors の中身が仕様の期待する形になっていない)。

根本原因(仮説、要裏取り): slice の held-error 機構は「トークンが**存在**して
reject された」場合 (例: `matcher.mbt` の「defined key, bad value => held
Error」、`node.mbt` の「number value primitive の parse-fail は held
Error」) にのみ Error を保持する設計になっており、トークン枯渇
(要求した位置にトークンがない = `argv.length` 相当) や残余トークン
(消費者がいない終端トークン列) の経路では、そもそも `ParseError` を
合成する箇所が無い。修正方向としては、scope 走査がこれらの経路を
「完全経路 0 本、Error なし」として落としている地点を特定し、そこで
`ParseError` を合成するのが筋と見ているが、実装方針 (どの走査ステップに
差し込むか) はこのリポの担当セッションでの裏取りに委ねる。

## 背景

fixture runner (`poc/fixture_runner_wbtest.mbt`、第 19 弾実食) で
`fixtures/dd/basic.json` (7 cases) を通した結果、outcome の一致は
取れるものの case 3/4/5 の `errors` 内容が空で、DR-053/065 が定める
Error 表現 (kind/element/argv_pos/reason) が検証できないことが判明した。

一次資料:

- `kawaz/kuu` main の `docs/CONFORMANCE.md` §2 (failure の `errors` 形状、
  `kind: parse` の割当 — 構造的必須の不成立 と 残余トークン の両方を含む)
- `kawaz/kuu` main の `docs/decisions/DR-053-parse-outcome-structure.md`
  (outcome union / 全保持の errors)
- `kawaz/kuu` main の `docs/decisions/DR-065-conformance-fixture-format.md`
  §3 (`kind` の割当規約)
- `kawaz/kuu` main の `docs/decisions/DR-066-error-reason-codes.md`
  (`reason` の機械可読識別子)
- `kawaz/kuu` main の `fixtures/dd/basic.json` case 3 (枯渇,
  `missing_operand`, argv_pos=2)・case 4 (残余,
  `unexpected_token`, argv_pos=2, element 省略)・case 5 (枯渇,
  `missing_operand`, argv_pos=3)
- slice の `poc/fixture_runner_wbtest.mbt` (実食結果の記録元)
- slice の held-error 実装箇所: `poc/matcher.mbt`, `poc/node.mbt`,
  `poc/eval.mbt` (`WithHeld` / held Error 一般)

## 受け入れ条件

- [x] `fixtures/dd/basic.json` case 3・4・5 について、slice の failure が
      仕様の定める `errors` 内容 (`kind: parse`、`element` 省略 or 該当
      element、`argv_pos`) を持つようになる
      (`eval.mbt`: 構造的必須不成立は held ParseError、残余トークンは
      top-level で合成。case 3=`{x@2/parse}`, case 4=`{@2/parse}`,
      case 5=`{x@3/parse}` が fixture 一致)
- [x] 上記 3 case が fixture runner 上で仕様準拠の期待値と一致する
      (fixture runner の case 3/4/5 が PASS)
- [ ] `reason` (`missing_operand` / `unexpected_token`) までは現状
      runner が未比較 (`reason` 検証は fixture 側 optional のため、
      本 issue のスコープ外としてよい。別途着手する場合は runner 側の
      比較ロジック追加が必要)

## 追記: 同根の後続解消 (complete-path-count::case#3)

本 issue で `eval.mbt` に入れた「構造的必須不成立は held ParseError」は `scope_consume` の
**StrArg** 経路のみだった。順序付き 2 positional (a:string, b:number) の 2 番目 `b` が number で
トークン枯渇するケース (`path-search/complete-path-count.json::case#3`, want `{b@1/parse}`) は
**NumArg 経路に枯渇 held が無く** 空 errors のままだった。`2026-07-05-min2-unbounded-empty-errors.md`
の修正で `scope_consume` の NumArg/SepArg にも枯渇 held を追加して解消済み (詳細はそちらの
「真因・修正」)。残余トークン (case#4) は本 issue の top-level 合成で既に解消済み。

## 関連メモ (future work, 本 issue の受け入れ条件には含めない)

- `proj_effects` (`fixture_runner_wbtest.mbt:44`) が binding の `source`
  を明示フィルタしていない。現状 parse fixture の binding は `cli` の
  みなので実害はないが、value-source 系 fixture (env/config/inherit/
  default 由来の binding) を導入する際は 1 行のフィルタ追加が必要になる
- 現行 runner は characterization テスト形式 (「observed slice behavior
  を frozen して drift を検出する」) であり、本 issue のような spec
  divergence があっても green (181/181) の中に埋もれる。181 件全体が
  「挙動凍結」であって「仕様準拠」を意味しない点に注意。乖離解消後は
  divergence = fail の conformance モードへ runner を育てる方針を検討
