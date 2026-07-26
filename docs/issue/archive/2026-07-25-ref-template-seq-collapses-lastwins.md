---
title: ref テンプレ経由の無名子 seq が配列形を失い last-wins で 1 個に潰れる
status: resolved
category: bug
created: 2026-07-25T22:56:26+09:00
last_read:
open_entered: 2026-07-25T22:56:26+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-26T11:57:30+09:00
discard_reason:
pending_reason:
close_reason: ["implemented: kuu.mbt commit 0ffc3a5c で seq_body_node を engine 側に切り出し、inline seq / or 枝 / templates の 3 経路で seq_child_nodes による同じ畳み方を共有させて解消。spec fixture 案 (seq-parse/ref-template-parity.json) は統括へ報告済みだが spec への書き込みは未実施。"]
blocked_by:
origin: 自リポ TODO
---

# ref テンプレ経由の無名子 seq が配列形を失い last-wins で 1 個に潰れる

## 概要

2026-07-25 実測 (commit a2fa856f 適用後)。`definitions.templates` に
`{"seq":[{"type":"string"},{"type":"string"}]}` を置いて ref した option に対し
`args --pair a 1` を与えると、result は `{"pair": "1"}` になる。両子が同じ無名
キーに束ねられ last-wins で 1 個が消えている。期待は `{"pair": ["a","1"]}`
(DESIGN §5.1 の「seq = 子の値の配列」)。

## 背景

inline seq 側は commit a2fa856f 以降正しく `["a","1"]` を返すので、同じ構造を
書く 2 つの経路 (inline seq と ref テンプレ) で結果形が割れている。DR-078 §1
は inline seq と ref を同じ構造の別の書き口と位置づけているので、結果形が
経路に依存するのは spec 違反。

今回の inline seq 側 bug (名前付き子が kv に畳まれない) のちょうど鏡像に
あたる。修正は `or_branch_node` に inline seq 側と同じ条件分岐 (結果キーを
持つ子が 1 つでもあるか) を入れる形になるが、or 枝と positional グループの
共有経路なので影響範囲が広い。

着手前に、その 3 経路 (ref テンプレ / or 枝 / positional グループ) それぞれで
現在どういう結果形になっているかのマトリクスを取ること。spec fixture として
は `fixtures/seq-parse/` に ref 経由版の断面を足すのが自然 (inline 版は
commit 4fa85041 で pin 済み)。

## 受け入れ条件

- [ ] ref テンプレ経由の無名子 seq が配列形 (`["a","1"]`) を保持する
- [ ] ref テンプレ / or 枝 / positional グループの 3 経路で結果形が一致する
      ことを検証するマトリクスを取得済み
- [ ] `fixtures/seq-parse/` に ref 経由版の断面 fixture を追加
