---
title: DR-047「制約を満たさない経路は完全経路と数えない」(path filter) が未実装
status: open
category: bug
created: 2026-07-09T11:00:30+09:00
last_read:
open_entered: 2026-07-09T11:00:30+09:00
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

# DR-047「制約を満たさない経路は完全経路と数えない」(path filter) が未実装

## 概要

DR-047 が定める「制約を満たさない経路は完全経路と数えない」(= 遅延述語による
path filter) が未実装。複数の完全経路が併存する場面で、制約 (`requires` 等)
が完全経路の候補計数に参加していない。

## 背景

spec 側ワーカーの実測 (2026-07-09、commit 7f1b0c96 世代)。alias 同一トリガで
2 経路が生成される定義 (a/b が共に `--v`、a に `requires:["c"]`) に対し:

- argv `["--v"]`: 期待 = a 経路が requires 未充足で完全経路から除外され、b 1
  本で success `{b:true}`。**実測 = ambiguous:2** (制約が経路を落とさない)
- argv `["--v", "--c"]`: 期待どおり ambiguous:2 (対照 — 2 経路の materialize
  自体は正しい)

単一経路の requires は正しく failure `kind:constraint` を返す
(`fixtures/alias-parse/canonical-constraint.json` PASS) ので、ギャップは
「複数完全経路の併存時に制約が候補計数へ参加しない」ことに限定される。制約が
「完全経路計数の前段 filter」でなく「後段検証」として実装されている。

正本: DR-047 (遅延述語)。「制約を満たさない経路は完全経路と数えない」—
ambiguous 解消への制約の参加。DR-038 (完全経路一意性) との合成点。

追いつき後、spec 側 fixture (`constraints-parse/`、上記再現構成そのまま) を
追加する (= 蒸留 1:1 audit の漏れ #6、slice phase25:171 の解消。spec
`findings/2026-07-09-distill-1to1-coverage-audit.md` 参照)。

由来: fixture-batch worker の wire 構成再挑戦 (2026-07-09)。team-lead 裁定
Y-1 (issue 起票 → 追いつき後回帰)。

## 受け入れ条件

- [ ] 複数完全経路が併存する場面で、制約 (`requires` 等) が完全経路の候補計数
      (ambiguous 解消) に参加する
- [ ] 上記の再現構成 (alias 同一トリガ 2 経路、片方に requires) で
      argv `["--v"]` が success `{b:true}` を返す
- [ ] argv `["--v", "--c"]` の ambiguous:2 (対照ケース) が引き続き成立する
- [ ] spec 側 `constraints-parse/` fixture 追加とあわせて回帰確認

## TODO
