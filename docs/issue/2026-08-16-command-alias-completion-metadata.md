---
title: command alias 候補に説明・(alias) 注記が付かない
status: open
category: bug
created: 2026-08-16T14:15:59+09:00
last_read:
open_entered: 2026-08-16T14:15:59+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt 全コードレビュー
---

# command alias 候補に説明・(alias) 注記が付かない

## 概要

command alias候補に説明も `(alias)` 注記も付かない。複数層にまたがる原因。

## 背景

- 場所: src/kuu/completion_query.mbt:373 ほか
- command alias 候補に説明も `(alias)` 注記も付かない
- 3重の原因: (1) engine の origin が alias自身の id (DR-104 §2 違反) (2) model 側 entry 不在 (3) is_alias:false

## 対処方針

engine/model の複数層修正が必要。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] {完了の判定基準}
