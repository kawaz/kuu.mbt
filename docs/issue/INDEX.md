# Issue Index

| date | category | status | slug | 概要 |
|---|---|---|---|---|
| 2026-07-18 | design | open | [api-surface-contract-triage](./2026-07-18-api-surface-contract-triage.md) | API 公開面の契約/実装仕分けと帰属修正 (Filter descriptor builtins 誤配置ほか、コールドレビュー起点) |
| 2026-07-18 | design | open | [feature-bundle-composition-api](./2026-07-18-feature-bundle-composition-api.md) | named bundle による組成 API — 機能単位で複数 registry への登録を 1 名前に束ねる (TRI-Q8 の発展) |
| 2026-07-18 | design | open | [installer-contract-opaque-carrier](./2026-07-18-installer-contract-opaque-carrier.md) | installer 契約の opaque 化と carrier 12 型の builtins 帰属 — DR-110 完全準拠への再設計 (TRI-Q1 後続) |
| 2026-07-25 | design | open | [fixpoint-convergence-tree-size-blind-spot](./2026-07-25-fixpoint-convergence-tree-size-blind-spot.md) | 不動点収束の判定が tree_size のみ — サイズ不変の in-place 書き換えを検出できない |
| 2026-07-25 | bug | open | [collision-drop-filter-identity-exposure-production-gap](./2026-07-25-collision-drop-filter-identity-exposure-production-gap.md) | 衝突解釈の drop 判定が identity 露出の rival を落とせない (production だけ未修正、wbtest は helper 経由で green) |
| 2026-07-25 | design | open | [static-lint-warn-and-diagnose-unimplemented](./2026-07-25-static-lint-warn-and-diagnose-unimplemented.md) | DESIGN §15.6 の静的 warn と §13.7 diagnose が未実装 — 露出キー衝突の潜在構造を誰も警告しない |
| 2026-07-25 | bug | open | [option-seq-named-children-not-folded-into-kv](./2026-07-25-option-seq-named-children-not-folded-into-kv.md) | option 直下 seq の名前付き子要素が kv に畳まれず、子ごとに別オブジェクト + 余分な配列階層になる |
| 2026-07-25 | bug | open | [config-file-multi-option-first-unresolved](./2026-07-25-config-file-multi-option-first-unresolved.md) | config_file option を 2 つ持つ定義で前段の config が解決されない (要調査、spec 規定有無から確認) |
| 2026-07-26 | design | open | [unify-flat-tree-sources-projection](./2026-07-26-unify-flat-tree-sources-projection.md) | has_commands 分岐そのものを廃止し sources 射影を flat/tree で統一する (export_key 修正 issue からの切り出し) |
| 2026-07-26 | design | open | [flat-tree-source-unset-default-mismatch](./2026-07-26-flat-tree-source-unset-default-mismatch.md) | flat 側の Unset=>Default 読み替えが tree 側に無い (sources 射影 export_key 修正 issue からの切り出し) |
| 2026-07-26 | bug | open | [command-scope-export-key-none-cell-leak](./2026-07-26-command-scope-export-key-none-cell-leak.md) | command scope の export_key rename があると type:none セルが result / sources に漏れる (DR-089 違反) |
| 2026-07-26 | bug | open | [or-seq-child-value-default-unsupported](./2026-07-26-or-seq-child-value-default-unsupported.md) | or/seq の structural child が value/default 等を持てない (schema と DR-067 に未追随) |
| 2026-07-26 | bug | open | [env-cli-accumulator-source-mismatch](./2026-07-26-env-cli-accumulator-source-mismatch.md) | env と CLI が同一 accumulator に供給されると最終値は CLI でも sources が env のまま (DR-031 違反) |
| 2026-07-26 | bug | open | [link-source-tag-cli-collapse](./2026-07-26-link-source-tag-cli-collapse.md) | link を独立した値源タグとして報告する (現状 cli に畳んでいる、DR-121 §4 未追随) |
| 2026-07-26 | bug | open | [unselected-transparent-command-flag-leak](./2026-07-26-unselected-transparent-command-flag-leak.md) | 未選択の transparent command 配下の未発火 flag が root に昇格して result に現れる (DR-051 違反、result/sources 非対称) |
