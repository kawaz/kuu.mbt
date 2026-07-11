---
title: bool_parser factory が未実装 (configurable factory の config キー true_values/false_values/case_insensitive が decode 不能)
status: open
category: bug
created: 2026-07-12T04:58:47+09:00
last_read:
open_entered: 2026-07-12T04:58:47+09:00
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

# bool_parser factory が未実装 (configurable factory の config キー true_values/false_values/case_insensitive が decode 不能)

## 概要

`dec_types` の factory match に bool 分岐が無く、`TypeShadow` 構造体にも bool 用
config フィールドが無いため、configurable factory の config キー
(`true_values` / `false_values` / `case_insensitive`) を wire 経由で decode
できない。

## 背景

factory 名リネーム作業 (2026-07-12) の調査で発見。

- spec 正本は **DR-074 §3/§4** (bool の canonical 語彙: `true_values` default
  `["true","1"]` / `false_values` default `["false","0",""]` /
  `case_insensitive` default `true`) と **DR-061** (configurable factory)。
- `schema/builtin-descriptors.json` に `builtin/bool_parser` の宣言あり
  (`reasons: ["not_a_bool"]`)。
- 現状 bool の canonical default 挙動自体は `value_parser` 直実装で動いている
  (`value-typing/bool-canonical.json` は green) が、方言 config (yes/no
  opt-in 等) を wire で渡す経路が無い。
- bare/builtin ns 表記 (`bool_parser` / `builtin/bool_parser`) を渡すと
  unsupported factory の `DecodeSkip` になることは wbtest で固定済み
  (2026-07-12)。

## 対応方針 (着手時のメモ)

- `dec_types` に `bool_parser` 分岐を追加
- `TypeShadow` へ bool config 3 キー (`true_values` / `false_values` /
  `case_insensitive`) を追加
- `value_parser` への配線
- spec 側に方言 config の輪郭 fixture を追加 (要 fixture 追加 → pin bump)
- 旧名 alias (`kuu_bool_parser` 等) は不要 — bool に旧名実装は元々無い

## 受け入れ条件

- [ ] `dec_types` に bool_parser 分岐が実装されている
- [ ] `TypeShadow` に bool config 3 キーが追加され `value_parser` に配線されている
- [ ] bare/ns 表記 (`bool_parser` / `builtin/bool_parser`) の decode が通る
- [ ] config 3 キー (`true_values` / `false_values` / `case_insensitive`) の
      挙動が fixture で固定されている
- [ ] conformance green (spec 側 fixture 追加後の pin bump 込み)

## 関連

DR-074 §3/§4、DR-061、DR-094、DR-095
