---
title: alias long_override の long:true が DR-076 §2 の flag 糖衣差し替えを受けない
status: open
category: design
created: 2026-07-08T20:39:02+09:00
last_read:
open_entered: 2026-07-08T20:39:02+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: dr066-path worker の spec fixture 移行報告 (2026-07-08、spec 側リポ kuu からの越境起票)
---

# alias long_override の long:true が DR-076 §2 の flag 糖衣差し替えを受けない

## 概要

canonical が flag の要素に対し、alias 独立要素で `long:true` を書くと、型に依存せず `[":set"]`
(値スロット形 main entry) にマップされ、flag が期待する `:set:true` (裸発火) への糖衣差し替え
(spec DR-076 §2 規則 1) が起きない。canonical 側は installer.mbt の resolve_long が型依存で
差し替えるが、alias 側 (dec_alias / desugar_aliases の long_override 経路) に相当ロジックが無い。

## 背景

2026-07-08 の spec fixture 移行作業 (fixtures/command-scope/shadowing.json 等の alias 化) で発見。
ワークアラウンドとして fixture は明示 colon DSL `long:[":set:true"]` を採用済み (これは正しく裸発火する)。
spec 側は fixture が明示形で書かれているため CI には影響なし。

## 受け入れ条件

- [ ] alias が wire 二形 (DR-071 §1) を保持しているか (LongDecl 化が alias 側に及んでいるか) を裏取りする
- [ ] 裏取り結果を踏まえ、alias の long_override も canonical の型で resolve_long 相当を通す修正方針を決める (フラグのみのスコープ)
- [ ] 修正または「対応しない」の裁定を残す
