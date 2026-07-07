---
title: greedy 1回制約・IdxRepeat bounded-head 前提・tried_triggers 失敗位置
status: open
category: bug
created: 2026-07-08T00:11:29+09:00
last_read:
open_entered: 2026-07-08T00:11:29+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 多視点レビュー (wf eval-core-deep-review)
---

# greedy 1回制約・IdxRepeat bounded-head 前提・tried_triggers 失敗位置

## 概要

多視点レビュー (wf eval-core-deep-review) で confirmed になった low/medium 3 件の追跡。いずれも eval-core の greedy/repeat 系の前提と、エラー報告 (tried_triggers) の伝搬に関わる。

## 背景

### (1) DR-041 §4「greedy のみ = 1 回」が未実装

同一 greedy entry が無制限に再発火し、`-v -v` のような入力が binding 2 個の単一経路 Success になってしまう。AtomicAST の greedy 面に repeat 有無を区別するフィールドが無いため、区別のための座席は installer / count registry 側に見込んでいる (Task 5 の count 型 fixture で顕在化予定)。

### (2) IdxRepeat の greedy-max が下流 backtrack を持たない

IdxRepeat の greedy-max 選択は下流への backtrack 機構を持たず、permissive head + 後続 positional の組合せで DR-043 の字義 (= 後退可能であるべき) と乖離する。bounded-head 前提を強制検査するか、installer 側の規約として明文化する必要がある。

### (3) tried_triggers (DR-053 §4) が root スコープ固定

「失敗位置で試行された綴り」を返す tried_triggers が root スコープに固定されており、subcommand 内で失敗した場合に子スコープの綴りが tried_triggers に出てこない。失敗位置を子スコープまで伝搬する設計 (= 素材収集の設計) が必要。

## 受け入れ条件

- [ ] (1) greedy entry の 1 回制約が installer/count registry いずれかの座席で実装され、`-v -v` のような入力が DR-041 §4 の意図通りに扱われる (fixture で確認)
- [ ] (2) IdxRepeat greedy-max の backtrack 有無について、実装追加 or 「bounded-head 前提」を installer 規約として明文化するかの方針が決まり反映される
- [ ] (3) tried_triggers が失敗した子スコープの綴りを含むよう伝搬される、または現状の root 固定が仕様である旨が明文化される
- [ ] 修正時は MDR-002 の TODO 節と同期する

## TODO

<!-- wip 時のみ -->
