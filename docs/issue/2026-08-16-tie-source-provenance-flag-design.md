---
title: tie 判別を由来フラグで明示的に持ち回る設計
status: open
category: bug
created: 2026-08-16T14:12:52+09:00
last_read:
open_entered: 2026-08-16T14:12:52+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)
---

# tie 判別を由来フラグで明示的に持ち回る設計

## 概要

tie判別 `effects_ != raw.binds` が Winner 置換全般で真になり、消費 ambiguous でも sparse 射影が無効化され Default-source scalar が漏れる。

## 背景

- 場所: src/kuu/front_door.mbt:1123
- tie判別 `effects_ != raw.binds` が Winner 置換全般で真になる
- 消費 ambiguous でも sparse 射影が無効化され Default-source scalar が漏れる (実測 d=9 混入)
- DR-138 §5 carve-out は tie 限定のはずだが、実際にはより広い条件で発動している

対処方針: 由来フラグを構築時に持たせる設計が必要 (現状の `effects_ != raw.binds` という間接判定に代えて、tie/非tie を明示的に持ち回る)。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] {完了の判定基準}
