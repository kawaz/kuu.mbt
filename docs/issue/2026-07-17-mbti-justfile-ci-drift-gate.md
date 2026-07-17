---
title: mbti 生成の justfile フロー組み込み + CI drift 検査
status: wip
category: task
created: 2026-07-17T09:38:43+09:00
last_read: 2026-07-17T09:58:24+09:00
open_entered: 2026-07-17T09:38:43+09:00
wip_entered: 2026-07-17T09:59:21+09:00
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:    # 1-line JSON array string[] 例: ["discarded","環境が変わった"]
pending_reason:    # 1-line JSON array string[] 例: ["pending","v2 待ち"]
close_reason:      # close 時に update が記録。1-line JSON array string[] 例: ["dr/DR-0007","implemented"]
blocked_by:
origin: 自リポ TODO (kawaz 発題)
---

# mbti 生成の justfile フロー組み込み + CI drift 検査

## 概要

`moon info` による `.mbti` (公開 API シグネチャ) 生成を justfile task 化し、
CI で drift (公開面の無自覚な変更) を検出するゲートを導入する。

## 背景

kawaz 発題 (2026-07-17)。M5 (pub 三分類棚卸し) 完了時に導入する:

1. `moon info` を just task 化
2. `pkg.generated.mbti` 3 本 (engine/builtins/kuu) を commit 対象にする
3. CI で 再生成 → diff → 差分があれば red にする drift gate を追加
   (公開面の変更を PR 上で明示させる)

M4 進行中での導入は見送り: 里程標ごとの mbti 差分がノイズになるため、
M5 (pub 三分類棚卸し完了) まで待つ (統括判断)。M4 期間中の中間確認は
green commit ごとのスナップショット生成で代替可能。

## 受け入れ条件

- [ ] `moon info` を実行する just task を追加
- [ ] `engine` / `builtins` / `kuu` の 3 pkg 分の `*.generated.mbti` を commit 対象化
- [ ] CI に 再生成 → diff → 差分あれば red、の drift gate を追加

## TODO

<!-- wip 時のみ -->
