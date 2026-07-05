---
title: or 値枝の制約違反 element が枝 id でなく親 name に帰属する
status: open
category: bug
created: 2026-07-06T01:29:30+09:00
last_read:
open_entered: 2026-07-06T01:29:30+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (docs/decisions/DR-052-export-key-unification.md, DR-055-constraint-vocabulary.md §1)
---

# or 値枝の制約違反 element が枝 id でなく親 name に帰属する

## 概要

slice の `ElemDef` は匿名 exact 枝 (`or` 配列の要素) に DR-052 の露出直交 id
を持てない。値依存制約 (DR-055 §1、値の枝への `requires` 合成) を
`CRequiresIf` へ lowering する際、違反した制約の `element` を宣言元の枝 id
(例 `fmt_json`) でなく、親要素の name (例 `format`) に帰属させてしまう。

JSON conformance runner (`poc/json_conformance_wbtest.mbt`) の divergence 台帳
(`known_divergences()`) に凍結済みの既知 gap 2 件:

- `constraints-parse/default-interaction.json::case#3`
- `constraints-parse/requires.json::case#4`

いずれも fixture 定義は
`{"exact": "json", "id": "fmt_json", "requires": ["schema"]}` という
`format` の or 枝で、`format=json` が committed かつ `schema` 未供給の場合に
`kind:constraint` / `reason:requires_violated` の failure を期待する。
`outcome` / `kind` / `argv_pos` は fixture と一致するが、`element` だけが
fixture の期待値 `fmt_json` (宣言元の枝 id) でなく `format` (値の格納先の
親 name) になっている。

fixture 側は kuu 仕様の正本 (`known_divergences()` のコメント通り「fixture
の期待値を書き換えて green にするのは禁止」の runner 方針)。gap は slice
被検体側にある。

## 背景

`dec_or` (`poc/json_conformance_wbtest.mbt:688`) の docstring に明記されている
LOSSY NOTE:

> the 枝 `id` (DR-052 orthogonal id naming the anonymous exact枝) is NOT
> representable — the slice attributes the constraint element to the
> parent NAME, so an id-bearing requires枝 produces a known
> element-name divergence (frozen in the ledger).

`known_divergences()` 内の該当コメント (`json_conformance_wbtest.mbt:1655-1660`):

> value枝 id attribution (DR-052 直交 id / DR-055 §1): the `or` value枝
> `{exact:json, id:fmt_json, requires:[schema]}` lowers to a
> value_requires (json → [schema]) whose `CRequiresIf` carries the
> PARENT element name `format`, not the枝 id `fmt_json` — the slice's
> `ElemDef` has no place to name an anonymous exact枝, so a constraint
> violation reports element=format where the fixture asserts
> element=fmt_json. slice gap (value-branch id attribution unmodeled).
> The outcome (failure, kind:constraint, argv_pos) is correct — only
> the element name diverges.

一次資料:

- `kawaz/kuu` main の `docs/decisions/DR-052-export-key-unification.md`
  (lexical スコープ name と id (ref/link) の直交性)
- `kawaz/kuu` main の `docs/decisions/DR-055-constraint-vocabulary.md` §1
  (値依存の制約は「値の枝 (exact 要素) への requires 合成」で書く、
  専用 DSL は不採用)
- `kawaz/kuu` main の `fixtures/constraints-parse/default-interaction.json`
  case#3、`fixtures/constraints-parse/requires.json` case#4
  (いずれも `format` の or 枝 `{"exact":"json","id":"fmt_json","requires":["schema"]}`)
- slice の `poc/json_conformance_wbtest.mbt` の `dec_or` docstring
  (行 683 付近の LOSSY NOTE) と `known_divergences()` (行 1655-1662)

## 受け入れ条件

- [ ] DR-052 直交 id を `ElemDef` / `CRequiresIf` (またはその lowering 経路)
      側で担持できるようにするか、当事者セッションで裏取りした上で採否を判断する
      (拡張が必要と判断した場合は実装、不要と判断した場合はその根拠を本 issue
      または派生 DR に残す)
- [ ] 採用する場合: `constraints-parse/default-interaction.json::case#3` と
      `constraints-parse/requires.json::case#4` の `element` が fixture の
      期待値 (`fmt_json`) と一致するようになり、`known_divergences()` から
      該当 2 行が VANISHED として消し込める
- [ ] 見送る場合: 見送り理由 (設計上の制約 / コスト判断の根拠) を明記し、
      台帳コメントに「既知の未対応、見送り済み」である旨を残す

## TODO

<!-- wip 時のみ -->
</content>
