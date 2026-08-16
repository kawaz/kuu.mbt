# Issue Index

| date | category | status | slug | 概要 |
|---|---|---|---|---|
| 2026-08-16 | task | open | [decode-attribute-carry-allowlist-audit](./2026-08-16-decode-attribute-carry-allowlist-audit.md) | decode面の属性 silent discard 監査 (allowlist ⊆ carry 検査、A7+R5 m1 統合) |
| 2026-08-16 | bug | open | [tie-source-provenance-flag-design](./2026-08-16-tie-source-provenance-flag-design.md) | tie判別 `effects_ != raw.binds` が Winner 置換全般で真になり sparse 射影無効化で Default-source scalar が漏れる |
| 2026-08-16 | design | open | [union-fold-ledger-identity-redesign](./2026-08-16-union-fold-ledger-identity-redesign.md) | union/tuple セル fold・ledger・identity の再設計 (A1 + C-1検査脱落 + 関連 統合) |
| 2026-08-16 | bug | open | [placeholder-op-default-null-fallthrough](./2026-08-16-placeholder-op-default-null-fallthrough.md) | degenerate op=default で placeholder Bool(false) が result/sources に漏れる (A2+R6 F7 統合、裁定要) |
| 2026-08-14 | task | open | [ref-link-resolution-name-axis-to-id-axis](./2026-08-14-ref-link-resolution-name-axis-to-id-axis.md) | ref/link/observes/borrow の解決が name 軸のまま — DR-046 §1 の id 軸へ載せ替える |
| 2026-07-18 | design | open | [api-surface-contract-triage](./2026-07-18-api-surface-contract-triage.md) | API 公開面の契約/実装仕分けと帰属修正 (Filter descriptor builtins 誤配置ほか、コールドレビュー起点) |
| 2026-07-18 | design | open | [feature-bundle-composition-api](./2026-07-18-feature-bundle-composition-api.md) | named bundle による組成 API — 機能単位で複数 registry への登録を 1 名前に束ねる (TRI-Q8 の発展) |
| 2026-07-18 | design | open | [installer-contract-opaque-carrier](./2026-07-18-installer-contract-opaque-carrier.md) | installer 契約の opaque 化と carrier 12 型の builtins 帰属 — DR-110 完全準拠への再設計 (TRI-Q1 後続) |
| 2026-07-25 | design | open | [fixpoint-convergence-tree-size-blind-spot](./2026-07-25-fixpoint-convergence-tree-size-blind-spot.md) | 不動点収束の判定が tree_size のみ — サイズ不変の in-place 書き換えを検出できない |
| 2026-07-25 | design | open | [static-lint-warn-and-diagnose-unimplemented](./2026-07-25-static-lint-warn-and-diagnose-unimplemented.md) | DESIGN §15.6 の静的 warn と §13.7 diagnose が未実装 — 露出キー衝突の潜在構造を誰も警告しない |
| 2026-07-25 | bug | open | [config-file-multi-option-first-unresolved](./2026-07-25-config-file-multi-option-first-unresolved.md) | config_file option を 2 つ持つ定義で前段の config が解決されない (要調査、spec 規定有無から確認) |
| 2026-07-26 | design | wip | [dec-or-leaf-remaining-node-keys](./2026-07-26-dec-or-leaf-remaining-node-keys.md) | dec_or_leaf の残余キー同型化の棚卸し (repeat/multiple/optional が最優先、DR-067 §2 直接規定) |
| 2026-07-27 | design | open | [link-fixed-path-dsl-unimplemented](./2026-07-27-link-fixed-path-dsl-unimplemented.md) | link target の固定パス DSL (.field / [idx]) が未実装 (bare name のみ対応) |
| 2026-07-27 | design | open | [ref-link-structural-body-gate](./2026-07-27-ref-link-structural-body-gate.md) | ref+link / structural body (or/seq/Group) + link が invalid-range で塞がれている (spec 上は合法、解除条件付き) |
| 2026-07-27 | bug | open | [option-structural-or-group-outer-repeat-not-wired](./2026-07-27-option-structural-or-group-outer-repeat-not-wired.md) | option structural Or/Group の outer repeat が受理されるが消費構造へ配線されない (missing_operand 位相化の実装監査) |
| 2026-07-27 | design | open | [array-filter-provenance-contract-gap](./2026-07-27-array-filter-provenance-contract-gap.md) | array filter の公開契約に provenance が無く、同値 duplicate 並べ替え・値合成で source 復元が破綻する |
| 2026-07-29 | bug | open | [head-progresses-scoped-indexed-unconditional-true](./2026-07-29-head-progresses-scoped-indexed-unconditional-true.md) | zero-progress 静的検査の head_progresses が Scoped/ScopeNode/IndexedRepeat を無条件 true にしており消費0 head + 無制限 repeat をすり抜けうる |
| 2026-08-02 | task | open | [w2-2-deferred-hygiene](./2026-08-02-w2-2-deferred-hygiene.md) | W2-2 実装の据え置きハイジーン 3 件 (F4/F6/F8) — Union uniqueItems 順序盲点 / builtin prefix 二重実装 / DefError 部分可視性 |
| 2026-08-02 | bug | open | [wire-multiple-bool-decode-divergence](./2026-08-02-wire-multiple-bool-decode-divergence.md) | wire decode が multiple: true (bool) を受けるが spec wire.schema.json は string\|object の二形のみ (裁定要、部外者観測フラグ) |
| 2026-08-02 | task | open | [resident-output-contract-generalization](./2026-08-02-resident-output-contract-generalization.md) | resident output contract の一般化 (provider/filter/cell_fns/collector) — DR-126 §4 の適用範囲残余 |
| 2026-08-12 | task | open | [command-definition-error-parity-review-followup](./2026-08-12-command-definition-error-parity-review-followup.md) | command 担体の definition-error パリティ + 残余レビュー指摘 (DR-133/134 実装レビュー 2026-08-12) |
| 2026-08-12 | design | open | [m5-origin-spelling-pair-or-branch-duplicate-flag](./2026-08-12-m5-origin-spelling-pair-or-branch-duplicate-flag.md) | M5 の (origin,spelling) ペア判定により or-branch option で同一 flag が 2 行 emit される (DR-117 棄却案と衝突、裁定要) |
| 2026-08-12 | bug | open | [type-owned-completion-values-option-face-unknown](./2026-08-12-type-owned-completion-values-option-face-unknown.md) | 型所有の展開値候補が option 配置で UnknownFace に落ち説明を引き直せない (RE-1) |
| 2026-08-12 | design | open | [completion-query-residual-minors](./2026-08-12-completion-query-residual-minors.md) | completion_query の残 Minor 3 件 — fire_path 純度 pin / merge ペアキーの scope 欠落 / emit 畳みキーの取りこぼし (RE-3・RE-4・RE-6) |
| 2026-08-16 | design | open | [branch-reject-provenance](./2026-08-16-branch-reject-provenance.md) | abi.Branch / ParseError が Reject の出自を運ばない — 敗北 or 枝の診断が残余に混入する (DR-037 を表現できない) |
