---
title: head_progresses の Many(min:0) が「進捗する」扱いで zero-progress 検査をすり抜けうる
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

# head_progresses の Many(min:0) が「進捗する」扱いで zero-progress 検査をすり抜けうる

## 概要

zero-progress 静的検査の `head_progresses` (`src/internal/engine/lowering.mbt:4491`) は
「この node は **必ず** 1 トークン以上消費するか」を判定する述語である
(`Bind(_,_) | ChildDefault(...) => false // a child-default fallback may consume 0 tokens`、
`BoundedTail(head, budget, _) => budget >= 1 && ...` が示すとおり、消費 0 があり得る形は false)。

ところが `Many(inner, _) => head_progresses(inner, registry, visiting)` は inner の形だけを見る。
`Many` は `min:0` の UNBOUNDED repeat の lowering 形 (`lower_positional` の doc 参照) で
**0 回反復 = 0 トークン消費**があり得るのに「進捗する」と答える。`BoundedTail` が
`budget >= 1` を明示的に確かめているのと非対称。

外側の無制限 repeat の head に `min:0` の子 repeat が入る形が、この経路で zero-progress 検査を
通過しうる。

> **未検証**: 静的読解のみ。レビュー時の probe は並行編集によるビルド破損で完走できなかった
> (2026-08-16 領域別レビュー R1 m8)。着手時に実機で再現を取ること。

## 更新 (2026-08-17): 旧タイトルの指摘対象は解消済み

本 issue は当初「`Scoped(_,_) | ScopeNode(_) => true` と `IndexedRepeat(...) => true` が
無条件 true」を指していたが、**3 つとも現実装では inner/head へ再帰済み**で、その穴は無い
(2026-08-17 実測):

| arm | 現実装 (lowering.mbt) |
|---|---|
| `IndexedRepeat(_, inner, _, _)` | `head_progresses(inner, ...)` (:4507) |
| `Scoped(_, inner)` | `head_progresses(inner, ...)` (:4548) |
| `ScopeNode(scope)` | greedy / positional の子へ再帰し、どれも進捗しなければ false (:4551-4562) |

そこで本 issue は**残った兄弟穴 (`Many`) へ差し替える**。旧「着手前の確認事項」も
`Many` 前提で引き直した。

## 着手前の確認事項

- [ ] `Many` を含む head で zero-progress を作る wire が decode まで到達するか
      (definition-error で先に落ちるなら理論上の穴に留まる)
- [ ] eval 側に実行時の zero-progress ガードがあるか (あれば無限 unfold は起きず優先度低)
- [ ] `Many(inner) => false` へ倒したとき、既存の正当な定義が zero-progress definition-error に
      化けないか (`fixtures/repeat-parse/preference-lazy-min0.json` 等の min:0 系が回帰の当たり)

## 受け入れ条件

- [ ] 上記確認事項の裏取り結果を記録する
- [ ] 実害 (wire 到達可能 + eval 側ガード無し) が確認できた場合、`Many` を
      `BoundedTail` と同様に「0 回反復があり得る形は進捗しない」判定へ修正する
- [ ] 実害なしと判明した場合はその根拠を記録して close する

## TODO

<!-- wip 時のみ -->
