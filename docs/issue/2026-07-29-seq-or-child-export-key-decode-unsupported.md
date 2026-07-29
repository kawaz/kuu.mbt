---
title: seq/or の子要素 export_key を dec_or_leaf が未対応キーとして拒否する
status: open
category: bug
created: 2026-07-29T09:27:29+09:00
last_read:
open_entered: 2026-07-29T09:27:29+09:00
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

# seq/or の子要素 export_key を dec_or_leaf が未対応キーとして拒否する

## 概要

seq / or の子要素に付いた `export_key` を `dec_or_leaf` が未対応キーとして拒否し、
fixture が decode skip になる。

## 背景

実測 2026-07-29: spec fixture `value-typing/none-exclusion-in-renamed-repeat-rows.json`
(未 push) が「skip 1x or branch leaf has unsupported key 'export_key'」で decode skip になる。

spec 上は合法 (DR-052 §1 は export_key を結果キー軸の唯一の指定として任意の name 持ち要素に
許す、wire schema も通る)。positionals の子は dec_positional 経由なので通る
(`export-key/transparent-seq.json` は green) — `dec_or_leaf` 側だけの語彙 gap。

`dec_or_leaf` は installer 語彙駆動化済み (Phase 2 の decode 改修) だが `export_key` は
installer 語彙でなく基本属性側なので、`dec_or_leaf` の受理列への追加が必要。

関連 issue: `2026-07-29-inline-seq-repeat-rows-collapse-and-none-leak` (同 fixture の姉妹 file が依存)

## 受け入れ条件

- [ ] 当該 fixture (`value-typing/none-exclusion-in-renamed-repeat-rows.json`) の decode が
      skip せず通過すること
- [ ] `export_key` の rename が子セルの結果キーに正しく効くこと

## TODO

<!-- wip 時のみ -->
