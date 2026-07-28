---
title: head_progresses の Scoped/ScopeNode/IndexedRepeat が無条件 true で zero-progress 検査をすり抜けうる
status: open
category: bug
created: 2026-07-29T04:26:48+09:00
last_read:
open_entered: 2026-07-29T04:26:48+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ) 統括最終監査
---

# head_progresses の Scoped/ScopeNode/IndexedRepeat が無条件 true で zero-progress 検査をすり抜けうる

## 概要

zero-progress 静的検査の `head_progresses` (`src/internal/engine/lowering.mbt:3583` 付近) が
`Scoped(_,_) | ScopeNode(_) => true` と `IndexedRepeat(...) => true` を無条件 `true` にしている。
このため、消費 0 の head を持つ named group (例: 子が `value:` のみの positional group) +
無制限 repeat の組み合わせが静的検査をすり抜けうる。

## 背景

Phase 2-5 の統括最終監査 (2026-07-29) で発見した既存面。Phase 2 以前から存在しており、
今回の一連の変更による回帰ではない。

`Many` / `BoundedTail` は 2026-07-28 の追補で inner 再帰化済みなので、`Scoped` /
`ScopeNode` / `IndexedRepeat` も同じ形 (inner/head への再帰) に揃えるのが修正候補。

## 着手前の確認事項

- [ ] 実際に消費 0 head の group + repeat を decode まで通せる wire が存在するか
      (definition-error で先に落ちるなら理論上の穴に留まる)
- [ ] eval 側に実行時の zero-progress ガードがあるか (あれば無限 unfold は起きず優先度低)
- [ ] 再現候補の definition と期待 (zero-progress definition-error) を fixture 化して確認するのが最短

## 受け入れ条件

- [ ] 上記確認事項の裏取り結果を記録する
- [ ] 実害 (wire 到達可能 + eval 側ガード無し) が確認できた場合、`Scoped` / `ScopeNode` /
      `IndexedRepeat` を `Many` / `BoundedTail` と同様に inner/head への再帰判定へ修正する
- [ ] 実害なしと判明した場合はその根拠を記録して close する

## TODO

<!-- wip 時のみ -->
