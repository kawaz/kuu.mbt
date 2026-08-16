---
title: option_alias_pairs の index zip が非対称フィルタで壊れる
status: open
category: bug
created: 2026-08-16T14:15:01+09:00
last_read:
open_entered: 2026-08-16T14:15:01+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)
---

# option_alias_pairs の index zip が非対称フィルタで壊れる

## 概要 (D1)

`option_alias_pairs` の index zip が非対称フィルタで壊れ、positional target alias があると別要素へ alias 誤帰属・本物の alias 消滅。

## 背景

- 場所: src/kuu/help.mbt:321
- `option_alias_pairs` の index zip が非対称フィルタで壊れる
- positional target alias があると別要素へ alias が誤帰属、本物の alias が消滅する (実測)
- completion 側にも波及

## 対処方針

desugar 側で対応関係を持たせるのが筋。現状の index zip の暗黙契約自体が脆弱なため、構造的な変更が必要。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] positional target alias があっても option alias の帰属が崩れない
- [ ] completion 側の波及箇所も修正・確認済み
