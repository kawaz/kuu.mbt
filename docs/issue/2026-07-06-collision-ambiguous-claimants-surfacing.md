---
title: export-key 共露出衝突を Ambiguous + claimants で表面化する (DR-073 追従)
status: open
category: bug
created: 2026-07-06T11:06:54+09:00
last_read:
open_entered: 2026-07-06T11:06:54+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (docs/decisions/DR-073-export-key-collision-carrier.md, 2026-07-06)
---

# export-key 共露出衝突を Ambiguous + claimants で表面化する (DR-073 追従)

## 概要

仕様側で export-key 衝突の担体が確定した (kawaz/kuu DR-073、2026-07-06: ambiguous
維持 + 解釈ごとの optional claimants 面 = 露出キー → 占有実体 entity の name)。
slice の実装 gap は 2 つ:

1. **共露出衝突を Ambiguous outcome として表面化しない** — 現在
   `find_export_collision` (`poc/result.mbt:199`) は Success 後の別関数として
   走り、`parse()` は Success を返す。`export_result_str`
   (`poc/helpers_wbtest.mbt:529`) は非仕様文字列 `"collision:x"` を返しており、
   DR-073 が定める Ambiguous outcome の形になっていない。
2. **`AmbiguousData` に claimants provenance フィールドが無い** —
   `poc/eval.mbt:48` の `AmbiguousData` は解釈ごとの claimants
   (露出キー → 占有実体 entity の name) を持てず、DR-073 の claimants 面を
   生成できない。

## 背景

runner 側の want decode は対応済み: `poc/json_conformance_wbtest.mbt` の
`exp_interp_str` (行 961) が `{result, claimants}` wrapper を読める
(commit 5d5345d5)。`known_divergences()` の該当コメント (行 2207 付近) にも
「co-exposure を AMBIGUOUS outcome としてモデル化し、2 つの解釈が claimants 面を
持つ」設計が明記されている。

つまり slice 本体が上記 2 gap を実装した時点で、`fixtures/export-key/collision`
の `co-exposure-collision` case の outcome 層 divergence
(`known_divergences()` に凍結済み: `EXPECTED-AMBIGUOUS got=ok{a=true,b=true}`,
行 2215) が解消し、claimants 比較が発火する構造に既になっている。

一次資料:

- `kawaz/kuu` main の `docs/decisions/DR-073-export-key-collision-carrier.md`
  (ambiguous 維持 + 解釈ごとの optional claimants 面の決定)
- `kawaz/kuu` main の `docs/decisions/DR-021-...` / `DR-052-export-key-unification.md`
  (export-key 衝突検査・露出直交 id の前提設計)
- slice の `poc/result.mbt:199` (`find_export_collision`)、
  `poc/helpers_wbtest.mbt:529` (`export_result_str`)、
  `poc/eval.mbt:48` (`AmbiguousData`)、
  `poc/json_conformance_wbtest.mbt:961` (`exp_interp_str`) と
  `known_divergences()` 内の `co-exposure-collision` エントリ (行 2207-2215)

## 受け入れ条件

- [ ] `find_export_collision` の衝突検査を `parse()` の Outcome 判定経路に
      統合し、共露出衝突時に Ambiguous outcome を返す
- [ ] `AmbiguousData` に解釈ごとの claimants (露出キー → 占有実体 entity の
      name) provenance フィールドを追加する
- [ ] `export-key/collision.json::co-exposure-collision` case が
      claimants を含めて fixture の期待値と一致する
- [ ] `known_divergences()` の該当エントリ (行 2215 付近) を VANISHED として
      消し込む

## TODO

<!-- wip 時のみ -->
