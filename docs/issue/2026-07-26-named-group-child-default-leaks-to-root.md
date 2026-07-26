---
title: named group positional child の default 席が root scope に漏れる
status: open
category: bug
created: 2026-07-26T22:23:57+09:00
last_read:
open_entered: 2026-07-26T22:23:57+09:00
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

# named group positional child の default 席が root scope に漏れる

## 概要

実測 (2026-07-26): 定義
`{"positionals":[{"name":"xs","repeat":{"min":0,"max":2},"positionals":[{"name":"k","type":"string"},{"name":"v","type":"string","default":"D"}]}]}`
+ args `["a","b"]` で sources に `[]`/`v=default` が出る (root 直下の `v` として binding が生える)。

## 背景

原因: structural child を `ensure_entity` で entity 登録すると default 席が宣言 scope (root) の
Phase 3b (resolve.mbt:3046 付近) で解決され、wrapper (`xs`) の外に着席する。期待は wrapper 配下
の席 (または要素 addressing 裁定に従う形)。DR-121 §3.2「nameless/named child の値は wrapper の
結果アドレスに畳まれる」と食い違う。

or/seq child の literal 実装 (2026-07-26) では `ensure_entity_body` を skip してこの経路を避けた
— named group positional の default は skip できない (真のラダー席が要る) ので別の直し方が要る。

## 受け入れ条件

- [ ] named group (`xs`) 配下の positional child (`v`) の default 席が wrapper 配下のアドレスに着席する (root 直下に漏れない)
- [ ] DR-121 §3.2 の wrapper 結果アドレス畳み込み規定と整合する

## TODO

<!-- wip 時のみ -->
