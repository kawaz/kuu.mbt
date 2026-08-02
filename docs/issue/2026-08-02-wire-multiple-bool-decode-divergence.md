---
title: wire decode が multiple: true (bool) を受けるが spec wire.schema.json は string|object の二形のみ
status: open
category: bug
created: 2026-08-02T12:18:09+09:00
last_read:
open_entered: 2026-08-02T12:18:09+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ) — W2-6 作業中の観測
---

# wire decode が multiple: true (bool) を受けるが spec wire.schema.json は string|object の二形のみ

## 概要

kuu.mbt の wire decode は `"multiple": true` (bool) を受理するが、spec の
`schema/wire.schema.json` の `multiple` はプリセット名 string | 詳細形 object の
oneOf として定義されており、bool を許さない。両者が乖離している。

## 背景

W2-6 作業中に実測: kuu.mbt の wire decode は `"multiple": true` を受理する
(`src/kuu/front_door_wbtest.mbt:1819` 等の wbtest がこの形を使用し、parse 成功する)。

一方 spec の `schema/wire.schema.json` の `multiple` はプリセット名 string |
詳細形 object の oneOf で bool を許さない。fixture lint で
`True is not valid under any of the given schemas` を実測済み (2026-08-02)。

schema が正なら decode 側は bool を definition-error/DecodeSkip に落とすべきで、
該当 wbtest の使用も書き換えが要る。逆に bool 糖衣を正とするなら spec 側の
schema/DR の追補が要る。どちらが正か、spec の DR-034/DR-080 系の規定を裏取りして
から採否を決めること。本 issue は部外者観測のフラグに留める (実装方針の断定はしない)。

関連: `docs/findings/2026-08-02-w2-6-value-space-static-resolution.md` の
「実用的な示唆」節。

## 受け入れ条件

- [ ] spec (DR-034/DR-080 系) を裏取りし、bool 糖衣を正とするか schema 準拠 (string|object のみ) を正とするか裁定する
- [ ] 裁定に従い、kuu.mbt の decode 実装と該当 wbtest、または spec 側 schema/DR のいずれかを是正する

## TODO

<!-- wip 時のみ -->
