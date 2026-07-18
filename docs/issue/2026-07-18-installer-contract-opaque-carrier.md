---
title: installer 契約の opaque 化と carrier 12 型の builtins 帰属 — DR-110 完全準拠への再設計 (TRI-Q1 後続)
status: open
category: design
created: 2026-07-18T18:44:52+09:00
last_read:
open_entered: 2026-07-18T18:44:52+09:00
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

# installer 契約の opaque 化と carrier 12 型の builtins 帰属 — DR-110 完全準拠への再設計 (TRI-Q1 後続)

## 概要

API 公開面棚卸し (issue api-surface-contract-triage) の TRI-Q1 裁定 (分割案) で「独立 issue へ」と切り出された再設計課題。**installer 契約 (InstallerExt::decode / DefsView / InstallBuilder) のシグネチャが installer 語彙 carrier 12 型 (ElemDef / Definition / CommandDef / AliasDef / ElemBody / OrBranch / Variant / LongDecl / RepeatSpec / RequiredCandidate / OwnedDecl / Constraint) を直接参照している**ため、carrier を builtins へ移せず (依存方向の矛盾)、pub(all) 撤廃すら不可能 (builtins/kuu が package 境界越しに直接構築、MoonBit に friend 可視性なし — 実機確認済み 2026-07-18)。

## 背景

api-surface-contract-triage サイクルで API 公開面 (pub/pub(all)/priv) を棚卸しした際に発覚。DR-110 §2-1 は「engine は installer 語彙の識別子を持たない」ことを要求するが、現行実装では carrier 型が engine 側 (installer 契約の型シグネチャ) に露出しており、この要求を満たせない。TRI-Q1 では複数の対応案を比較した結果、この課題単体では現サイクルのスコープに収まらないと判断し、独立 issue として切り出すことになった。

## ゴール (DR-110 完全準拠)

- engine は installer 語彙 (long/short/env/... のフィールド名) を知らない — carrier は builtins 所有へ
- InstallerExt::decode の戻りを opaque data (Json or encode 済み decl) に変え、engine は「所有語彙の交差検査 + unknown-vocab 検査 + 不動点反復」だけを担う
- ElemDef 55 field の god struct 問題 (コールドレビュー指摘) もこの再設計で構造化する (サブ構造への畳み込み — TRI-Q7=b で分離された Entity 最小化と同時に検討)

## 制約・前提

- MoonBit の可視性: pub(all) / pub / priv のみ (sibling package 限定の friend なし)。「外部構築不可の共有型」は同一 package 内でしか作れない — carrier を builtins に置けば builtins 内で自由、engine は opaque 参照
- open node 化 (Node 18 バリアントの Ext 移行、TRI-Q5=a で分離) と同じ再設計群 — 同時に設計するのが手戻りが少ない
- 実装順の目安: permutation test 復活 (issue feature-bundle-composition-api の前提タスク) → 本 issue の設計 → bundle API — いずれも install 契約周りなので 1 サイクルに束ねる判断もあり

## 受け入れ条件

- [ ] opaque 化の設計プラン (decode 戻り値の形、engine 側検査の残し方、carrier 移動の段取り)
- [ ] MDR (実装設計) 起草 + kawaz 裁定
- [ ] 実装 + carrier 12 型の builtins 移動 + pub(all) 解消
- [ ] conformance green 維持 + mbti 凍結更新

## 関連

- docs/issue/2026-07-18-api-surface-contract-triage.md (親サイクル、実施記録に経緯) / docs/findings/2026-07-18-api-surface-triage-table.md (TRI-Q1/Q5/Q7)
- spec の DR-110 §2-1 (engine は語彙の識別子を持たない) / MDR-006 (現行 package 分離の実施記録)
- docs/issue/2026-07-18-feature-bundle-composition-api.md (同じ install 契約周りの再設計群)
