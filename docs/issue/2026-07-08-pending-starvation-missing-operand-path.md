---
title: Pending 飢餓経由の missing_operand が DR-066 §4 path を持てない
status: open
category: design
created: 2026-07-08T17:47:53+09:00
last_read:
open_entered: 2026-07-08T17:47:53+09:00
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

# Pending 飢餓経由の missing_operand が DR-066 §4 path を持てない

## 概要

parse() トップレベルで Pending (値スロットが入力終端で飢餓) を missing_operand エラーへ変換する経路は、CPS の scope 境界通過 (nest_branches / CmdSat の Held prepend) の外側で走るため、ネストしたコマンド内で起きた値飢餓の missing_operand は常に path=[] になる。Held 経由で直接生成される missing_operand は正しく path が積まれる (eval_wbtest の REVIEW-D6 パターンで確認済み)。

## 背景

DR-066 §4「値は発火時の動的パス」— 発火位置がネスト scope 内なら祖先列が入るべき。conformance 上は path が optional 検証のため既存 fixture は無傷だが、将来 spec fixture が nested missing_operand に path を書いたら露呈する。

由来: 2026-07-08 DR-066 §4 実装 (commit 1d99bed9) の監査で dr066-path worker が報告。

## 修正方向 (フラグのみ、実装判断は着手時に)

Cand 構造体 (node.mbt、completion DR-060 と共有) に path 情報を持たせるか、Pending にも境界 prepend を適用するかの二択が見えている。Cand は complete() の公開面と共有なので波及確認が必要。

## 受け入れ条件

- [ ] ネストしたコマンド内での値飢餓による missing_operand が、正しい祖先 path を持つ
- [ ] Cand / complete() 公開面への波及有無を確認・記録
