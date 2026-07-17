---
title: interpretation view の filter 規則を front_door へ昇格する
status: open
category: design
created: 2026-07-17T12:12:02+09:00
last_read:
open_entered: 2026-07-17T12:12:02+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:    # 1-line JSON array string[] 例: ["discarded","環境が変わった"]
pending_reason:    # 1-line JSON array string[] 例: ["pending","v2 待ち"]
close_reason:      # close 時に update が記録。1-line JSON array string[] 例: ["dr/DR-0007","implemented"]
blocked_by:
origin: M5d 残課題 (統括受理条件 2026-07-17)
---

# interpretation view の filter 規則を front_door へ昇格する

## 概要

conformance runner (`json_conformance_test.mbt`) が `@kuu.output` の
result+sources から interpretation view を組む際、手元で filter 規則を
実装している:

1. SourceEntry が Default の scalar を除外
2. ただし collision claimant key の default は保持
3. 空 accumulator 配列は保持

例外 2 つを持つ非自明な意味論であり、kuu-cli が interpretations を出す時に
同じ規則の再実装を強いる — MDR-006 §7-3 の「呼び出し側が各自組み合わせて
漏れ穴を掘る」の残存形。

## 背景

M5d の残課題として統括が受理 (2026-07-17)。result 構築 / sources 射影 /
warnings 射影は `docs/issue/2026-07-16-result-projection-production-promotion.md`
で front_door の production API へ昇格済みだが、interpretation view の
filter 規則はまだ conformance runner 内のローカル実装のまま。

kuu-cli lockstep 追随で同規則が必要になった時点で front_door の専用射影
API (別名関数) 化を再判断する (= 今すぐ昇格するのではなく、必要になった
タイミングで判断する遅延判断の issue)。

## 受け入れ条件

- [ ] kuu-cli 側で interpretation view の filter 規則が実際に必要になった
      タイミングで、front_door への昇格要否を再判断する
- [ ] 昇格すると判断した場合、3 つの filter 規則 (Default scalar 除外 /
      collision claimant key の default 保持 / 空 accumulator 配列保持) を
      production API として `front_door` に実装し、conformance runner を
      薄い委譲に書き換える
