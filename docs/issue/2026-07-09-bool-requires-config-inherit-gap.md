---
title: bool 目的語 requires の解決が config / inherit 値源を見ない (既知の限界)
status: open
category: design
created: 2026-07-09T14:36:29+09:00
last_read:
open_entered: 2026-07-09T14:36:29+09:00
wip_entered:
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

# bool 目的語 requires の解決が config / inherit 値源を見ない (既知の限界)

## 概要

`apply_bool_requires_filter` (commit 5dd6b8a9、DR-047 §5 明確化の実装) の
`resolved_bool_value` は committed (CLI) → env → default の順でしか解決しない。
DR-047 §5 明確化は「値源不問 (cli / env / config / inherit / default)」なので、
config または inherit 経由でのみ true になる bool 目的語の requires は正しく
解決されない。

## 背景

- path filter で経路が誤って除外される (false negative — 本当は充足しているのに除外される)
- 逆に暗黙 `default:false` 判定で経路を通した後、config が false を供給しても再評価されない

由来: DR-047 §5 実装 (2026-07-09) の既知の限界として impl-worker2 が報告。
指定 3 ケース (CLI + env) は全て pin 済みで、config/inherit の実需要が出た時に着手する。

## 着手時の設計メモ

- `resolved_bool_value` へ config provider / inherit (親スコープ値) の参照を配線する。
  config は provider callback + config_key 解決 (`resolve_entity_raw` の持ち物) の再利用が要る
  — `apply_bool_requires_filter` の引数拡張か、`resolve_tree` との統合か
- inherit は経路ごとの親スコープ binding 探索が必要
- fixture: config 経由の true で経路生存 / inherit 経由の true で経路生存

## 受け入れ条件

- [ ] config 経由でのみ true になる bool requires が path filter で正しく生存する
- [ ] inherit 経由でのみ true になる bool requires が path filter で正しく生存する
- [ ] 既存 fixture (CLI/env pin 済み 3 ケース) が regress しないこと
