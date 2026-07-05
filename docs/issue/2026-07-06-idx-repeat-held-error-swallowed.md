---
title: idx_repeat_eval が Held を握り潰し、repeat group の min 未達が空 errors になる (latent)
status: open
category: bug
created: 2026-07-06T02:56:39+09:00
last_read:
open_entered: 2026-07-06T02:56:39+09:00
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

# idx_repeat_eval が Held を握り潰し、repeat group の min 未達が空 errors になる (latent)

## 概要

`eval.mbt:616` 付近の `idx_repeat_eval` に `Held(_, _) => ()` があり、IdxRepeat 経路の Held ParseError を全部捨てている。repeat group (nested-group positional) の min 未達は held-error parity 修正 (commit `deb8d0f65e`、`consume_head` / `scope_consume` の枯渇 held 追加) の同族ケースだが、IdxRepeat 経路には未展開のため、min 未達時に Held エラーが握り潰されて呼び出し元は空 errors を受け取る。

## 背景

held-error parity 修正 (`deb8d0f65e`) は `consume_head` / `scope_consume` の枯渇時 held error 追加を行ったが、`idx_repeat_eval` の Held ハンドリングは対象外のまま残った。

現状は nested-group positional の fixture (`export-key/transparent-seq.json`) が runner decoder 未対応で skip されているため latent (顕在化していない)。skip 解除 (`parse_definition` の IdxRepeat 対応) 時に、repeat group の min 未達ケースが UNEXPECTED divergence として噴く見込み。skip 解除タスクと同時に対処するのが効率的。

発見経緯: gap 修正 (`deb8d0f65e`) の Fable レビューで指摘された。

関連: `2026-07-05-parse-conformance-gaps-batch1` に列挙された既知 gap の一つではなく、held-error parity 修正のレビューで新たに見つかった別件として新規登録。

## 受け入れ条件

- [ ] `idx_repeat_eval` の Held ハンドリングが held-error parity 修正 (`deb8d0f65e`) と揃い、Held ParseError を握り潰さず伝播する
- [ ] nested-group positional fixture (`export-key/transparent-seq.json`) の skip 解除 (IdxRepeat 対応) と同時に検証されている
