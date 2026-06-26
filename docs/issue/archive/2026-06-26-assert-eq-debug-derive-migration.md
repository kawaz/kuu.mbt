---
title: assert_eq → Debug derive migration
status: resolved
category: task
created: 2026-06-26T20:47:59+09:00
last_read:
open_entered: 2026-06-26T20:47:59+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-06-26T22:45:40+09:00
discard_reason:
pending_reason:
close_reason: ["implemented","commit:poqnwoxw d8c12dd9 refactor: deprecation warnings 800件根治"]
blocked_by:
origin: 自リポ TODO
---

# assert_eq → Debug derive migration

## 概要

moonbit 0.1.20260618 で `assert_eq` の型 trait 要件が `Show` → `Debug` に変わり、479 件の deprecation warning が複数 test ファイルで発生中。今回は対応せず、別セッションで集中作業する想定で起票。

## 背景

ast-spec ws (sid: 4285658F-66B4-4CB6-8BE6-1AB39DBB1C1B) から引き継いだ kuu.mbt 整備タスクの一部 (Task 5)。moon fmt 適用 (Task 2) と DR rename (Task 4) は完了済み。ユーザ意向で「今回は対応しない、別セッションで集中作業」。

関連: [[2026-06-26-try-operator-migration]] (同じく moon fmt 適用後の deprecation 対応)

## 影響ファイル

- src/core/cmd_wbtest.mbt
- src/core/constraint_wbtest.mbt
- src/core/error_wbtest.mbt
- src/core/filter_wbtest.mbt
- src/core/options.mbt
- src/core/parse_wbtest.mbt
- src/dx/dx_wbtest.mbt

## 対応方針

- `derive(Show)` → `derive(Debug)` または両方追加
- `assert_eq` 呼び出しは変更不要 (型 trait の要件変更だけ)

## 受け入れ条件

- [ ] 479 件の deprecation warning が解消されている
- [ ] 既存テストが全件通過している
