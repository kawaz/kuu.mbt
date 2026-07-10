---
title: DR-087 (default 遅延解決) に対する resolve フェーズの先詰め箇所の棚卸し
status: wip
category: task
created: 2026-07-10T22:49:09+09:00
last_read: 2026-07-10T22:55:24+09:00
open_entered: 2026-07-10T22:49:09+09:00
wip_entered: 2026-07-10T22:56:31+09:00
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

# DR-087 (default 遅延解決) に対する resolve フェーズの先詰め箇所の棚卸し

## 概要

spec DR-087 (spec commit ffbfc066) は default の意味論を「全解決後に空の cell へ
入る fallback (placeholder 設置 + 依存順の最終実体化)」と規範化した。kuu.mbt の
resolve フェーズが DR-087 と観測同値かを監査する。

## 背景

DR-087 の遅延解決モデルでは、default は解決過程の早い段階で先詰め (pre-fill) される
のではなく、他の値源 (cli / env / config / inherit) がすべて解決し尽くした後に
「空のまま残った cell」へ最後に流し込まれる。実体化順序も DR-087 §3 が
`config_path 解決 → 他要素の config 席参照 → 祖先 → inherit` の依存順を規定する。

kuu.mbt 側は過去の実装で default を早期に pre-fill している箇所が複数あり
(`resolve_ladder_below_cli` / `resolve_scope` / `resolve_scope_config` /
`apply_export_to_defaults` 等)、これが DR-087 の遅延モデルと観測同値かどうか
未検証。加えて、解決後の消費者 (`bool-requires` filter / `build_result` /
`proj_sources`) が中間状態 (default 未実体化の cell) を観測しうる経路が残って
いないかも確認が必要。特に `bool-requires` の `config_obj` 注入は対症療法的な
実装であり、遅延モデルが正しく成立していれば検査時点で全実体化済みのはずで、
注入自体が不要になる可能性がある。

`docs/issue/2026-07-09-bool-requires-config-inherit-gap.md` (config/inherit 値源を
見ない既知の限界) が、この遅延モデル導入で自然解消するかも合わせて確認する。

## 監査項目

- [ ] (1) default の先詰め (pre-fill) 実装箇所の列挙: `resolve_ladder_below_cli` /
      `resolve_scope` / `resolve_scope_config` / `apply_export_to_defaults` 等を
      grep して全箇所を洗い出す
- [ ] (2) 実体化順序が DR-087 §3 の依存順 (`config_path` 解決 → 他要素の config 席
      参照 → 祖先 → inherit) と観測同値かを確認する
- [ ] (3) 解決後の消費者 (`bool-requires` filter / `build_result` / `proj_sources`)
      が中間状態を観測しうる経路が残っていないかを確認する (`bool-requires` の
      `config_obj` 注入が対症療法かどうかの判定を含む)
- [ ] (4) CfgFiles (スコープ動的 config_file) 経路の `bool-requires` 残存ギャップ
      (`2026-07-09-bool-requires-config-inherit-gap.md` の実装で `config_obj=None`
      のまま残した箇所) が遅延モデルで自然解消するかを確認する

観測差が出た場面は spec 側へ fixture 起票を対で行う。

## 受け入れ条件

- [ ] 監査レポート (`docs/findings/`) を作成する
- [ ] 観測差 0 の確認、または差分の fixture 化と修正のいずれかを完了する
