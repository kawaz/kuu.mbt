---
title: accum (multiple) 要素への filters / post_filters 配線 — resolve_entity の accum 対応
status: wip
category: design
created: 2026-07-09T10:26:36+09:00
last_read:
open_entered: 2026-07-09T10:26:36+09:00
wip_entered: 2026-07-09T17:01:55+09:00
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ)
---

# accum (multiple) 要素への filters / post_filters 配線 — resolve_entity の accum 対応

## 概要

filters registry 基盤 (commit 7f1b0c96) で filters/post_filters は **scalar cell (accum 無し) 限定**の動作保証。accum (append/flatten) 要素は resolve_entity を通らず、conformance harness の「生 CLI binding 配列を build_result へ直接渡す」バイパス経路 (scope_needs_default_ladder の use_resolve=false) に依存している。

filters を持つ entity で resolve 経路を強制すると、resolve_entity の「同名 binding は最後の 1 個へ fold」ロジックが accum の蓄積を壊す regression を実機確認済み (tags 2 値 → 1 値)。当該変更は撤回済み。

## 背景

issue filters-registry-foundation (2026-07-09) の実装中に発見。dr066-path worker の報告 (regression の実機観測込み) より。

## 2026-07-09 調査結果とスコープ確定 (accum-filters-recon 4 次元調査)

- **regression の根**: resolve_entity_raw の CLI 座席 fold ループ (resolve.mbt L1505-1566) が e.accum を見ず DR-015 last-wins を一律適用して同名 Binding を 1 本に潰す。config 座席 (L1591-1609) には accum 時に複数 Binding を温存する対照実装が既にあり、修正のテンプレートになる
- **段 5 (filters each)**: apply_entity_filters (L1445-) は Binding 単位で全 Binding に適用するため、CLI 座席 fold を直せば accum でも自然に動く。1 piece でも reject すれば全体 failure (静かな除外ではない) — fixture の why に明記する
- **harness ガード**: scope_needs_default_ladder (json_conformance_wbtest.mbt L3285) の `e.accum is None &&` 条件が accum×filters を resolve 経路から除外している。CLI 座席修正とセットで外す
- **段 7 (累積後 post_filters) は本 issue から切り出し** → issue accum-post-filters-stage7 (AccumCell/build_result の設計変更 + 配列系 filter の registry 追加が前提で、fixture も現時点で書けないため)
- accum × Update 効果の意味論は仕様上未定義 (DR-077 の update はスカラー ledger 用)。本 issue では現状挙動を変えない — 遭遇したら報告

## 受け入れ条件 (段 7 切り出し後)

- [ ] resolve_entity (CLI 座席 fold) が accum (append/flatten) 要素の複数 Binding を温存し、filters (each、段 5) が accum 要素にも適用される
- [ ] harness の scope_needs_default_ladder から `e.accum is None &&` ガードが除去され、accum×filters が resolve 経路で走る (filters を持たない scope の else 分岐は残る = バイパスの正当化範囲を縮小)
- [ ] accum + filters(each) の conformance fixture (全 piece 通過で累積成功 / 1 piece reject で全体 failure kind=filter) が追加されている
- [ ] 既存 conformance (decoded=142/ran_cases=363/skipped=0/mismatches=0 + 新規分) が全 GREEN
