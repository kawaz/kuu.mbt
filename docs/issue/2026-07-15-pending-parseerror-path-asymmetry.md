---
title: Pending→ParseError (missing_operand) 変換経路の path が Held 直接経路と非対称 (Cand.link escape の漏れ出し疑い)
status: open
category: bug
created: 2026-07-15T15:21:24+09:00
last_read:
open_entered: 2026-07-15T15:21:24+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: audit-held-path-rooted-escape 調査の副次発見 (archive 済み、close_reason の note 参照)
---

# Pending→ParseError (missing_operand) 変換経路の path が Held 直接経路と非対称 (Cand.link escape の漏れ出し疑い)

## 概要

audit-held-path-rooted-escape の調査 (2026-07-15) で実証された派生発見。Pending→ParseError
(missing_operand) 変換経路 (eval.mbt の変換箇所、調査時点で 3634-3639 付近) は Cand.path を
ParseError.path にそのままコピーするが、Cand.path は Cand.link の Rooted-escape を経由した
「宣言元 scope 基準」の値になっていることがある。一方 Held 直接経路は DR-066 §4 (発火時の動的
パス = walk 位置のコピー先 scope 基準) に従う。両者が食い違う (= 同一エラーで path が 2 通り
出る) ことがある。

## 背景

実機実証 (KUU_FIXTURES 注入): global option (number, global:true) を子 command `a` に持つ定義で
`["a","--level"]` (値 starve) → errors 2 件併存:

- `level@2/parse/missing_operand|path=[]` (宣言元基準、Pending 変換経路由来)
- `level@2/parse/missing_operand|path=["a"]` (コピー先基準、Held 経路由来)

DR-066 §4 の「発火時の動的パス」規範に照らすと Pending 変換経路側が設計不整合の疑い —
Cand.link (complete() 専用の内部実装、node.mbt コメントで purely an implementation detail と
明言) が ParseError 生成に漏れ出している副作用の可能性。

## 受け入れ条件

- [ ] Pending→ParseError 変換経路の path 決定を spec 期待 (DR-066 §4) と突き合わせて裁定
- [ ] 不整合なら修正 + 同一エラーの重複出力 (2 件併存) の是非も裁定
- [ ] 修正時は spec fixture で pin
- [ ] 整合と判明したら根拠追記で close

## TODO

<!-- wip 時のみ -->
