---
title: named or wrapper に multiple (accumulator) を付けると発火 row に未選択枝の空配列セルが混入する
status: open
category: bug
created: 2026-07-29T09:24:59+09:00
last_read: 2026-07-29T09:50:23+09:00
open_entered: 2026-07-29T09:24:59+09:00
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

# named or wrapper に multiple (accumulator) を付けると発火 row に未選択枝の空配列セルが混入する

## 概要

named `or` wrapper に `multiple` (accumulator) を付けたとき、発火 row に未選択枝の空配列セルが混入する。
未選択枝は成立しなかった構造なので result にも sources にも席が無いのが正 (DR-051 / DR-122 §2)。

## 背景

### 実測 (2026-07-29、未 push)

spec fixture `or-parse/accum-branch-rows-sources.json::two-fires-different-branches-elementwise-shadow`:

```
got  {sel=[{nums=[1,2]},{nums=[],word=foo}]}
want {sel=[{nums=[1,2]},{word=foo}]}
```

`word` 枝を選んだ row に `nums:[]` が漏れている。

### 回帰ではない証拠

multiple 無しの同型定義 `or-parse/child-repeat-branch.json::string-branch-excludes-numeric-branch` は green。
accumulator の row 構築経路だけが未選択枝の除外を落としていると見られる。

## 受け入れ条件

- [ ] `or-parse/accum-branch-rows-sources.json::two-fires-different-branches-elementwise-shadow` が pass する
- [ ] 既存の `or-parse` / `multiple-parse` 群に回帰が無い

## 関連

- spec `docs/decisions/DR-051-*.md`, `docs/decisions/DR-122-*.md` §2 — 未選択枝は result / sources に席を持たない
- spec fixture `fixtures/or-parse/accum-branch-rows-sources.json`
- spec fixture `fixtures/or-parse/child-repeat-branch.json` (対照、multiple 無しで green)
