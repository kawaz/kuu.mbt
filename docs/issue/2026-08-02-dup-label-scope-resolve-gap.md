---
title: duplicate raw label scope での resolve 相 entity 解決が候補を区別しない gap
status: open
category: bug
created: 2026-08-02T15:14:10+09:00
last_read:
open_entered: 2026-08-02T15:14:10+09:00
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

# duplicate raw label scope での resolve 相 entity 解決が候補を区別しない gap

## 概要

同一 scope 内に同じ raw label を持つ entity が複数存在する場合、resolve 相の
entity 解決が候補を区別せず、どの候補を指しているか一意に決定できない gap が
ある。

## 背景

W2-8 監査 (M3) で露出した gap。対応前に W2-8 監査記録 (M3) と resolve 相の
spec 側規定 (関連 DR) を突き合わせて、意図しない解決・曖昧性の見落としが
実際にどの経路で発生するかを裏取りしてから対応方針を検討すること。

## 受け入れ条件

- [ ] duplicate raw label を持つ scope での resolve 相の挙動を再現・特定する
- [ ] spec 側の resolve 相規定 (関連 DR) と照合し、期待される区別方法を明確化する
- [ ] resolve 相の entity 解決が候補を正しく区別するよう実装を修正する

## TODO

<!-- wip 時のみ -->
