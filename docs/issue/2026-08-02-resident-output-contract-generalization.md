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

## 進捗

W2-7 で cell_fns の値残余座分 (DR-127 §3.2: 値残余座への Value fn 戻り値を
着地フィールド type の out と照合し乖離を held Error にする) を消化した。
`src/extension/output_contract.mbt` の `seat_fn_output_breach` が既存の
undeclared_field/duplicate_field/field_type_mismatch/output_shape_mismatch
語彙を再利用して実装。pin: `src/kuu/value_seat_wbtest.mbt`
(「DR-127 §3.2: fn 戻り値の out 不適合は乖離 Error」)。

残余スコープ = provider / filter / collector / 通常セル着地の cell_fns の
「自己宣言 io_type との照合」(値残余座以外)。

### 実装上の障害

cell fn descriptor (`src/extension/cell_fn.mbt`) の `CellFnOutput` は
Value/Number/Sentinel 級の粗い分類で、DR-126 §1 の ValueType を名乗る
io_type 席が descriptor に無い。一般適用には descriptor へ output_type 席を
足す ABI 拡張が先行して要る (provider/filter/collector も同様に要確認)。

## 受け入れ条件

- [ ] provider/filter/cell_fns/collector の産出が各自の io_type 宣言と照合され乖離が held Error になる
- [ ] 既存の undeclared_field/duplicate_field/field_type_mismatch/output_shape_mismatch 語彙を再利用
- [ ] wbtest で pin
