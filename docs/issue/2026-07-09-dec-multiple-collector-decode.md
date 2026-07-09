---
title: conformance harness の dec_multiple に collector 属性の decode を追加
status: open
category: task
created: 2026-07-09T10:59:04+09:00
last_read:
open_entered: 2026-07-09T10:59:04+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 依頼元プロジェクト kuu (spec リポ)
---

# conformance harness の dec_multiple に collector 属性の decode を追加

## 概要

unwrap_single は resolve.mbt:632 に runtime 実装済み (DR-034 縮退ケース) だが、conformance harness の dec_multiple (json_conformance_wbtest.mbt:1875 付近) の allowed_keys が ["accumulator", "separator"] のみで **collector キーを受理しない** (accumulator も "append" のみ)。DR-036 の multiple registry 定義 (accumulator + collector + separator の属性セット、collector は filters registry から引く) の wire 経路が塞がっている。

## 受け入れ条件

- [ ] dec_multiple に collector キー受理 + 実体 lookup 配線 (unwrap_single、可能なら to_set / from_entries も)
- [ ] accumulator の受理語彙も DR-036 と突き合わせて拡張要否を判断
- [ ] 追いつき後、spec 側で unwrap_single fixture (multiple: {accumulator:"append", collector:"unwrap_single"}、slice phase14:157 相当) を追加 (蒸留 1:1 audit の漏れ #3、spec findings/2026-07-09-distill-1to1-coverage-audit.md)

## 背景

fixture-batch worker の追調査 (2026-07-09)。座席裁定 (multiple の collector 属性、実体は filters registry) は team-lead 済み。

## TODO

<!-- wip 時のみ -->
