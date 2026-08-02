---
title: cell fn `empty` の target 型検査が lowering に無い
status: resolved
category: bug
created: 2026-08-02T11:05:08+09:00
last_read:
open_entered: 2026-08-02T11:05:08+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-08-02T12:18:44+09:00
discard_reason:
pending_reason:
close_reason: ["dr/DR-044","implemented","finding/2026-08-02-w2-6-value-space-static-resolution"]
blocked_by:
origin: kuu spec リポ
---

# cell fn `empty` の target 型検査が lowering に無い

## 概要

REFERENCE.md の cell_fns 表は `empty` を array/map/record 専用と規定しており、scalar 等の target への `clear:empty` は definition-error (invalid-range) となる規定になっている。しかし kuu.mbt の lowering 実装はこの target 型検査を持たず、scalar cell への `clear:empty` が definition-error にならず parse を通ってしまう。

## 背景

REFERENCE の cell_fns 表 (empty の target 型制約) を実装側で裏取りしたところ、対応する型検査コードが lowering に存在しないことを確認した。W2-5/W2-6 の value_type 整備 (`docs/research/2026-08-02-w2-2-value-type-model-design.md` 系統) でこの種の target 型検査が体系的に整うため、その中で閉じる想定。

## 受け入れ条件

- [x] scalar 等 array/map/record 以外の target への `clear:empty` が definition-error (invalid-range) になる
- [x] spec fixture (`definition-error/` 配下) に該当ケースを追加
- [x] REFERENCE.md の cell_fns 表の規定と実装が一致することを確認
