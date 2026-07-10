---
title: パイプライン再構成 — resolve 先行 + 制約検査は解決済み bindings の読者に (DR-087 §4 の実装形)
status: open
category: design
created: 2026-07-10T23:02:42+09:00
last_read: 2026-07-10T23:06:41+09:00
open_entered: 2026-07-10T23:02:42+09:00
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

# パイプライン再構成 — resolve 先行 + 制約検査は解決済み bindings の読者に (DR-087 §4 の実装形)

## 概要

DR-087 棚卸し audit (issue `lazy-default-resolution-audit`、2026-07-10) の本命 finding への根本対策。

現状 `run_case` / 本体パイプラインでは `apply_bool_requires_filter` が `resolve_tree` より前に raw CLI-only Outcome へ適用され、自前ミニラダー (`resolved_bool_value_ladder`) で値源を再解決している — DR-087「採用しなかった案」#2 (消費者ごとの値源再解決) に該当する構造。

## 背景

上記構造の帰結:

1. `resolve_ladder_below_cli` と `resolved_bool_value_ladder` の優先順位ロジックが重複している (`default_fns` 導入時に両方の更新が必要になる)
2. `CfgFiles` (スコープ動的 config_file) × bool-requires の理論的観測差がある。`config_obj` 単一注入契約では `CfgFiles` を渡せず常に `None` になる (該当 fixture は未存在、再構成後に fixture 化する)

対策: resolve を無条件先行させ、制約検査 (bool-requires 含む) を「全実体化済み bindings の読者」に再構成する。Ambiguous outcome の各解釈ごとに resolve を先出しする必要があり、設計規模の変更になる。

## 受け入れ条件

- [ ] 制約検査が resolve 済み値のみを参照する (`config_obj` 注入と `resolved_bool_value_ladder` の廃止)
- [ ] CfgFiles × bool-requires の fixture を spec に追加して green
- [ ] conformance 全 green を維持

## 関連

- DR-087
- issue `bool-requires-config-inherit-gap` (対症)
- issue `lazy-default-resolution-audit` (発見元)
