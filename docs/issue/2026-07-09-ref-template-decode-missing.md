---
title: conformance harness に ref (共有 template 参照) の decode が無い
status: open
category: task
created: 2026-07-09T11:47:33+09:00
last_read:
open_entered: 2026-07-09T11:47:33+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: fixture-batch2 worker (依頼元プロジェクト: kuu)
---

# conformance harness に ref (共有 template 参照) の decode が無い

## 概要

`positionals:[{"name":"hlcolors","ref":"color","repeat":{"min":1}}]` + 共有 template `color` を宣言する parse fixture が書けない。dec_positional / dec_option の allowed_keys (json_conformance_wbtest.mbt:2225-2233 / 2086-2095) に "ref" キーが無く DecodeSkip になる。"ref"/"link" は lowering fixture の expect (内部 AST) 側の語彙としてのみ実装されており、definition 入力側の共有 template 宣言機構 (registry への植え込み) が decode 層に未実装。

## 背景

fixture-batch2 worker の実測報告 (2026-07-09)。DecodeSkip の確認 fixture は削除済み。

## 受け入れ条件

- [ ] definition 側の ref 宣言 + 共有 template (definitions 節? 独立 template 節?) の wire 形式を spec (DR-028 type-as-reference / DR-034) と突き合わせて確定
- [ ] decode → installer (ElemDef.ref_target + registry 注入、実装済み経路) への配線を追加
- [ ] spec 側 fixture 2 本 (ref-or-template repeat の ambiguity = slice phase4:114 / 取り分選好の or 非侵食 = phase10:64、蒸留 1:1 audit 漏れ #1/#2) を追加

## TODO

<!-- wip 時のみ -->
