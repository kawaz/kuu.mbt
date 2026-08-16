---
title: name付き alias の独立entry出力が DR-113 §4.3/4.4 と衝突
status: open
category: design
created: 2026-08-16T14:15:06+09:00
last_read:
open_entered: 2026-08-16T14:15:06+09:00
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

# name付き alias の独立entry出力が DR-113 §4.3/4.4 と衝突

## 概要

## ⚠ spec 裁定待ち

## 概要 (D4)

name付き alias を options列の独立entryとして出す実装が DR-113 §4.3/4.4「独立一覧しない」に違反しているが、help_wbtest.mbt:63 が現挙動を意図的に pin しており、実装意図と spec が正面衝突している。

## 詳細

- 場所: src/kuu/help.mbt:693
- name付き alias を options列の独立entryとして出している
- DR-113 §4.3/4.4「独立一覧しない」に違反
- help_wbtest.mbt:63 が現挙動を意図的に pin 済み = 実装意図と spec の衝突

## 裁定が必要な点

DR-113 の規定通りに実装を直す (独立entryを廃止) か、DR-113 側を実装に合わせて改訂するかの裁定が必要。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 背景

## 受け入れ条件

- [ ] DR-113 と実装 (src/kuu/help.mbt:693, help_wbtest.mbt:63) の扱いについて裁定が下る
