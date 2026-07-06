# Issue INDEX

active な issue の一覧。close 済みは archive/ にあり、ここには載せない。

| date | category | status | slug | 概要 |
|---|---|---|---|---|
| 2026-07-06 | bug | open | [collision-ambiguous-claimants-surfacing](./2026-07-06-collision-ambiguous-claimants-surfacing.md) | export-key 共露出衝突を Ambiguous + claimants で表面化する (DR-073 追従) |
| 2026-07-06 | task | open | [separator-whitelist-cleanup-after-pin](./2026-07-06-separator-whitelist-cleanup-after-pin.md) | spec-gaps #10/#9 pin (bare separator 不在) に伴う reader allowed_keys / installer 内部表現の掃除 |
| 2026-07-06 | bug | open | [idx-repeat-held-error-swallowed](./2026-07-06-idx-repeat-held-error-swallowed.md) | idx_repeat_eval が Held を握り潰し、repeat group の min 未達が空 errors になる (latent) |
| 2026-07-06 | bug | open | [transparent-scalar-promotion-no-sibling](./2026-07-06-transparent-scalar-promotion-no-sibling.md) | 透過要素の SCALAR 昇格判定が兄弟セル存在 heuristic で、兄弟なし kv 文脈に latent 穴 |
| 2026-07-06 | bug | open | [or-branch-id-attribution](./2026-07-06-or-branch-id-attribution.md) | or 値枝の制約違反 element が枝 id でなく親 name に帰属する (DR-052/055 §1) |
| 2026-07-05 | bug | open | [parse-conformance-gaps-batch1](./2026-07-05-parse-conformance-gaps-batch1.md) | 既知だが未起票の parse gap 5件 (export-key衝突/transparent-kv/空発火scope/shadow/二重repeat取り分) |
| 2026-07-05 | bug | open | [dd-placement-agnostic-collection](./2026-07-05-dd-placement-agnostic-collection.md) | dd の配置不問回収 (DR-064 §2) が inst_dd 未実装 — options[] 宣言の dd が install されない |
| 2026-07-05 | bug | open | [lowering-entity-generation-gaps](./2026-07-05-lowering-entity-generation-gaps.md) | lowering entity 生成の spec 乖離 2件 (dd options[] 配置 / global 子scope 誤生成) |

<!--
雛形メモ (migrate sub-command 用):

- 列構成は固定 (= 上記 5 列、列名と順序を変えない)
- 行の {{rows}} は migrate が走査後の active issue から生成 (= 全件再生成)
- ソート規約:
  1. status 優先順: idea → open → wip → blocked → pending-sublimation
  2. 同 status 内は date 降順 (= 新しい起票が上)
- 各行: `| YYYY-MM-DD | <category> | <status> | [<slug>](./YYYY-MM-DD-<slug>.md) | <本文 1 行目から 80 文字以内> |`
- 概要は 80 文字を超えたら末尾を「…」で省略
-->
