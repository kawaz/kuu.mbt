---
title: try? operator migration
status: resolved
category: task
created: 2026-06-26T20:46:40+09:00
last_read:
open_entered: 2026-06-26T20:46:40+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-06-26T22:44:32+09:00
discard_reason:
pending_reason:
close_reason: ["implemented"]
blocked_by:
origin: 自リポ TODO
---

# try? operator migration

## 概要

moonbit 0.1.20260618 で `try?` operator が deprecated になった。1,160 件の warning が複数ファイルにわたって発生中。別セッションで集中作業する。

## 背景

ast-spec ws (sid: 4285658F-66B4-4CB6-8BE6-1AB39DBB1C1B) から引き継いだ kuu.mbt 整備タスクの一部 (Task 5)。moon fmt 適用 (Task 2) と DR rename (Task 4) は完了済み。ユーザ意向で「今回は対応しない、別セッションで集中作業」。

## 影響ファイル (6 ファイル)

- `src/_size_check/main.mbt:18`
- `src/contrib/timespec/timespec.mbt:16`
- `src/contrib/timespec/timespec_wbtest.mbt:52, 87`
- `src/core/parse_wbtest.mbt` 多数
- `src/wasm/main.mbt:1449, 1534, 1620`

## 対応方針

- success path = 単純除去（`try? expr` → `expr!`）
- error path = `try ... catch ... noraise` パターンに書き換え

## 受け入れ条件

- [ ] `moon check` で `try?` deprecated warning が 0 件になる
- [ ] 全テストが通過する

## TODO

<!-- wip 時のみ -->

- [ ] 各ファイルの `try?` 使用箇所をリストアップして変換方針を個別に確認
- [ ] 変換実施
- [ ] `moon test` で全テスト通過確認
