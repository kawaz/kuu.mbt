---
title: M5 の (origin,spelling) ペア判定により or-branch option で同一 flag が 2 行 emit される (DR-117 棄却案と衝突、裁定要)
status: open
category: design
created: 2026-08-12T11:01:48+09:00
last_read:
open_entered: 2026-08-12T11:01:48+09:00
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

# M5 の (origin,spelling) ペア判定により or-branch option で同一 flag が 2 行 emit される (DR-117 棄却案と衝突、裁定要)

## 概要

M5 の (origin, spelling) ペアで trigger 候補を判定する実装により、or-branch を持つ option で同一 flag が help に 2 行出てしまう。これは DR-117 で検討され棄却された「word_end/cont ペアの 2 行 emit」案と同型の重複であり、既存の裁定と衝突している。

## 背景

DR-117 では word_end/cont のペアで 2 行 emit する案が検討されたが棄却された経緯がある。今回 M5 の (origin, spelling) ペア判定を実装したところ、or-branch option で同一 flag が origin 違い (or の各枝) ごとに複数候補として生成され、結果として help に同一 flag が 2 行出る事象が発生している。DR-117 の棄却理由がこのケースにも適用されるのか、それとも別ケースとして許容されるのかは未裁定。

## 受け入れ条件

- [ ] or-branch option で同一 flag が 2 行 emit される実例を再現する
- [ ] DR-117 の棄却理由を再読し、今回のケースが同型か差分かを整理する
- [ ] 裁定 (2 行 emit を許容する / dedup する / M5 判定方式自体を見直す) を QUESTIONS.md 等で取る
- [ ] 裁定に基づき実装を修正し、重複 emit がなくなることを確認する
