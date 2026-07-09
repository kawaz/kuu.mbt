# Issue Index

| date | category | status | slug | 概要 |
|---|---|---|---|---|
| 2026-07-07 | design | open | [accum-export-key-rename-asymmetry](./2026-07-07-accum-export-key-rename-asymmetry.md) | accum セルの export_key rename が未対応 (resolve 層の非対称) |
| 2026-07-08 | bug | open | [greedy-once-and-idxrepeat-premises](./2026-07-08-greedy-once-and-idxrepeat-premises.md) | greedy 1回制約・IdxRepeat bounded-head 前提・tried_triggers 失敗位置の追跡 (deep review low/medium 3件) |
| 2026-07-08 | design | open | [export-key-collision-identity-exposure-gap](./2026-07-08-export-key-collision-identity-exposure-gap.md) | find_export_collisions が identity 露出 (ek 未登録) 由来の衝突を見逃す |
| 2026-07-09 | design | open | [bool-requires-config-inherit-gap](./2026-07-09-bool-requires-config-inherit-gap.md) | bool 目的語 requires の解決が config / inherit 値源を見ない (既知の限界) |
| 2026-07-09 | task | open | [regex-match-filter](./2026-07-09-regex-match-filter.md) | filters registry に regex_match を追加 (DR-040 語彙、正規表現エンジンの調達判断込み) |
| 2026-07-09 | bug | open | [config-string-pieceprocessor-gap](./2026-07-09-config-string-pieceprocessor-gap.md) | config の string 値が pieceProcessor (pre_filters → parse) を通らない (DR-050 乖離) |
| 2026-07-09 | bug | open | [env-separator-split-gap](./2026-07-09-env-separator-split-gap.md) | separator 付き multiple 要素の env 値が separator 分割されない (DR-049 乖離) |
| 2026-07-09 | design | open | [accum-post-filters-stage7](./2026-07-09-accum-post-filters-stage7.md) | accum セルの post_filters (DR-009 段 7、累積後 Acc→Acc) の配線 — build_result 層の設計変更が前提 |
| 2026-07-09 | design | wip | [accum-filters-non-set-op-semantics](./2026-07-09-accum-filters-non-set-op-semantics.md) | accum セルの filters(each) が非 Set 効果 (Default/Unset/Update) の placeholder 値にも走り得る |
| 2026-07-09 | task | open | [accum-fold-update-default-ops](./2026-07-09-accum-fold-update-default-ops.md) | build_result の ACCUMULATE fold が Update / Default op を解釈しない (実装未対応) |
