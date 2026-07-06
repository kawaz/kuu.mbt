---
title: parse_definition に構造 or (多 cell 枝) の builder が無く、path-search の蒸留 fixture 3 本が skip 凍結中
status: open
category: bug
created: 2026-07-06T11:40:12+09:00
last_read:
open_entered: 2026-07-06T11:40:12+09:00
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

# parse_definition に構造 or (多 cell 枝) の builder が無く、path-search の蒸留 fixture 3 本が skip 凍結中

## 概要

spec-gaps #1 の決着 (2026-07-06) で slice テスト 3 件が wire form へ蒸留されたが、
slice の `ElemDef` は flat (1 element = 1 value cell) で、枝ごとに別の named cell を
束縛する構造 or (`Or([Seq([typed cells]), ...])`) を `parse_definition` (§5 contract
path) から組む builder が存在しない。engine 側の Node ADT (Or/Seq/NumArg、
`poc/eval.mbt` / `poc/complete.mbt`) は形自体を完全にサポート済み — 欠けているのは
flat-ElemDef → structural-or の lowering 経路のみ。

runner は `expected_skips()` に 3 本を凍結済み (commit 353b9328、1× variable-arity
or-option / 2× structural or-positional)。

## 背景

蒸留された fixture (計 6 case、いずれも path-search 系):

- `fixtures/path-search/variable-arity-ambiguous`
- `fixtures/path-search/held-errors-distinct-depth`
- `fixtures/path-search/held-errors-same-depth`

既存の nested-group positional skip (export-key/transparent-seq、issue
`2026-07-06-idx-repeat-held-error-swallowed` が関連) と同型の genuine gap
(= 未実装であって仕様側の欠陥ではない)。

## 受け入れ条件

- [ ] `parse_definition` (§5 contract path) が flat ElemDef から構造 or
      (`Or([Seq([typed cells]), ...])`) を組む builder を持つ
- [ ] 上記 3 fixture (6 case) が `expected_skips()` から消し込まれ、VANISHED SKIP
      として loud に検知されること (= 台帳から外す)
- [ ] `variable-arity-ambiguous` の golden は interpretations が flat な
      `r/g/b/rest` を前提 (DESIGN §15.4 canonical) — outer option ノード
      `name:"color"` が wrapper キー `{color:{...}}` を注入しない形で実装されている
      (レビュー指摘の再確認ポイント)
- [ ] 既存の nested-group positional skip 系実装と重複せず、共通の lowering
      経路として整理されている (可能なら)

## 関連

- nested-group positional skip (export-key/transparent-seq)
- `docs/issue/2026-07-06-idx-repeat-held-error-swallowed.md` — IdxRepeat の Held
  握り潰し。repeat group 実装時に同時対処を検討
