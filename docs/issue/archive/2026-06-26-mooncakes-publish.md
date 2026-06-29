---
title: mooncakes.io に kawaz/kuu を publish する
status: discarded
category: task
created: 2026-06-26T23:54:55+09:00
last_read:
open_entered: 2026-06-26T23:54:55+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered: 2026-06-29T10:54:39+09:00
resolved_entered:
discard_reason: ["discarded:kawaz判断でROADMAP管理に移行、実作業時期が来たら再起票"]
pending_reason:
close_reason: ["discarded:kawaz判断でROADMAP管理に移行、実作業時期が来たら再起票"]
blocked_by:
origin: 自リポ TODO
---

# mooncakes.io に kawaz/kuu を publish する

## 概要

`kawaz/kuu` パッケージを mooncakes.io に publish して、ライブラリとしての kawaz/kuu を成立させる。

## 背景

- v0.1.1 として GH Release 公開済み (commit `41916fc1`)
- WASM/JS artifact は GH Release に添付済み (kuu-wasm-gc.wasm, kuu-wasm.wasm, kuu.js)
- mooncakes.io には未公開 (`curl -s https://mooncakes.io/api/v0/manifest/kawaz/kuu` で "Package not found")
- dep の `kawaz/grapheme@0.10.2` と `kawaz/timespec@0.2.0` は mooncakes.io 公開済み

## 受け入れ条件

- [ ] `moon publish` 実行成功 (mooncakes.io に kawaz/kuu が現れる)
- [ ] release.yml に `moon publish` ステップを追加済み (次回 VERSION bump で自動公開)

## TODO

- [ ] `moon publish` のフロー確認 (mooncakes.io の API トークン設定等)
- [ ] `moon.mod` の publish-ready 確認 (description, keywords, repository, exclude 等)
- [ ] README.md の品質確認 (mooncakes.io 表示用)
- [ ] `moon publish` 実行
- [ ] release.yml に `moon publish` ステップを追加
