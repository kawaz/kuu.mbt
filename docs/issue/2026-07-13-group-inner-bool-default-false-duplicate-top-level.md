---
title: group 内側 bool 要素の暗黙 default:false が top-level result に重複出現する
status: open
category: bug
created: 2026-07-13T09:38:57+09:00
last_read:
open_entered: 2026-07-13T09:38:57+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ)
---

# group 内側 bool 要素の暗黙 default:false が top-level result に重複出現する

## 概要

positional group 内側の bool 系要素 (`bool_config` 付き `TypeShadow` 経由で作った型) が、
group の row (`grp: [{gflag: ...}]`) には正しく現れる一方、**同じ要素が top-level result にも
`gflag=false` として重複出現する**。DESIGN §2.6 の入れ子モデル (結果キーを持つスコープ生成要素の
子は row/kv の中に現れる、親スコープに flat に漏れ出さない) に反する。

## 背景

spec fixture `fixtures/value-typing/positional-group-factory-config.json` (未 push) の live 検証で
発見 (2026-07-13)。ケース `group-inner-leaf-carries-true` (argv `["yes","yes"]`) /
`group-inner-leaf-carries-false` (argv `["no","no"]`) の `expect.result` は
`{"ctrl": <bool>, "grp": [{"gflag": <bool>}]}` のみで top-level に `gflag` キーを含まないが、
実装の実際の出力は `gflag` を top-level にも (`false` で) 重複出現させる。

推測される原因: 暗黙 default:false (bool の canonical、DESIGN L712) を entity 注入する
`ensure_entity` の `TFlag`/`TBool` 共通ルールが、group 入れ子のスコープを無視して flat に
top-level entity を作っている疑い。DR-099 実装 (`is_tty` 除外) が触った箇所と同じ `ensure_entity`
が関連する可能性が高い。

同 fixture と対をなす or 枝側の carry gap
(`fixtures/value-typing/or-leaf-factory-config.json` の case 1/2/4:
`bool-dialect-or-leaf-carries-true` / `bool-dialect-or-leaf-carries-false` /
`base-prefix-or-leaf-carries` が pin する `dec_or_leaf` の factory config carry gap) は
既 issue `docs/issue/2026-07-12-typeshadow-carry-gap-or-leaf-positional-group.md` が追跡中。
この既 issue のタイトル・背景にあった「`dec_positional_group` も未配線」という記述は本 issue の
調査過程で誤りと判明した (group 側は `dec_positional` 再帰経由で `TypeShadow` の全フィールドが
既に carry 済み — `dec_or_leaf` だけが `base`/`int_round` の 2 フィールドに絞られている)。
該当既 issue 側は本 issue と同時に記述を訂正済み。

## 受け入れ条件

- [ ] `fixtures/value-typing/positional-group-factory-config.json` の case
      `group-inner-leaf-carries-true` / `group-inner-leaf-carries-false` が green になる
      (= top-level への `gflag` 重複出現が消え、`grp` row 内側の値のみが正になる)
