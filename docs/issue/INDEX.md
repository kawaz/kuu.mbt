# Issue Index

| date | category | status | slug | 概要 |
|---|---|---|---|---|
| 2026-07-07 | design | open | [accum-export-key-rename-asymmetry](./2026-07-07-accum-export-key-rename-asymmetry.md) | accum セルの export_key rename が未対応 (resolve 層の非対称) |
| 2026-07-08 | bug | open | [greedy-once-and-idxrepeat-premises](./2026-07-08-greedy-once-and-idxrepeat-premises.md) | greedy 1回制約・IdxRepeat bounded-head 前提・tried_triggers 失敗位置の追跡 (deep review low/medium 3件) |
| 2026-07-08 | design | open | [export-key-collision-identity-exposure-gap](./2026-07-08-export-key-collision-identity-exposure-gap.md) | find_export_collisions が identity 露出 (ek 未登録) 由来の衝突を見逃す |
| 2026-07-09 | design | wip | [accum-entity-filters-wiring](./2026-07-09-accum-entity-filters-wiring.md) | accum (multiple) 要素への filters/post_filters 配線 — resolve_entity の accum 対応 |
| 2026-07-09 | design | open | [bool-requires-config-inherit-gap](./2026-07-09-bool-requires-config-inherit-gap.md) | bool 目的語 requires の解決が config / inherit 値源を見ない (既知の限界) |
| 2026-07-09 | bug | open | [separator-non-string-type-parse-gap](./2026-07-09-separator-non-string-type-parse-gap.md) | separator 付き multiple の非 string 型が型 parse を経由しない (SepArg = VStr 固定) |
| 2026-07-09 | task | open | [regex-match-filter](./2026-07-09-regex-match-filter.md) | filters registry に regex_match を追加 (DR-040 語彙、正規表現エンジンの調達判断込み) |
| 2026-07-09 | bug | open | [config-string-pieceprocessor-gap](./2026-07-09-config-string-pieceprocessor-gap.md) | config の string 値が pieceProcessor (pre_filters → parse) を通らない (DR-050 乖離) |
| 2026-07-09 | bug | open | [env-separator-split-gap](./2026-07-09-env-separator-split-gap.md) | separator 付き multiple 要素の env 値が separator 分割されない (DR-049 乖離) |
