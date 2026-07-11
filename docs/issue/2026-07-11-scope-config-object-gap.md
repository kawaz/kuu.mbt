---
title: DESIGN §7.2 の scope config オブジェクト機構が未実装 (long_prefix 等 6 フィールド + 階層継承)
status: open
category: task
created: 2026-07-11T11:10:52+09:00
last_read:
open_entered: 2026-07-11T11:10:52+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: DR-091 §3 実装調査
---

# DESIGN §7.2 の scope config オブジェクト機構が未実装 (long_prefix 等 6 フィールド + 階層継承)

## 概要

DESIGN §7.2 が規定する config オブジェクト (`long_prefix` / `short_prefix` / `env_prefix` / `auto_env` / `allow_equal_separator` / `short_combine`、階層継承と子 command への伝播) が kuu.mbt に一切実装されておらず、`--` 等が `inst_long` 内に文字列リテラルでハードコードされている。

## 背景

DR-091 §3 実装の調査 (2026-07-11) で発見。DR-091 §3 対応では最小実装 (Definition 直下に `long_prefix` + `require_equal_separator` の 2 フィールド、継承なし) を採った。残る 4 フィールドと階層継承・子伝播が本 issue の管掌。

着手時は spec 側の fixture (`lowering/config/basic.json` 等の既存 pin) と DESIGN §7.2 を正本にする。

関連: DR-091 §3 / DESIGN §7.2。

## 受け入れ条件

- [ ] config オブジェクトの decode + 階層継承
- [ ] 既存の最小実装 2 フィールド (`long_prefix` / `require_equal_separator`) の config オブジェクトへの統合
- [ ] conformance 全 green

## TODO

<!-- wip 時のみ -->
