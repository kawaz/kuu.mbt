---
title: API 公開面の契約/実装仕分けと帰属修正 — Filter descriptor の builtins 誤配置ほか (コールドレビュー起点)
status: open
category: design
created: 2026-07-18T13:59:57+09:00
last_read:
open_entered: 2026-07-18T13:59:57+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 自リポ TODO
---

# API 公開面の契約/実装仕分けと帰属修正 — Filter descriptor の builtins 誤配置ほか (コールドレビュー起点)

## 概要

ゼロ知識 API コールドレビュー (docs/findings/2026-07-18-api-cold-review-zero-knowledge.md) と kawaz の指摘 (2026-07-18) を受けた公開面の立て直し。kawaz 自己評価依頼への統括回答「胸を張って出せない。直したい」で方針確定、kawaz 承認済み。

## 背景

### 確定した問題 (実機確認済み)

1. **Filter 契約の帰属違反**: `FilterDescriptor` / `ArrayFilterDescriptor` / `FilterSignature` が builtins (src/builtins/filters.mbt) にのみ定義され engine に無い。DR-110 の「builtins は公開 extension interface のみを使う一住人 (3rd party と差し替え可能)」に対し、**3rd party が filter を作る際に builtins 依存を強制**する配置で、AccumulatorExt/MatcherExt 等 (engine 帰属) と非対称。M1〜M5 の物理移動で filter 系だけ契約とレジストリ実装の分離を落とした残債
2. **pub 過剰 (コールドレビュー指摘の真の改善分)**: 内部ヘルパ (`cat`/`to_chars`/`split_on`/`mkb`/`pe_*` 7 本/`argmin_action` 等) の pub、`Node` 18 バリアント全公開、`ElemDef` 55 field の pub(all) 外部構築可能。DR-110 が正当化するのは Ext trait 群と契約型のみで、これらは正当化されない
3. **命名揺れ**: engine `depr_marker` vs builtins `deprecation_mark`、暗号略語 (`mkb`/`pe_*`/`pend_value`)、`InstallBuild`/`InstallBuilder` の取り違えやすいペア
4. **径路多重**: `result`/`output`/`build_result` の 3 径路が型から読み分け不能 (コールドレビュー指摘 — is_sentinel→OutputView 乗り換え後の deprecated 整理残)

### 進め方 (kawaz 承認の段取り)

- Phase 1: **全数分類表** — mbti 3 本 (engine 685/builtins 208/kuu 102 行) の全 identifier を「A. 3rd party 拡張契約 (engine 帰属)」「B. kuu 玄関」「C. 実装詳細 (降格)」「D. 帰属間違い (移動)」に仕分けた findings。各判定に根拠 (DR-110 境界裁定表 / 実使用箇所) を付ける
- Phase 2: 仕分けの kawaz 裁定 (境界ケースのみ、導出可能分は進める)
- Phase 3: 実装 — Filter descriptor の engine 移動、pub 降格、命名修正。ElemDef 構造化は影響が大きいので別判断
- Phase 4: mbti 再生成 + moon test/conformance green + kuu-cli 追随 + lockstep push

### 順序の裁定

**本サイクルが help P2 (fixtures/help/ + help query 実装) より先** — 公開面が動くと P2 実装の足場も動くため (kawaz 承認 2026-07-18)。

## 受け入れ条件

- [ ] 全 identifier 分類表 findings が land
- [ ] Filter 契約型の engine 帰属修正 + 3rd party filter 実装が builtins 非依存で書けることの確認
- [ ] C 分類の pub 降格完了 (mbti drift gate で凍結)
- [ ] 命名揺れの修正 (リネーム一覧は分類表で確定)
- [ ] moon test / conformance green 維持、kuu-cli pin bump

## 関連

- docs/findings/2026-07-18-api-cold-review-zero-knowledge.md (指摘の全文)
- spec の DR-110 (3 層境界裁定表 = 帰属判定の正本) / MDR-006 (実装設計)
- docs/issue/2026-07-17-interpretation-view-filter-front-door.md (径路多重の隣接残債)
