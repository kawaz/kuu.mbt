---
title: named group positional child の default 席が root scope に漏れる
status: resolved
category: bug
created: 2026-07-26T22:23:57+09:00
last_read: 2026-07-27T02:26:41+09:00
open_entered: 2026-07-26T22:23:57+09:00
wip_entered: 2026-07-27T02:29:35+09:00
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-27T03:17:42+09:00
discard_reason:
pending_reason:
close_reason: ["implemented: Entity が named positional group の declaring_path を保持し、発火した indexed row scope ごとに child ladder を解決。0 row で root child default を生成しない。string/bool 対偶・trailing positional・spec fixture を追加。commit 99ed766d、spec fixture a6a2dbe5。KUU_FIXTURES 付き 542/542、conformance 362 files/820 cases/mismatches=0、just lint green。", "implemented: DR-051 §2 / DR-121 §2.2 に従い、IndexedRepeat の 0 fire wrapper source `[]/xs=default` を structural projection として追加。実装 e92f6548、fixture de7cd1db。KUU_FIXTURES 付き 542/542、conformance 362 files/820 cases/mismatches=0、just lint green。"]
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

- [x] named group (`xs`) 配下の positional child (`v`) の default 席が wrapper 配下のアドレスに着席する (root 直下に漏れない)
- [x] DR-121 §3.2 の wrapper 結果アドレス畳み込み規定と整合する

## Follow-up (2026-07-27)

DR-051 §2 / DR-121 §2.2 に従い、IndexedRepeat の 0 fire wrapper source
`[]/xs=default` を structural projection として追加。実装 e92f6548、
fixture de7cd1db。KUU_FIXTURES 付き 542/542、conformance 362 files/820
cases/mismatches=0、just lint green。

## TODO

<!-- wip 時のみ -->

調査方針: DR-051/DR-121 に従い、0 fire は xs=[] の accumulator default 席のみ、1+ fire は named child を wrapper 配下で解決する。root scope への child default 解決を止め、wbtest + spec fixture で 0/1/2 row と partial row を固定する。
