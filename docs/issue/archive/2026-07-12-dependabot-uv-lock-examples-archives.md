---
title: dependabot 警告 2 件 — examples/archives の uv.lock 由来
status: resolved
category: task
created: 2026-07-12T17:57:21+09:00
last_read:
open_entered: 2026-07-12T17:57:21+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-13T08:24:01+09:00
discard_reason:
pending_reason:
close_reason: ["examples/archives は main 書き直し時に既に削除済みで working copy にも git 管理下にも存在しない (gh api contents は 404 で確認)","alert は旧リモート枝時代の manifest を指す stale、#8/#18 とも GitHub 上で dismissed 済み (2026-07-13、dismissed_comment に経緯記載)","起票自体が alert の manifest_path だけを見て main に実在すると誤認したものと判明。実物確認を経ずに起票した点が原因"]
blocked_by:
origin: kuu (依頼元プロジェクト)
---

# dependabot 警告 2 件 — examples/archives の uv.lock 由来

## 概要

GitHub dependabot が open alert を 2 件報告している。両方とも
`examples/archives/20260309-cargo-python/uv.lock` に由来し、本体 (`src/`) の
コードや配布物には無関係なアーカイブ例の lockfile。対応方針は未裁定。

## 背景

2026-07-12 に `gh api` の実出力で確認:

- alert #18: pytest "vulnerable tmpdir handling" (severity: medium)
- alert #8: Pygments "ReDoS due to Inefficient Regex for GUID Matching" (severity: low)

両 alert とも `manifest_path = examples/archives/20260309-cargo-python/uv.lock`。

対処候補 (未裁定):

- (a) `examples/archives/` ごと削除
- (b) alert を dismiss (inaccurate / not-used)
- (c) lock を bump

削除は不可逆なので kawaz 判断待ち。緊急性なし。

## 受け入れ条件

- [ ] 対処方針 (a / b / c のいずれか) を裁定する
- [ ] 裁定に従って対応し、対象 2 件の open alert が解消 (または dismiss 理由が記録) されている
