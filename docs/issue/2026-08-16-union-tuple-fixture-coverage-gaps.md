---
title: union/tuple 系 fixture 網羅の死角
status: open
category: task
created: 2026-08-16T14:15:58+09:00
last_read:
open_entered: 2026-08-16T14:15:58+09:00
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

# union/tuple 系 fixture 網羅の死角

## 概要

テスト網羅の系統的死角。Major指定の複数バグ (C2/C3/A4/C-4等) が未検出だった直接原因。

## 背景

- front_door 89 test に union/tuple 出現 0 件
- repeat グループ子 union の fixture 不在
- 親再開後 path の fixture 不在
- 多トークン viability の fixture 不在
- 統合報告全体としては union×構造の fixture 不在 / 数値境界(2^31/指数10桁超) / alias の command・leaf・positional 面 / errors.path の opt-in pin 不足 も同種の死角として指摘されている (P7)

対処方針: spec fixture 追加は lockstep 窓で管理する (project-lockstep-push-window の運用に従う)。wbtest は各修正 (issue #22/#23/A4/C-4等) と同時に追加するのが効率的。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] front_door test に union/tuple の代表 fixture が追加されている
- [ ] repeat グループ子 union / 親再開後 path / 多トークン viability の fixture が追加されている
- [ ] P7 指摘の関連死角 (union×構造 / 数値境界 / alias 各面 / errors.path opt-in pin) が個別に手当てされている、または追跡先が明記されている
