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

- [x] 全 identifier 分類表 findings が land (2a035958、既知の誤記 2 件: filter 住人 19→7、`configured_short_type` は dead でなく使用中)
- [x] Filter 契約型の engine 帰属修正 + 3rd party filter が builtins 非依存で書けることの確認 (fba093d8、engine に filter 契約 + Registry 系統増設、synthetic 住人 wbtest で実証)
- [x] C 分類の pub 降格完了 (mbti drift gate で凍結) — 部分達成。段 0 c8585109 + mbti 凍結 0ac2843f。carrier 12 型 + D-3 の pub(all) 撤廃は MoonBit の可視性制約 (sibling package 限定の friend 可視性なし、builtins/kuu が境界越し直接構築) により今サイクル不成立 — (a) pub(all) 維持 + (c) installer 契約 opaque 化 issue へ統合、の統括裁定 2026-07-18
- [ ] 命名揺れの修正 (リネーム一覧は分類表にあり、段 4 相当は後続)
- [x] moon test / conformance green 維持、kuu-cli pin bump (393/393 + 280/686/0、kuu-cli 588/588 pin bump 06e088a2)

## 実施記録

- **TRI-Q 裁定**: Q1=分割案 / Q2=a TypeParseFail 開放 (4d5f290e) / Q4=a は径路整理として未実施・interpretation-view issue と統合予定 / Q8=a 組成必須化 (b2cda9d9)
- **carrier の実施形訂正の経緯**: 当初 carrier 型 (12 型) + D-3 の pub(all) 撤廃を段 0 実装範囲に含める想定だったが、MoonBit の可視性制約 (sibling package 限定の friend 可視性が無く、builtins/kuu が境界を越えて直接構築している) により opaque 化が今サイクルでは不成立と判明。pub(all) を維持したまま、installer 契約の opaque 化を独立 issue へ切り出す方針に訂正 (統括裁定 2026-07-18)
- **残作業**:
  - 命名揺れの修正 (リネーム一覧は分類表にあり、段 4 相当)
  - TRI-Q4 実装 (径路整理、kuu-cli 追随込み) — interpretation-view issue と統合予定
  - installer 契約 opaque 化の issue 起票

## 関連

- docs/findings/2026-07-18-api-cold-review-zero-knowledge.md (指摘の全文)
- spec の DR-110 (3 層境界裁定表 = 帰属判定の正本) / MDR-006 (実装設計)
- docs/issue/2026-07-17-interpretation-view-filter-front-door.md (径路多重の隣接残債)
