---
title: command node の value: — carrier 不在 + 意味論未規定でスコープ外に切った分
status: open
category: bug
created: 2026-07-27T02:03:28+09:00
last_read:
open_entered: 2026-07-27T02:03:28+09:00
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

# command node の value: — carrier 不在 + 意味論未規定でスコープ外に切った分

## 概要

issue 2026-07-26-value-default-unimplemented-root-positions の残り 1 配置。option root / positional root の `value:` は実装済み (commit 4da51dd6、`const_values` carrier + DR-031 CONST-Q1=a の const 意味論)。**command node の `value:` だけ未対応**のまま残った。

## 背景 (なぜスコープ外にしたか — 調査結果)

1. **carrier が無い**: `CommandDef` は `{name, body, export_key}` の 3 フィールドのみ (src/internal/engine/declaration.mbt:292)。type も値セルも持たない。option/positional の `ElementDef` (値属性一式を持つ) とは carrier の形からして別物なので、`const_values` を足すだけでは届かない。
2. **意味論が spec 未規定**: command の結果キーは「子スコープの object」を主張する。そこへ値セルを足すと、同じ結果キーが object とスカラー値を同時に主張することになる。この衝突をどう解くかは spec に規定が無い。DR-017 (command 一級扱い、内部正規形は同型) は**構造**の同型を言っているのであって、command node が値セルを持つとは言っていない。

つまり carrier 変更 + 新規裁定の両方が要る。option/positional root の const (= DR-030 実体だけノードの本命ユースケース) とは独立した課題。

## 現状の挙動

`dec_command` の allowed_keys に `value` が無いので malformed_definition で弾かれる (黙って捨ててはいない)。

## 着手前に要る裁定

- command の結果キーが object と値を同時に持つ形を認めるか / 認めないなら明示 definition-error にするか
- 認める場合、`{"name":"build","value":X,"options":[...]}` の result 形をどうするか

## 参照

- src/kuu/wire_decode.mbt の `dec_command` (allowed_keys)
- src/internal/engine/declaration.mbt:292 `CommandDef`
- 実装済み側: `ElementDef.const_values` / `Entity.const_values` の doc comment、resolve.mbt の const 枝

## 受け入れ条件

- [ ] command 結果キーが object と値を同時に持つケースの扱いについて裁定が下る
- [ ] 裁定に基づき `CommandDef` の carrier 拡張または明示 definition-error 化のいずれかが実装される
