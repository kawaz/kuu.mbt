---
title: ローカル just ci に mbti drift チェックを追加する
status: resolved
category: task
created: 2026-08-16T01:31:04+09:00
last_read:
open_entered: 2026-08-16T01:31:04+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-08-16T01:57:49+09:00
discard_reason:
pending_reason:
close_reason: ["done:kuu.mbt commit f82170c1 (justfile mbti-check recipe — CI と同一の6パッケージで moon info 実行、drift あり→diff表示+exit 1+mbti復元、ci depsに配線。基準線は再生成前の作業コピーvs再生成結果。v0.1.2でCI green)"]
blocked_by:
origin: kuu (spec リポ、クロスプロジェクト起票)
---

# ローカル just ci に mbti drift チェックを追加する

## 概要

ローカル `just ci` に `moon info` (pkg.generated.mbti 再生成) + `git diff --exit-code` 相当の drift チェックを追加する。CI の「Check public interface drift」ジョブが検出している内容を push 前にローカルで再現する。

## 背景

v0.1.0 push (2026-08-16) で CI の「Check public interface drift」(moon info + git diff --exit-code) が failure になった。実装 worker が mbti 再生成を一部忘れたままローカル `just ci` (fmt/check/test のみ) を実行し green だったため検出できず、v0.1.1 の修正 push が必要になった。

## 受け入れ条件

- [ ] justfile の `ci` recipe の deps に、mbti drift チェック相当の recipe が追加されている
- [ ] mbti が意図的に未反映の状態でローカル `just ci` を実行すると failure する (再現確認)
- [ ] CI 側の「Check public interface drift」ジョブと検査内容が一致する (同じ `moon info` 呼び出し + diff 対象)

## TODO

<!-- wip 時のみ -->
