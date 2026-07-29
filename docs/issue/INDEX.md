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
| 2026-07-26 | design | wip | [dec-or-leaf-remaining-node-keys](./2026-07-26-dec-or-leaf-remaining-node-keys.md) | dec_or_leaf の残余キー同型化の棚卸し (repeat/multiple/optional が最優先、DR-067 §2 直接規定) |
| 2026-07-27 | design | open | [link-fixed-path-dsl-unimplemented](./2026-07-27-link-fixed-path-dsl-unimplemented.md) | link target の固定パス DSL (.field / [idx]) が未実装 (bare name のみ対応) |
| 2026-07-27 | design | open | [ref-link-structural-body-gate](./2026-07-27-ref-link-structural-body-gate.md) | ref+link / structural body (or/seq/Group) + link が invalid-range で塞がれている (spec 上は合法、解除条件付き) |
| 2026-07-27 | bug | open | [command-node-value-unimplemented](./2026-07-27-command-node-value-unimplemented.md) | command node の value: — carrier 不在 + 意味論未規定でスコープ外に切った分 |
| 2026-07-27 | bug | open | [option-structural-or-group-outer-repeat-not-wired](./2026-07-27-option-structural-or-group-outer-repeat-not-wired.md) | option structural Or/Group の outer repeat が受理されるが消費構造へ配線されない (missing_operand 位相化の実装監査) |
| 2026-07-27 | design | open | [array-filter-provenance-contract-gap](./2026-07-27-array-filter-provenance-contract-gap.md) | array filter の公開契約に provenance が無く、同値 duplicate 並べ替え・値合成で source 復元が破綻する |
| 2026-07-29 | bug | open | [head-progresses-scoped-indexed-unconditional-true](./2026-07-29-head-progresses-scoped-indexed-unconditional-true.md) | zero-progress 静的検査の head_progresses が Scoped/ScopeNode/IndexedRepeat を無条件 true にしており消費0 head + 無制限 repeat をすり抜けうる |
| 2026-07-29 | bug | open | [or-accum-rows-leak-unselected-branch-empty-array](./2026-07-29-or-accum-rows-leak-unselected-branch-empty-array.md) | named or wrapper に multiple (accumulator) を付けると発火 row に未選択枝の空配列セルが混入する |
| 2026-07-29 | bug | open | [inline-seq-repeat-rows-collapse-and-none-leak](./2026-07-29-inline-seq-repeat-rows-collapse-and-none-leak.md) | repeat 付き positional の inline seq 子が行配列にならず last-wins で潰れる + none セルが effects/result/sources に漏れる |
