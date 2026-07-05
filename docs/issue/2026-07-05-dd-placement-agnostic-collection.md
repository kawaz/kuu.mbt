---
title: dd の配置不問回収 (DR-064 §2) が inst_dd 未実装 — options[] 宣言の dd が install されない
status: open
category: bug
created: 2026-07-05T13:17:34+09:00
last_read:
open_entered: 2026-07-05T13:17:34+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (docs/decisions/DR-064)
---

# dd の配置不問回収 (DR-064 §2) が inst_dd 未実装 — options[] 宣言の dd が install されない

## 概要

kuu spec (kawaz/kuu main の `docs/decisions/DR-064` §2「dd は配置不問で回収」) は
`--` (dd) を `def.positionals` / `def.options[]` のどちらに宣言していても
install 時に回収されるべきと定めているが、slice の `inst_dd`
(`installer.mbt:544-550`) は `def.positionals` のみを走査しており、
`options[]` 側 (canonical 配置) に宣言された dd は install されない。
結果として、その dd に対する `--` の sever (以降の引数を非オプション化する
挙動) が効かない。

## 背景

第 19 弾 fixture runner (`poc/fixture_runner_wbtest.mbt`) で
`fixtures/dd/*.json` を実食したところ、8 cases 中 6 case が仕様の
faithful 転記であるにもかかわらず slice 側の実装と乖離した
(残り 2 case は DIAG = dd を positionals に移設したコントロールケースで、
これは期待通り一致する)。つまり乖離は 100% slice 側の実装漏れであり、
fixture 側の記述が誤っているわけではない。

一次資料:

- `kawaz/kuu` main の `docs/decisions/DR-064` (§2「dd は配置不問で回収」)
- `kawaz/kuu` main の `fixtures/dd/*.json` (8 cases)
- slice の `poc/fixture_runner_wbtest.mbt` ヘッダコメント (実食結果の記録)
- slice の `installer.mbt:544-550` (`inst_dd` の現行実装、`def.positionals` のみ走査)

## 受け入れ条件

- [ ] `inst_dd` が `def.options` 側に宣言された dd も走査し、install 対象にする
      (実装方針は要裏取り: `inst_dd` 側で両面走査するか、`clone_def` で dd を
      単一の面へ正規化するか — このリポの担当セッションが選定する)
- [ ] `fixtures/dd/*.json` の faithful 8 cases が仕様準拠の期待値で全て一致する
- [ ] `fixture_runner_wbtest.mbt` の DIAG コントロールケース (dd を positionals
      に移設して期待一致を確認していた 2 case) は目的を終えるため削除する

## TODO

<!-- wip 時のみ -->
