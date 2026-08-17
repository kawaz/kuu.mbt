---
title: find_help_entry が help preset を区別せず fail_action 一般を拾う
status: open
category: bug
created: 2026-08-17T09:26:44+09:00
last_read:
open_entered: 2026-08-17T09:26:44+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt 全コードレビュー即修サイクル 2026-08-17 (D3 の未修正分)
---

# find_help_entry が help preset を区別せず fail_action 一般を拾う

## 概要 (D3 の残り半分)

DR-053 §4 は `help_entry` を「定義に **help 入口** があれば、その綴り」と定める。ところが engine の `find_help_entry` は lowered node 上の **FailMark の有無しか見ていない**ため、DR-113 §7.2 / DESIGN §15.10 の汎用 `on_failure: true` を素で立てた `--version` のような **help 入口でない fail_action** を `help_entry` として返す。

本物の `--help` が併存していても、宣言順で先に見つかった方が勝つ。

## 実測 (RED、現在も再現する)

即修サイクルで help model 側 (`src/kuu/help.mbt` の `help_entry`) は `is_help_preset` gate を入れて修正済み (commit `7c8fa4b0`)。**engine 側は未修正**なので、同じ定義に対して 2 つの面が食い違う:

| 定義 | `HelpModel.help_entry` (修正済み) | `ParseFailure.help_entry` (未修正) |
|---|---|---|
| `{"options":[{"name":"help","type":"help","long":true}]}` | `--help` | `--help` |
| `{"options":[{"name":"version","type":"flag","long":true,"on_failure":true}]}` | `<none>` ✅ | **`--version`** ❌ |
| 上の 2 つを version → help の順で併記 | `--help` ✅ | **`--version`** ❌ |

DR-053 §4 の `help_entry` は本来 **outcome (failure / ambiguous) に載る素材**が本命 (DR-048 の誘導行 `Try 'prog --help' for more information.` の材料) なので、未修正で残っているのは重い方の面である。

## 原因

- `src/internal/engine/outcome.mbt` の `find_help_entry_in_greedy` が、greedy 衛星の Seq に `node_is_failure_mark(it)` が真の Ext ノードを含むかだけで判定する
- `node_is_failure_mark` は `NodeExt::is_failure_action()` を見るが、これを true にするのは `FailureMarkExt` 1 つで、同 resident は `name : String` しか持たない
- つまり **lowered node の側に「この fail_action は help preset 由来か」を区別する情報が無い**。宣言層 (`ElementDef.help_meta.is_help_preset`、DR-113 §7.2 が別目的で置いた carry) は lowering を越えて運ばれていない

## 設計候補 (どちらも公開 API に触るので裁定が要る)

### 案 A: `failure_mark` に help 区別を持たせる

`FailureMarkExt` に `is_help_entry : Bool` を足し、`pub fn failure_mark(name)` のシグネチャを変更する (lowering が `e.help_meta.is_help_preset` を渡す)。

- 利点: resident が 1 つのままで概念が増えない
- 欠点: `failure_mark` は `src/internal/engine` の `pub` かつ `src/kuu-node/node.mbt` 経由で再公開されている**公開 node API**。破壊的変更 (VERSION 0.0.0 のドラフト期なので互換 alias は不要 — DR-068 §3)

### 案 B: help 入口専用の marker resident を足す

`is_help_entry()` を `NodeExt` の既定 false メソッドとして足し、help preset だけが true を返す resident (または `FailureMarkExt` のフラグ付きコンストラクタ) を新設。`find_help_entry_in_greedy` はそちらを見る。

- 利点: 既存 `failure_mark` のシグネチャを壊さない (追加のみ)
- 欠点: `NodeExt` trait に面が 1 つ増える。extension 契約の面積は DR-110 の関心

どちらも `pkg.generated.mbti` が動くので、drift gate (`just mbti-check`) の再生成が要る。

## 受け入れ条件

- [ ] 上表の 2 行目が `ParseFailure.help_entry == None`、3 行目が `Some("--help")` になる
- [ ] `HelpModel.help_entry` と `ParseFailure.help_entry` が同じ定義に対して常に一致する
- [ ] スコープ解決 (DR-053 §4 の失敗位置基準、`fixtures/failure-actions/tried-triggers-scope.json` が pin) が壊れない
- [ ] `fixtures/failure-actions/help-basic.json` / `dd-internal.json` など既存の fired_action / help_entry 系が無傷
- [ ] 既存 conformance が無傷 (decoded=454 / ran_cases=1001 / skipped=0 / mismatches=0)

## 関連

- DR-053 §4 (help_entry / tried_triggers の素材規定)
- DR-113 §7.2 (`is_help_preset` の carry — 同じ判別を別目的で既に持っている)
- DR-048 (失敗時アクションと誘導行)
- D3 の修正済み分: commit `7c8fa4b0` (help model 側の gate + union 由来 Failure への help_entry 付与)
