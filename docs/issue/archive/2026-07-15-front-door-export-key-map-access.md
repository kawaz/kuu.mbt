---
title: front_door 経由で export_key map に到達できない (kuu-cli dogfooding での発見)
status: resolved
category: task
created: 2026-07-15T19:34:34+09:00
last_read:
open_entered: 2026-07-15T19:34:34+09:00
wip_entered: 2026-07-15T19:37:48+09:00
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-15T19:53:26+09:00
discard_reason:
pending_reason:
close_reason: ["dr/MDR-005-front-door-api","implemented"]
blocked_by:
origin: kuu-cli PoC dogfooding (統括起票)
---

# front_door 経由で export_key map に到達できない (kuu-cli dogfooding での発見)

## 概要

kuu-cli の MoonBit PoC (kawaz/kuu-cli impl/mbt、2026-07-15) が front_door の
`parse_definition` + `parse` を使って conformance と同形の JSON 出力を組もうと
したところ、result の export_key 適用に必要な ekmap (`build_export_map` の結果)
が取得できなかった。

`build_export_map` と `dec_definition` は `wire_decode.mbt` 内部の非 pub fn で、
`front_door.parse_definition` が返す AtomicAST からは生 Definition を復元できない。
PoC は `apply_export_keys(binds, Map([]))` (空 ekmap) で回しており、export_key を
持つ definition では result キーが name ベースになる (effects/errors/warnings は影響なし)。

## 背景

front_door (MDR-005 の正面玄関 3 関数) の責務として「conformance の expect と
同形の出力を外部利用者が組める」を含めるなら、ekmap の露出
(parse_definition の副戻り値 / AtomicAST への保持 / result 構築ヘルパの pub 化
のいずれか) が要る。

一次資料:
- kuu-cli の `impl/mbt/cli/src/lib/wire.mbt` 頭部コメント
- kuu.mbt の `src/core/front_door.mbt`
- kuu.mbt の `src/core/wire_decode.mbt` (`build_export_map`)

実装方針は当事者セッションで裏取りして判断してほしい (部外者フラグにつき断定しない)。

## 受け入れ条件

- [x] ekmap 露出の要否と方式 (副戻り値 / AtomicAST 保持 / ヘルパ pub 化 等) を裁定する
      (裁定: AtomicAST に `ekmap` フィールドを同梱 + `pub fn export_map(ast)` を追加)
- [x] 裁定結果を front_door の責務定義 (MDR-005) と整合させる (MDR-005 §「除外」に追記)

## TODO

- [x] AtomicAST (front_door.mbt) は root+registry のみ保持し、生 Definition を復元できないことを確認
- [x] `build_export_map` は `installer.mbt:972` で既に pub であることを確認 (露出範囲の問題ではない)
- [x] conformance runner (`json_conformance_wbtest.mbt:2219-2240`) は `parse_definition` とは別に
      Definition を decode し直して ekmap を組んでいる現状の実装パターンを確認
- [x] 上記裏取りに基づく実装方針を mbt-writer worker に委譲し、front_door 側の ekmap 露出を実装する
  (`AtomicAST.ekmap` + `pub fn export_map(ast)`、MDR-005 追記、`just test` 347/347 pass)
