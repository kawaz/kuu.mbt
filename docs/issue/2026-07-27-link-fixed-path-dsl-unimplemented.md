---
title: link target の固定パス DSL (.field / [idx]) が未実装 (bare name のみ対応)
status: open
category: design
created: 2026-07-27T00:29:04+09:00
last_read:
open_entered: 2026-07-27T00:29:04+09:00
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

# link target の固定パス DSL (.field / [idx]) が未実装 (bare name のみ対応)

## 概要

DR-029 は link target を固定パス DSL `name ('.' name | '[' int ']')*`
(例 `link:"timerange.since"`、`link:"color.rgb[-1]"`) と規定し、解決は遅延
(実行時)・失敗はその経路のパース失敗とする。2026-07-26 の link source 実装
(Source::Link、commit 4f5663fa 系スタック) は bare name target のみ対応で、
path 付き target は decode で受理していない。

## 背景

path 付き target の実装には型内部構造 (value_parser が実行時に作るオブジェクト)
への到達が要るため、値の実行時 introspection 設計が前提になる。現状はこの
前提が未整備のため bare name のみで先行実装されている。

関連: `src/kuu/wire_decode.mbt` の link decode、DR-029 (spec `docs/decisions/`)。

## 受け入れ条件

- [ ] link target の固定パス DSL (`.field` / `[idx]` の連結) が decode で受理される
- [ ] 値の実行時 introspection 設計 (value_parser が生成したオブジェクトへの到達手段) が定まっている
- [ ] path 解決が DR-029 の規定通り遅延 (実行時) で行われ、失敗時はその経路のパース失敗として扱われる

## TODO

<!-- wip 時のみ -->
