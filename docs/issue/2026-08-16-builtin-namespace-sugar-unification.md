---
title: builtin/ 糖衣の適用範囲拡張と factory 形態統一
status: open
category: design
created: 2026-08-16T14:13:49+09:00
last_read:
open_entered: 2026-08-16T14:13:49+09:00
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

# builtin/ 糖衣の適用範囲拡張と factory 形態統一

## 概要

DR-094 の `builtin/` 糖衣が type 参照のみ — filter/accumulator/collector/cell_fn/completer は明示 ns 綴りを解決できず、factory は手書き二択と3形態散在。

## 背景

- 場所: src/extension/registry.mbt:103
- DR-094 の `builtin/` 糖衣が type 参照のみに限られている
- filter/accumulator/collector/cell_fn/completer は明示 ns 綴りを解決できない
- factory は手書き二択と3形態散在 (統一されていない)

## 対処方針

糖衣処理の一元化設計が必要。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] {完了の判定基準}
