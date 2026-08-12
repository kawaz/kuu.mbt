---
title: 消費済み command トリガが positional なし子スコープで候補に再露出する
status: resolved
category: bug
created: 2026-08-12T19:55:00+09:00
last_read: 2026-08-12T13:50:21+09:00
open_entered: 2026-08-12T19:55:00+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-08-12T14:36:45+09:00
discard_reason:
pending_reason:
close_reason: ["done: eval.mbt の complete arm に command_scope_selected ガードを追加して修正 (commit 5828c289, Release v0.0.30)","fixture:complete/consumed-command-trigger-no-reexposure.json (pin, conformance 409 decoded / mismatches=0)","cause: 親再開後の complete arm が選択済み command marker を無視していた"]
blocked_by:
origin: DR-116 実装サイクルでの副次観測
---

# 消費済み command トリガが positional なし子スコープで候補に再露出する

`fixtures/complete/command-scope.json` の case `child-scope-candidate-after-entry` は
**「親のコマンド名綴り `build` はもう候補に出ない (トリガは 1 回消費されると再露出しない)」**
を明示的に pin している。この fixture は green だが、**子スコープが positional を 1 つも
持たない構成では同じ性質が破れる**。

## 再現 (実測 2026-08-12、DR-116 実装作業中の probe)

`complete(ast, args_before)` の結果を並べた観測:

| 定義の子スコープ | args_before | 候補 |
|---|---|---|
| option のみ (`alpha`) | `["build"]` | `--alpha`, `--verbose`, **`build`** |
| option のみ (`alpha`) | `["--verbose","build"]` | `--alpha`, `--verbose`, **`build`** |
| positional あり (`target`) | `["build"]` | `--verbose`, (値位置 `target`) |

再露出した `build` 候補は `origin=build` / `path=[build]` / `fire_path=[build]` —
つまり **build スコープの内側から** 提示されている。

global option の有無は無関係 (上表 2 行目と 1 行目が同結果、global なし版も同じ)。
差が出るのは **子スコープに positional があるかどうか** だけ。

定義 (option のみ版):

```json
{"options":[{"name":"verbose","type":"flag","long":true}],
 "commands":[{"type":"command","name":"build",
   "options":[{"name":"alpha","type":"flag","long":true}]}]}
```

## 仮説 (未検証 — 裏取りしてから採否を決めること)

子スコープの背骨が何も消費しない (options だけで positional が無い) 構成では、
親の greedy 面がまだ同じトークン位置で生きている読みが残り、command トリガ衛星が
もう一度提示されるのではないか。`fixtures/complete/command-scope.json` の子スコープは
positional `target` を持つため、この経路を踏んでいない = **corpus のカバレッジ欠落**。

## 影響

補完面で、既に入ったサブコマンド名がもう一度候補に並ぶ。DR-116 の生成器 policy 側では
救えない (素材段の候補集合そのものが多い) ため、engine 側の課題。

なお canonical 生成器から見ると、この候補は子スコープの help model に対応 entry を持たない
ため説明なしで末尾に並ぶ。DR-116 実装 (`completion_query`) はこの候補を特別扱いしていない。

## 次の一手

1. 上記仮説を engine の読み (`scope_step` / greedy 面の再評価) で裏取りする
2. `fixtures/complete/command-scope.json` に **positional を持たない子スコープ** の case を
   足すか、別 fixture を起こすか判断する (spec 側の課題 — corpus 欠落の是正)
3. engine を直す場合、`command-scope/*` 系の既存 fixture への波及を確認する
