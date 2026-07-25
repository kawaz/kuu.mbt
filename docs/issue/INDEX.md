# Issue Index

| date | category | status | slug | 概要 |
|---|---|---|---|---|
| 2026-07-18 | design | open | [api-surface-contract-triage](./2026-07-18-api-surface-contract-triage.md) | API 公開面の契約/実装仕分けと帰属修正 (Filter descriptor builtins 誤配置ほか、コールドレビュー起点) |
| 2026-07-18 | design | open | [feature-bundle-composition-api](./2026-07-18-feature-bundle-composition-api.md) | named bundle による組成 API — 機能単位で複数 registry への登録を 1 名前に束ねる (TRI-Q8 の発展) |
| 2026-07-18 | design | open | [installer-contract-opaque-carrier](./2026-07-18-installer-contract-opaque-carrier.md) | installer 契約の opaque 化と carrier 12 型の builtins 帰属 — DR-110 完全準拠への再設計 (TRI-Q1 後続) |
| 2026-07-25 | design | open | [fixpoint-convergence-tree-size-blind-spot](./2026-07-25-fixpoint-convergence-tree-size-blind-spot.md) | 不動点収束の判定が tree_size のみ — サイズ不変の in-place 書き換えを検出できない |
| 2026-07-25 | bug | open | [collision-drop-filter-identity-exposure-production-gap](./2026-07-25-collision-drop-filter-identity-exposure-production-gap.md) | 衝突解釈の drop 判定が identity 露出の rival を落とせない (production だけ未修正、wbtest は helper 経由で green) |
| 2026-07-25 | bug | open | [sources-projection-skips-export-key-under-commands](./2026-07-25-sources-projection-skips-export-key-under-commands.md) | command 木がある定義で sources が export_key を適用しない (command を 1 つ足すだけでキー体系が変わる) |
| 2026-07-25 | design | open | [static-lint-warn-and-diagnose-unimplemented](./2026-07-25-static-lint-warn-and-diagnose-unimplemented.md) | DESIGN §15.6 の静的 warn と §13.7 diagnose が未実装 — 露出キー衝突の潜在構造を誰も警告しない |
| 2026-07-25 | bug | open | [option-seq-named-children-not-folded-into-kv](./2026-07-25-option-seq-named-children-not-folded-into-kv.md) | option 直下 seq の名前付き子要素が kv に畳まれず、子ごとに別オブジェクト + 余分な配列階層になる |
| 2026-07-25 | bug | open | [ref-template-seq-collapses-lastwins](./2026-07-25-ref-template-seq-collapses-lastwins.md) | ref テンプレ経由の無名子 seq が配列形を失い last-wins で 1 個に潰れる (inline seq bug の鏡像) |
| 2026-07-25 | bug | open | [config-file-multi-option-first-unresolved](./2026-07-25-config-file-multi-option-first-unresolved.md) | config_file option を 2 つ持つ定義で前段の config が解決されない (要調査、spec 規定有無から確認) |
