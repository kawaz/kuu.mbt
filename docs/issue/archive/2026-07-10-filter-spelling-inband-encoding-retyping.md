---
title: filter spelling の内部表現を U+E000 タグ encode から FilterSpelling 型へ再設計
status: resolved
category: design
created: 2026-07-10T20:23:20+09:00
last_read:
open_entered: 2026-07-10T20:23:20+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-10T21:24:16+09:00
discard_reason:
pending_reason:
close_reason: ["implemented: kuu.mbt commit 7c80a55f で FilterSpelling 型 (name+args 構造) へ再型付け、U+E000 encode/decode を全削除 (grep で痕跡 0 件確認)、chain 消費側 8 ファイル追従。受け入れ条件 4 点すべて充足: 型導入と全 chain 追従 / U+E000 encode 削除 / conformance 全 green (decoded=174 skipped=0 mismatches=0、colon オブジェクト形式 case 含む) / U+E000 を含む引数値の literal 生存 wbtest 追加 (moon test 201 本)"]
blocked_by:
origin: 依頼元プロジェクト (kuu spec リポ)
---

# filter spelling の内部表現を U+E000 タグ encode から FilterSpelling 型へ再設計

## 概要

commit `d7909136` の DESIGN §8.4 オブジェクト形式 decode 対応で、
`piece_filters` / `value_filters` / `cell_filters` の型 (`Array[String]`) を
維持するため、オブジェクト形式 `{name,args}` を U+E000 (Private Use Area)
タグ付き単一文字列にエンコードする暫定実装を採用した
(`filters.mbt` の `encode_object_form_filter_spelling` /
`split_filter_spelling`)。

## 背景

暫定実装は以下 2 点の問題を抱える:

1. **in-band マジック文字方式の潜在穴**: filter 引数の値が U+E000 を含む
   定義で誤分割する。definition JSON は任意 string を書けるため、この
   マジック文字を含む値が来た場合に decode が壊れる
2. **型が意味を運ばない**: `Array[String]` のままなので、encode/decode の
   対の維持が暗黙規約になっている (= 型システムで保護されない)

## 対応

- `Array[String]` を `Array[FilterSpelling]` (name + args を構造で持つ型)
  へ再型付けする
- installer / resolve / eval の chain 消費側を追従させる
- 波及が広いため独立サイクルで実施する

## 受け入れ条件

- [x] `FilterSpelling` 型の導入と全 chain の追従
- [x] U+E000 encode/decode の削除
- [x] conformance 全 green (`piece-filters/regex-match.json` の colon
      オブジェクト形式 case 含む)
- [x] U+E000 を含む引数値が literal として通る wbtest

## 関連

- commit `d7909136` — DESIGN §8.4 オブジェクト形式 decode 対応 (暫定実装の導入元)
