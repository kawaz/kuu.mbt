---
title: 遅延述語の value_present が env/config/inherit を見ない (DR-047 §4 の『充填後の最終状態で評価』と乖離)
status: wip
category: bug
created: 2026-07-10T23:14:17+09:00
last_read: 2026-07-10T23:32:37+09:00
open_entered: 2026-07-10T23:14:17+09:00
wip_entered: 2026-07-10T23:33:33+09:00
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

# 遅延述語の value_present が env/config/inherit を見ない (DR-047 §4 の『充填後の最終状態で評価』と乖離)

## 概要

`value_present` (`src/core/eval.mbt:2621`) は `is_committed || has_default` のみで値の充足を判定しており、
値源ラダー (env / config / inherit) からの供給を見ていない。DR-047 §4 が定める「遅延述語は値源ラダーの
充填を済ませた最終状態に対して評価する」という規定と実装が乖離している。

## 背景

kuu (spec リポ) 側で resolve-first-constraint-pipeline の設計調査 (2026-07-10) を行った際に発見。

- DR-047 §4: 遅延述語は値源ラダー (env/config/inherit/default) の充填を済ませた最終状態に対して評価する、と明文化
- 実装: `value_present` は `is_committed || has_default` のみをチェックし、env/config/inherit 経由の供給を判定に含めていない
- 影響候補: 非 bool の `requires` 目的語、および `required` 自体の値充足判定。例えば CLI 引数も default も無く env のみから供給される必須項目が、誤って未充足 (missing) 判定される可能性がある
- 現行 fixture では該当ケースが見当たらない (grep 済み、mismatch は未発生 = 実機再現は未検証)
- 対応方針の見立て: resolve-first-constraint-pipeline (Phase 1) で `resolve_scope_tree` が「解決済み bindings」の唯一の生成源に昇格した後、`value_present` も同じパターンで「解決済み bindings の読者」に載せ替えるのが自然
- 同型の先行事例: issue `bool-requires-config-inherit-gap` (bool 版の requires で同種のギャップが既知)

## 受け入れ条件

- [ ] env のみから供給される必須項目 (CLI/default なし) を用いた実機再現テストで、現状の誤判定 (missing 判定) を確定させる
- [ ] 上記を再現する spec fixture を追加する
- [ ] `value_present` を「解決済み bindings の読者」に載せ替える修正を行う (resolve-first-constraint-pipeline Phase 1 の resolve_scope_tree 昇格後が望ましい)
- [ ] DR-047 §4 の規定と実装が一致することを確認する

## 関連

- DR-047 §4 (遅延述語の評価タイミング規定)
- issue `resolve-first-constraint-pipeline` (Phase 1 で resolve_scope_tree が bindings の唯一の生成源に昇格)
- issue `bool-requires-config-inherit-gap` (bool requires での同型の先行例)
