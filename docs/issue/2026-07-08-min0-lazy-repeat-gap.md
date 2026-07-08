---
title: min:0 + lazy:true の unbounded repeat で laziness が沈黙で失われる
status: open
category: bug
created: 2026-07-08T14:55:00+09:00
last_read:
open_entered: 2026-07-08T14:55:00+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: path-search 3 件解消 (min:0 → Many lowering) の監査で発見
---

# min:0 + lazy:true の unbounded repeat で laziness が沈黙で失われる

## 概要

`lower_positional` (installer.mbt) は unbounded repeat の `min:0` を `Many(head)` に lower する
(DR-043 取り分選好を持つ既存 spine 形)。しかし `Many` は greedy-only で AST に lazy knob が無く、
`repeat: {min: 0, lazy: true}` という spec 上有効な宣言 (DR-043 の lazy は宣言的選好) の laziness が
**エラーにも警告にもならず沈黙で greedy に落ちる**。

min>=1 経路は registry の `"lazy:" + name` marker で lazy を評価器に伝えているが、`Many` lowering は
registry を使わない (同一ノード再入) ため、この経路には lazy を運ぶ座席が無い。

## 受け入れ条件

- [ ] min:0 + lazy:true の表現手段を決める (候補: Many に lazy フィールド追加 / lazy 時のみ registry 経由の別 lowering / ManyLazy variant)。既存 Node の組合せ優先の原則 (design-thinking) と、取り分選好ロジックの重複回避を秤にかける
- [ ] spec 側 fixture (repeat-parse/ or path-search/) に min:0+lazy の輪郭 case を追加 (現状 fixture 未固定 = conformance では検出不能)
- [ ] 決まるまでの間、沈黙で落とすのではなく「min:0+lazy は未対応」を可視化するか検討 (installer で定義時エラー化 or 警告)
