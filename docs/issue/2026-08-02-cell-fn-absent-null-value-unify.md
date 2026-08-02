---
title: builtin cell fn の値不在を null Value へ統一する
status: open
category: bug
created: 2026-08-02T17:29:24+09:00
last_read:
open_entered: 2026-08-02T17:29:24+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt TODO
---

# builtin cell fn の値不在を null Value へ統一する

## 概要

REFERENCE §7.6 と DR-131 §1.1 は builtin cell fn の v1 reason 語彙を空とし、
値不在は専用 reason ではなく null Value で表す正本仕様。一方、現行
`src/extension/cell_fns.mbt` の env / borrow / computed 系は `absent-source`
reason を返しており、`src/extension/cell_fns_wbtest.mbt` も
`reasons=[absent-source]` を固定している。正本と実装が食い違っている。

## 背景

共有 fold の branch_fold 消費者では `FnFailed` (枝 Reject・座不変) と
`Value(null)` (成功・ラダー開放) で枝の可否そのものが変わりうる。
このため descriptor・実装・schema/fixtures・wbtest のすべてを正本 (REFERENCE
§7.6, DR-131 §1.1) へ追随させる必要がある。

task #127 の coverage 補強では、この不一致を pin してしまうと正本と反対の
挙動を固定してしまうため、現状 pin は避け、test 専用の rejecting resident
を使って FnFailed 分岐だけを個別に固定する回避策を取った。

## 受け入れ条件

- [ ] `src/extension/cell_fns.mbt` の env / borrow / computed 系が値不在時に
      `FnFailed(absent-source)` ではなく `Value(null)` を返すよう修正されている
- [ ] `src/extension/cell_fns_wbtest.mbt` の `reasons=[absent-source]` 固定箇所が
      null Value 前提のテストへ更新されている
- [ ] 関連 schema / fixtures が REFERENCE §7.6・DR-131 §1.1 の null Value 意味論と
      整合している
- [ ] branch_fold 消費者側で FnFailed/Value(null) の枝可否差分に対する回帰テストがある
- [ ] `src/kuu/resolve.mbt` の absent-source reason 名特別処理を廃止または新契約へ再定義する
- [ ] `src/kuu/resolve_wbtest.mbt` の borrow absent-source 保証を Value(null) 意味論へ更新する
- [ ] spec REFERENCE §6b の borrow/env/computed の fallibility と descriptor fallibility/reasons を §7.6 に整合させる
- [ ] 実装・spec 全体の absent-source 残存箇所を棚卸しし、generic extension 契約として残す場合は
      builtin 契約と分離した根拠を明示する

## TODO

<!-- wip 時のみ -->
