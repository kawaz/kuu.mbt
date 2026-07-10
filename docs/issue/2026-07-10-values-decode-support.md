---
title: values キーの decode 対応 (or 展開) — set-always-variant-branch.json の skip 解消
status: open
category: task
created: 2026-07-10T18:59:05+09:00
last_read:
open_entered: 2026-07-10T18:59:05+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 依頼元プロジェクト (kuu spec リポ)
---

# values キーの decode 対応 (or 展開) — set-always-variant-branch.json の skip 解消

## 概要

decoder が `values` キーを unsupported key として扱っているため、
`fixtures/value-sources/set-always-variant-branch.json` (spec commit
`f85d2331e251`、DR-081 §4 の values×variant 枝競合 4 case) が skip されている。
`values` キーを decode 対応させ、or 展開として実装する必要がある。

## 背景

spec 側は DESIGN §5.3 (`values` は or 展開のショートハンド) が正本。今回、
以下の明文化追記が spec 側でなされている:

- §5.3 直交性
- DR-028 (type なし enum)
- DR-041 §4 (raw 消費と構造照合の別レイヤ性)

これにより decoder 側の実装方針が明確になったため、対応する。

## 対応

- decoder に `values` キーを受理させ or 構造へ展開 (DESIGN §5.3)
- variant long (`:set` / `:set:always`) との同居を通す
- 対象 fixture `set-always-variant-branch.json` の 4 case を green 化
- `expected_skips` ledger から該当エントリを削除
- pin bump

## 受け入れ条件

- [ ] values decode + or 展開の実装
- [ ] `set-always-variant-branch.json` 4 case が green
- [ ] `expected_skips` ledger エントリ削除
- [ ] conformance mismatches=0 / skipped=0

## 関連

- spec issue `values-variant-branch-competition` (受け入れ条件 3 の対)
- kuu.mbt `json_conformance_wbtest.mbt` の `expected_skips` (暫定 ledger 登録は本 issue が追跡)
