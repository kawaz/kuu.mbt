---
title: values sugar / or-of-exacts の option で trigger 候補の origin が要素名でなく綴りになり help が消える
status: resolved
category: bug
created: 2026-08-12T11:01:48+09:00
last_read:
open_entered: 2026-08-12T11:01:48+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-08-12T13:30:55+09:00
discard_reason:
pending_reason:
close_reason: ["done:eval.mbt の origin fixup を head Exact 限定に修正、spec fixture complete/values-sugar-or-exacts-origin.json で green (commit 5c08dcca)"]
blocked_by:
origin: 自リポ TODO
---

# values sugar / or-of-exacts の option で trigger 候補の origin が要素名でなく綴りになり help が消える

## 概要

values sugar / or-of-exacts で組んだ option の trigger 候補を生成すると、origin が要素名でなく綴り (例: `--mode`) になってしまう。DR-116 §4 の「origin から説明を引き直す」ロジックがこの綴り origin では効かず、結果として help 説明が消える。

## 背景

DR-116 §4 は trigger 候補の origin から help 文言を再引きする設計になっているが、values sugar / or-of-exacts 由来の option ではこの origin が要素名 (要素識別子) ではなく綴り文字列そのものに置き換わってしまっている。origin の意味論が経路によって食い違っており、DR-116 §4 が前提とする「origin = 要素名」が崩れているケースがある。

## 受け入れ条件

- [ ] values sugar / or-of-exacts 経由の option で trigger 候補の origin が何になっているか実装を確認する
- [ ] DR-116 §4 の説明引き直しロジックが期待通り動くよう origin の生成経路を揃えるか、または綴り origin 用の別経路を設計する
- [ ] help 説明が消えないことを回帰確認する
