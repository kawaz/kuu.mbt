---
title: preset canonical 展開の HelpMetaInstaller.apply 移送 (M3c-D/M5-4 残タスク)
status: open
category: task
created: 2026-07-20T20:22:55+09:00
last_read:
open_entered: 2026-07-20T20:22:55+09:00
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

# preset canonical 展開の HelpMetaInstaller.apply 移送 (M3c-D/M5-4 残タスク)

## 概要

P3 で 5 つの help preset は `wire_decode` の暫定処理 (flag_type + fail_action +
help.mbt 側 defaulting) で全 fixture green を達成した。しかし DR-113 §1 が
定める「help_installer.apply による preset canonical expansion」の完全形は
未移送のまま残っている。完全形として必要なのは:

- 内部セル `#help` 系 5 種の cell registry 登録
- 発火時の `cell_fns` set 供給
- `help_category` の `or[bool, string]` wire canonical 展開
- `InstallOutput.entities` へのセル追加

これらを `HelpMetaInstaller.apply` 側へ正式に移す。

## 背景

p3-m4 worker による影響見積もりは 600-1500 行、`eval` / `installer` /
`cell_fns` / `wire_decode` を跨ぐ規模。conformance 上は現状の暫定処理で
完全 green のため機能欠損ではなく、内部品質・DR 準拠構造の改善位相の課題。

関連:
- `docs/findings/2026-07-20-p3-help-refactor-survey.md`
- DR-113 §1/§2 (spec リポ)

同位相の残メモ (未着手、将来 corner-case fixture が生えたら再検討):
provenance の installer 側 stamp 化も見送り済み。help.mbt 側の逆推定で
全 fixture green を達成しており、p3-m4 の design-thinking 判断
(2026-07-20) として現時点では見送りとした。

## 受け入れ条件

- [ ] `#help` 系 5 種の内部セルが cell registry に登録されている
- [ ] 発火時に `cell_fns` set が正しく供給される
- [ ] `help_category` の `or[bool, string]` が wire canonical 形式で展開される
- [ ] `InstallOutput.entities` にセルが追加される
- [ ] DR-113 §1 の記述と実装が一致することを確認 (双方向整合性チェック)
- [ ] 着手前後で eval 経路の regression が無いことを確認 (全 fixture green 維持)

## TODO

<!-- wip 時のみ -->
