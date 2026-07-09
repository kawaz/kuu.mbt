---
title: filters registry 汎用基盤の整備 (DR-009/DR-010/DR-040/DR-077 の宣言軸が未実装)
status: open
category: design
created: 2026-07-09T09:55:47+09:00
last_read:
open_entered: 2026-07-09T09:55:47+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 依頼元プロジェクト kuu (spec リポ)
---

# filters registry 汎用基盤の整備 (DR-009/DR-010/DR-040/DR-077 の宣言軸が未実装)

## 概要

kuu.mbt には filters registry の汎用機構が無い。FilterArg はハードコードされた "max" 専用の消費ノードのみで、`filters` / `pre_split_filters` / `post_filters` 宣言軸 (DR-009 の 3 段 chain)、in_range 等の組み込み filter、descriptor による signature (validate/transform) 宣言 (DR-061/DR-077 §2) がいずれも未実装。

## 背景

DR-077 実装 (commit c5e5f44b) で「post_filters が update の結果にも通る」(DR-077 §1) が**基盤不在で検証不能**だった。update の transform 解決も registry lookup でなく apply_transform 内のハードコード match ("increment" のみ) で代替している。DR-040 の「count の上限は post_filters (in_range) で書く」も現状は書けない。

由来: dr066-path worker の DR-077 実装報告 (2026-07-09)。

## 受け入れ条件

- [ ] filters registry の器 (名前 → 実体 + descriptor: signature/args/reasons 宣言) が実装されている
- [ ] DR-009 の 3 段 chain (pre_split / each / post) の宣言 decode と実行配線ができている
- [ ] 組み込み filter 最小セット (trim / non_empty / in_range / increment) が動く
- [ ] apply_transform (resolve.mbt) が registry lookup 化されている
- [ ] update 結果への post_filters 適用 + wbtest/fixture が揃っている
- [ ] apply_transform が emit する暫定 reason (update_transform_type_mismatch / unknown_update_transform) の扱い (descriptor 宣言へ載せるか整理) が決着している

## TODO

<!-- wip 時のみ -->
