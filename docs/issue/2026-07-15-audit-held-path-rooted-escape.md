---
title: Held.path にも Rooted escape 未対応の疑い (Cand.path と同種の構造的欠落の可能性)
status: open
category: idea
created: 2026-07-15T11:37:35+09:00
last_read: 2026-07-15T13:45:03+09:00
open_entered: 2026-07-15T11:37:35+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt completer 実装セッション (副次発見, 2026-07-15)
---

# Held.path にも Rooted escape 未対応の疑い (Cand.path と同種の構造的欠落の可能性)

## 概要

completer 実装中の副次発見として、`Held.path` (`ParseError.path`) にも
`Cand.path` で見つかったのと同種の Rooted escape 未対応が理論上残っている
可能性がある。未調査・未着手。

## 背景

`Cand.path` は `nest_cands` が無条件 prepend していたため、global option
(Rooted 衛星) の候補 path が「コピー先の子 scope」になり、宣言元 Entity と
食い違う潜在バグがあった。`Cand.link` (Rooted-escape カウンタ、`Binding.link`
と同ロジック) の新設で修正済み (completer 配線 commit 参照)。

同じ「無条件 prepend で子 scope に潜り込む」構造が `Held.path` にも存在する
なら、同じ escape 欠落バグが理論上起こりうる。ただし `Held.path` 側は
今回未調査・未変更 — 構造の類似性からの推測であって実証はしていない。

## 受け入れ条件

- [ ] global option の値エラー (filter reject 等) が子 command scope 内で
      発生した場合の error path/element 帰属について、spec 期待
      (DR-066 §4) と実装の現状を突き合わせる
- [ ] ズレが実証された場合: `Binding.link` / `Cand.link` と同じ Rooted-escape
      ロジックを `Held.path` 側にも配線する
- [ ] 修正した場合: spec fixture でその挙動を pin する
- [ ] ズレが無いと確認できた場合: 「該当なし」の根拠 (= なぜ escape が
      不要か) を本 issue に追記して close する

## TODO

<!-- wip 時のみ -->
