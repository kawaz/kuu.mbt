---
title: release.yml semver gate に latest-release 並列 check 追加 (DR-0039 canonical 同期)
status: discarded
category: request
created: 2026-06-28T20:06:07+09:00
last_read:
open_entered: 2026-06-28T20:06:07+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered: 2026-06-29T10:52:31+09:00
resolved_entered:
discard_reason: ["kuu は GH Release / binary 配布なし方針のため release.yml semver gate 改善は不要。release.yml 自体の今後 (完全削除/暫定維持/mooncakes publish 専用) は別途方針確認。"]
pending_reason:
close_reason:
blocked_by:
origin: bump-semver dogfood 報告
---

# release.yml semver gate に latest-release 並列 check 追加 (DR-0039 canonical 同期)

## 概要

bump-semver canonical (DR-0039) で release.yml の semver gate pattern が更新された。本リポの release.yml に `latest-release` 並列 check を追加して canonical pattern に同期する。

## 背景

bump-semver canonical (DR-0039) で release.yml の semver gate pattern が更新された。本リポは `latest-tag` 単独 + moon.mod 整合 check + `gh release view` の B 型変種。

## 現状 (release.yml L69-102 該当)

`vcs get latest-tag` + moon.mod / VERSION 多重 source 整合 check + `gh release view`。`latest-release` 並列 check 無し。

## 修正方針

既存の moon.mod 整合 check は維持しつつ、`latest-release` 並列 check を追加。canonical pattern は bump-semver の release.yml と DR-0039 参照。

## 参考

- bump-semver の `.github/workflows/release.yml`
- bump-semver の docs/decisions/DR-0039-release-yml-semver-gate-pattern.md
- kawaz/die dogfood 報告: session 911732b3、2026-06-28

## 優先度

中 (= B 型)。bump-semver v0.43.0 release 後に着手推奨。

## 受け入れ条件

- [ ] release.yml の semver gate に `latest-release` 並列 check が追加されている
- [ ] 既存の moon.mod 整合 check が維持されている
- [ ] DR-0039 の canonical pattern と整合している
