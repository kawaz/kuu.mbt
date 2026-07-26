---
title: dec_or_leaf の残余キー同型化の棚卸し (repeat/multiple/optional が最優先、DR-067 §2 直接規定)
status: open
category: design
created: 2026-07-26T22:23:57+09:00
last_read:
open_entered: 2026-07-26T22:23:57+09:00
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

# dec_or_leaf の残余キー同型化の棚卸し (repeat/multiple/optional が最優先、DR-067 §2 直接規定)

## 概要

schema `$defs.node` と `dec_or_leaf` の `allowed_keys` の差分は 2026-07-26 調査で 52 キー →
value/default 実装後も約 49 キー残る。優先度階層に沿って段階的に同型化する。

## 背景

優先度階層 (2026-07-26 調査時点):

- **(高)** `repeat` / `optional` / `multiple` — DR-067 §2 が child 内で合法と直接規定、かつ
  「optional な 2 番目 + fallback」の表現手段がこれが無いと存在しない
- **(中)** `default_fn`、`export_key`、filters 系、`env` — `default_fn` は resolve 相の遅延評価が
  要るため消費 0 literal に落とせず意図的にスコープ外にした (decode だけ通すと silent wrong
  answer になるため現状は明示エラー維持)。`env` は DR-042 により席宣言のみで child でも spec 上
  有効 (long/short の inert とは違う)
- **(低)** ネスト or/seq、表示メタ、ref 等

実装前に各キーの child 位置での意味論を spec と突き合わせること。

## 受け入れ条件

- [ ] repeat/optional/multiple が child 位置で decode を通過する (DR-067 §2 準拠)
- [ ] 中優先度キー (default_fn の扱い方針含む、export_key、filters、env) の child 位置意味論が spec 突き合わせで確定する
- [ ] 低優先度キーの対応要否が判断される (対応しないなら理由を明記)

## TODO

<!-- wip 時のみ -->
