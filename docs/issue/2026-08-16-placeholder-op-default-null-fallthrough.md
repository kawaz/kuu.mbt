---
title: placeholder op=default が null 化されず result/sources に漏れる
status: open
category: bug
created: 2026-08-16T14:12:06+09:00
last_read:
open_entered: 2026-08-16T14:12:06+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ) コードレビュー 2026-08-16
---

# placeholder op=default が null 化されず result/sources に漏れる

## 概要

⚠ spec 裁定待ち

## 概要 (A2 + R6 F7 統合)

degenerate op=default (宣言 default なし・下位席なし) で placeholder `Bool(false)` が result/sources に漏れる。

## A2 (resolve): 場所 src/kuu/resolve.mbt:4077, 4086

degenerate op=default (宣言 default なし・下位席なし) で placeholder `Bool(false)` が result/sources に漏れる。実測 `{color=false}` — string セルに bool の型汚染。definition-error でも塞がれていない。

## 関連: R6 F7 (front_door.mbt)

OutputEffect.op 語彙にも同種の placeholder `Bool(false)` 漏出が確認されている (統合報告 P5「placeholder `Bool(false)` の漏出 — 2領域3件」参照、もう1件は R3-3 union shadow判定)。

## 裁定が必要な点

null落ち (placeholder を null として扱い result/sources に出す) と def-error (宣言不備として definition-error にする) のどちらの挙動にすべきか、報告自身が明記する通り裁定が必要。「placeholder を観測面に出さない」不変条件が型で保証されていない点も対処に含める。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] null落ち / def-error のどちらにするか裁定される
- [ ] resolve.mbt (A2) と front_door.mbt (R6 F7) の両箇所が裁定に沿って修正される
- [ ] placeholder が観測面 (result/sources) に出ない不変条件が確認される (型 or テストで担保)
