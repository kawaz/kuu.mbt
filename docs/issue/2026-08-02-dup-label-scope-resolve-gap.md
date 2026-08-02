---
title: duplicate raw label scope での resolve 相 entity 解決が候補を区別しない gap
status: open
category: bug
created: 2026-08-02T15:14:10+09:00
last_read:
open_entered: 2026-08-02T15:14:10+09:00
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

# duplicate raw label scope での resolve 相 entity 解決が候補を区別しない gap

## 概要

duplicate raw command path (同名 command 2 本、export_key で結果キーは分離 — DR-120 合法) の
配下に同名 entity が別宣言で並ぶとき、resolve 相の entity 解決 (binding.scope の raw label
walk) が候補を区別せず、選択された読みと違う側の宣言を引く。

## 再現 (実測 2026-08-02、W2-8 監査 M3 対応時)

```json
{"commands":[
 {"name":"go","export_key":"go1","options":[
  {"name":"tr","type":"trange","long":true},
  {"name":"until","type":"string","long":true,"link":"tr.until"}]},
 {"name":"go","export_key":"go2","options":[
  {"name":"tr","type":"number","long":true}]}]}
```

args `["go", "--until", "5"]` (trange は record `{since,until}` を名乗る wbtest 用型 —
`src/kuu/value_seat_wbtest.mbt` の `RangeSeatType`)。読みは go1 側 (--until は go1 にしか
無い) だが、resolve 相の値残余分岐が go2 側の `tr` (number 宣言) を引き、
`invalid-range: the value-space seat of 'tr' did not resolve: absent (the seat's container
is absent and vivify is set-only — DR-127 §3)` で全体パース失敗になる。正しくは go1 の
trange 宣言で vivify が効き `{go1:{tr:{since:null,until:5}}}` が立つはず。

wbtest「監査 M3: 同名 command 2 本の別宣言 target は保守的スキップ (誤枝刈りしない)」
(`src/kuu/value_seat_wbtest.mbt`) が現状を pin — parse 相の枝ローカル fold は宣言候補の
食い違いで保守的スキップするため誤枝刈りしない (そこは正)。失敗は resolve 相のみ。

## 裏取りの観点

binding には「どの同名 scope 本体の読みか」を運ぶ素材が無い (scope は raw label 列)。
区別には枝 identity の搬送 (binding か scope marker の拡張) が要る可能性 — 部外者裁定は
せず、spec 側の DR-120 / DR-025 (結果 nesting) と突き合わせて設計判断すること。

## 受け入れ条件

- [ ] 上記再現が go1 側の宣言で解決され result `{go1:{tr:{since:null,until:5}}}` になる
- [ ] parse 相 fold の保守的スキップ wbtest を「成立する」期待へ更新する
- [ ] 既存 tests / conformance 不変

## TODO

<!-- wip 時のみ -->
