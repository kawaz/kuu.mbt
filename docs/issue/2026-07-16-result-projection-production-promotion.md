---
title: binds → result object 構築の production 昇格
status: open
category: task
created: 2026-07-16T16:35:14+09:00
last_read:
open_entered: 2026-07-16T16:35:14+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:    # 1-line JSON array string[] 例: ["discarded","環境が変わった"]
pending_reason:    # 1-line JSON array string[] 例: ["pending","v2 待ち"]
close_reason:      # close 時に update が記録。1-line JSON array string[] 例: ["dr/DR-0007","implemented"]
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

- [ ] result 構築 + sources 射影 + warnings 射影が front_door 経由で呼び出せる
      (シグネチャは MDR-005 の玄関原則に沿って設計)
- [ ] conformance runner が新 API に乗り換えて重複を解消
- [ ] kuu-cli の wire.mbt も乗り換え (kuu-cli 側は別リポ作業として r27 経由)
- [ ] moon test / conformance 全 green 維持
- [ ] MDR-005 に追記 note

## TODO

<!-- wip 時のみ -->
