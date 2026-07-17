---
title: binds → result object 構築の production 昇格
status: resolved
category: task
created: 2026-07-16T16:35:14+09:00
last_read:
open_entered: 2026-07-16T16:35:14+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-17T13:52:24+09:00
discard_reason:    # 1-line JSON array string[] 例: ["discarded","環境が変わった"]
pending_reason:    # 1-line JSON array string[] 例: ["pending","v2 待ち"]
close_reason: ["kuu-cli wire.mbt が OutputView (@kuu.output(ast, pbinds, resolved=rbinds)) 1発へ乗り換え (kuu-cli 86575f29、conformance 569/569 維持)、手組み is_excluded_cell/is_dd_cell_scan は削除。これを受けて kuu.mbt 側も is_sentinel を pub 降格 (92b9cee5、CI green)、kuu-cli pin bump 5e7d2911 で lockstep 完結","done"]
blocked_by:
origin: DR-109 波及 (統括起票)
---

# binds → result object 構築の production 昇格

## 概要

conformance runner 内に閉じている binds → result object 構築 (proj_result_export /
build_result 相当、accum_cells / apply_export_to_defaults / none_cells の 4 素材組み立て)
と sources 射影 (proj_sources)、warnings 構造化射影を front_door の production API に
昇格させる。

## 背景

spec の DR-109 §5 (UX-Q5=a) で UX-Q2/Q3 (CLI envelope 厳密一致 / sources 常時出力) と
同サイクルの解消が裁定された。kuu-cli の Binding 面 (DR-109 骨子柱 1) の土台であり、
現在 kuu-cli の wire.mbt は 4 素材の組み立てを runner から写した重複実装を持っている。
production API 化でこの重複を解消する。

## 受け入れ条件

- [x] result 構築 + sources 射影 + warnings 射影が front_door 経由で呼び出せる
      (シグネチャは MDR-005 の玄関原則に沿って設計) — `front_door.result`/`front_door.sources`
      追加、`warnings_structured` は既存 pub のまま (変更不要を確認)
- [x] conformance runner が新 API に乗り換えて重複を解消 — `proj_result_export`/`proj_sources`/
      `proj_sources_tree` を production 側ヘルパーへの薄い委譲に書き換え
- [x] kuu-cli の wire.mbt も乗り換え (kuu-cli 側は別リポ作業として r27 経由) — kuu-cli wire.mbt が
      OutputView (`@kuu.output(ast, pbinds, resolved=rbinds)`) 1 発へ乗り換え (kuu-cli 86575f29、
      conformance 569/569 維持)、手組み is_excluded_cell/is_dd_cell_scan は削除。これを受けて
      kuu.mbt 側も is_sentinel を pub 降格 (92b9cee5、CI green)、kuu-cli pin bump 5e7d2911 で
      lockstep 完結
- [x] moon test / conformance 全 green 維持 — `decoded=272 ran_cases=661 skipped=0 mismatches=0`、
      moon test 352/352 green (fresh 実行で確認)
- [x] MDR-005 に追記 note — 追記済み

## TODO

<!-- wip 時のみ -->
- [x] (別セッション) kuu-cli `wire.mbt` の乗り換え完了 (OutputView 1 発呼び出しへ、上記受け入れ条件参照)
