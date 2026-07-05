# Issue INDEX

active な issue の一覧。close 済みは archive/ にあり、ここには載せない。

| date | category | status | slug | 概要 |
|---|---|---|---|---|
| 2026-07-05 | bug | open | [structural-failure-empty-errors](./2026-07-05-structural-failure-empty-errors.md) | トークン枯渇・残余の failure で errors が空になる — held-error が未捕捉 (DR-053/065) |
| 2026-07-05 | bug | open | [dd-placement-agnostic-collection](./2026-07-05-dd-placement-agnostic-collection.md) | dd の配置不問回収 (DR-064 §2) が inst_dd 未実装 — options[] 宣言の dd が install されない |

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
