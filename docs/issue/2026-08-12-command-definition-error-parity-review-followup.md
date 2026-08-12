---
title: command 担体の definition-error パリティ + 残余レビュー指摘 (DR-133/134 実装レビュー 2026-08-12)
status: open
category: task
created: 2026-08-12T12:38:27+09:00
last_read:
open_entered: 2026-08-12T12:38:27+09:00
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

# command 担体の definition-error パリティ + 残余レビュー指摘 (DR-133/134 実装レビュー 2026-08-12)

## 概要

DR-133/134 実装 (commit 61715d3c) のレビューで見つかった 3 件の指摘をまとめて記録する。

1. **M1 = command 担体の definition-error 検査未合流**
   command 担体 (value/default/default_fn) が element 系 definition-error 検査を素通しする。
   `lowering.mbt` の `collect_default_fn_errors` (:4016) / `collect_scalar_array_default` (:5473)
   は options/positionals しか歩かず、command の default+default_fn 併用・default_fn 名の
   UnknownVocab・sentinel 戻り検査・observes cycle graph 不参加が全部素通しになっている。
   DR-134 §5「値供給は既存 node 意味論のまま」から導出可能なので裁定不要。command 担体を
   疑似 ElementDef として既存検査群に合流させるか、専用検査を足す。spec 側 fixture
   (`definition-error/` に command 版) も要る。
   配列 value と透過 value command は spec の CVQ-Q1/Q2 裁定待ちで本 issue のスコープ外。

2. **m1 = committed 判定から Link 由来供給が漏れる**
   `resolve.mbt:4817` の committed 判定 (`source is Cli|Env`) から Link 由来の供給が漏れている。
   link が config_file セルを target にできるかの実測が先。できるなら DR-133 §3 の
   「cli/env 明示」に Link を含むかの Q 化が必要。

3. **m3 = 内部セル negative list の (path,name) 同定不備**
   内部セルの negative list が (path,name) で同定されているため、config_file と同名の
   通常要素が同スコープに並ぶと、実セルの binding/[] が巻き添えで落ちる (既存欠陥)。
   `resolve.mbt:1055` / `resolve.mbt:1329` 参照。

レビュー出典: fable5-high 2026-08-12。レビュー担当の指摘は実物照合済み。

## 背景

DR-133/134 (config_file 担体・command 担体まわり) の実装レビューで見つかった残余指摘。
M1 は definition-error 検査のパリティ欠如、m1/m3 は既存の細部欠陥。

## 受け入れ条件

- [ ] M1: command 担体の default+default_fn 併用・default_fn 名 UnknownVocab・sentinel 戻り検査・
      observes cycle graph が element 系検査と同等にカバーされる (spec fixture 込み)
- [ ] m1: Link 由来供給が committed 判定に含まれるべきか実測 + 必要なら Q 化
- [ ] m3: config_file と同名の通常要素が同スコープに並んでも実セルの binding/[] が巻き添えで
      落ちないよう negative list の同定方法を修正

## TODO

<!-- wip 時のみ -->
