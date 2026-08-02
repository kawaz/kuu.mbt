---
title: resident output contract の一般化 (provider/filter/cell_fns/collector) — DR-126 §4 の適用範囲残余
status: open
category: task
created: 2026-08-02T12:33:36+09:00
last_read:
open_entered: 2026-08-02T12:33:36+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu
---

# resident output contract の一般化 (provider/filter/cell_fns/collector) — DR-126 §4 の適用範囲残余

## 概要

DR-126 §4 は乖離検査 (産出値 vs 自己宣言 io_type) を type パーサに限らず io_type
を名乗る resident 一般に適用すると規定する (DR-126 §4 末尾の適用範囲段落)。

現実装 (W2-5) は `src/extension/output_contract.mbt` の `parse_token_checked` 経由で
type resident の `parse_token` 席のみに配線しており、provider / filter / cell_fns /
collector の産出値は未検査。

## 背景

W2-5 事後監査 M3 の統括裁定で「段階実装として明示し W2-7 へ送る」ことが確定した。
W2-7 の「値残余座への fn 戻り値がフィールド type の out への適合検査を通る」
(DR-127 §3.2) と共通インフラになるため。

参照:
- docs/findings/2026-08-02-w2-5-producer-and-divergence.md §3.5
- 計画 docs/research/2026-08-02-dr127-wave2-implementation-plan.md W2-7 行

## 受け入れ条件

- [ ] provider/filter/cell_fns/collector の産出が各自の io_type 宣言と照合され乖離が held Error になる
- [ ] 既存の undeclared_field/duplicate_field/field_type_mismatch/output_shape_mismatch 語彙を再利用
- [ ] wbtest で pin
