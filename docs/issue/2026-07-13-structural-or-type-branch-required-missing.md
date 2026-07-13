---
title: structural or (type 付き枝) + required の組合せで、値供給時にも required missing になる
status: open
category: bug
created: 2026-07-13T10:02:52+09:00
last_read:
open_entered: 2026-07-13T10:02:52+09:00
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

# structural or (type 付き枝) + required の組合せで、値供給時にも required missing になる

## 概要

structural 形 (type 付き枝) の `or` + `required: true` の組合せで、**値を供給しても**
`required 'X' is missing` で failure になる挙動を観測した。

value-enum 形 (exact 枝) の `or` + `required: true` は正常動作する (`required_violated`
の element は or 親の name、自作 probe fixture で 0 mismatch を確認済み) のに対し、
structural 形 (type 付き枝) だけが値供給後も missing 扱いになる非対称。

## 背景

at-least-one 表現力調査 (2026-07-13、read-only worker) の副次発見。

- 発生源は `eval.mbt` / `resolve.mbt` の required 充足判定と推定 (未特定)
- conformance fixture にはこの組合せ (structural or + required) の実例が現状無く、
  grep 確認済みで未検出のまま埋もれていた
- 再現 probe は調査時の scratchpad (`fx-atleastone/probe-a/`) 配下にあったが、
  セッション固有ディレクトリのため現存しない可能性がある。再現は受け入れ条件の
  fixture 追加時に取り直す

関連: DR-093 (required の型委譲 — or 要素の充足定義)、DESIGN §9.1
「グループ的必須は or + required」

## 受け入れ条件

- [ ] spec 側に structural or (type 付き枝) + required の組合せを表す輪郭 fixture を
      追加して現象を pin する (fixture 先行ルール)
- [ ] 実装側 (`src/core/eval.mbt` / `src/core/resolve.mbt` の required 充足判定と推定)
      を修正する
