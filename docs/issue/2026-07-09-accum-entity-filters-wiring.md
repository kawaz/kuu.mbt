---
title: accum (multiple) 要素への filters / post_filters 配線 — resolve_entity の accum 対応
status: wip
category: design
created: 2026-07-09T10:26:36+09:00
last_read:
open_entered: 2026-07-09T10:26:36+09:00
wip_entered: 2026-07-09T17:01:55+09:00
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

# accum (multiple) 要素への filters / post_filters 配線 — resolve_entity の accum 対応

## 概要

filters registry 基盤 (commit 7f1b0c96) で filters/post_filters は **scalar cell (accum 無し) 限定**の動作保証。accum (append/flatten) 要素は resolve_entity を通らず、conformance harness の「生 CLI binding 配列を build_result へ直接渡す」バイパス経路 (scope_needs_default_ladder の use_resolve=false) に依存している。

filters を持つ entity で resolve 経路を強制すると、resolve_entity の「同名 binding は最後の 1 個へ fold」ロジックが accum の蓄積を壊す regression を実機確認済み (tags 2 値 → 1 値)。当該変更は撤回済み。

## 背景

issue filters-registry-foundation (2026-07-09) の実装中に発見。dr066-path worker の報告 (regression の実機観測込み) より。

## やること (着手時に設計)

- resolve_entity の accum 対応: 複数 piece の蓄積を resolve 層で正しく扱う (DR-009 の段 5 = 各 piece への each 適用、段 6 = accumulator、段 7 = 累積後 post_filters の順序を実現)
- harness のバイパス経路 (use_resolve 判定) の解消または正当化 — resolve 層が accum を扱えれば判定自体を消せる可能性
- accum + filters の conformance fixture (piece 単位 reject / 累積後 sort/unique 等)

## 受け入れ条件

- [ ] resolve_entity が accum (append/flatten) 要素に対して filters/post_filters を正しく適用できる
- [ ] harness の use_resolve バイパス判定が解消 or 正当化されている
- [ ] accum + filters の conformance fixture が追加されている
