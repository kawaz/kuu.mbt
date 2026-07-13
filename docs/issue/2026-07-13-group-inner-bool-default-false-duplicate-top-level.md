---
title: plain bool (TBool) への暗黙 default:false 注入は spec 違反 — 未発火は absent が正
status: open
category: bug
created: 2026-07-13T09:38:57+09:00
last_read:
open_entered: 2026-07-13T09:38:57+09:00
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

# plain bool (TBool) への暗黙 default:false 注入は spec 違反 — 未発火は absent が正

## 概要

`ensure_entity` が暗黙 default:false を entity に注入する対象が広すぎる。spec の教義
(LOWERING §A.5「flag = bool + default:false + long 綴り合成」、DESIGN §9.3) では
**default:false は flag preset (`TFlag`、count 含む) 固有の展開**であり、plain bool
(`TBool`) は暗黙 default を持たない — 未発火・値源なしなら他の値型と同様に absent
(DR-099 §2 の `resolved_default = fold(観測) ?? 宣言 default ?? absent` 終端、
`fixtures/value-sources/tty-ladder.json` の absent pin と整合)。

この spec 違反は 2 つの形で露出する (同根、本 issue で一括対応):

1. **or 枝の未選択 bool leaf / 未発火 plain bool option が `false` で漏れる**
   (`fixtures/value-typing/or-leaf-factory-config.json` case
   `bool-dialect-or-leaf-fallback-to-int-branch` / `bool-dialect-direct-option-baseline` が pin)
2. **group 内側 bool の top-level への `false` 重複** (本 issue の当初の報告対象、
   `fixtures/value-typing/positional-group-factory-config.json` case
   `group-inner-leaf-carries-true` / `group-inner-leaf-carries-false` が pin)

2026-07-13 の `moon test` 実行で上記 4 case すべてが divergence ledger に UNEXPECTED として
実測された:

```
value-typing/or-leaf-factory-config.json::bool-dialect-or-leaf-fallback-to-int-branch :: result got={ctrl=false,switch_bool=false,switch_n=5} want={switch_n=5}
value-typing/or-leaf-factory-config.json::bool-dialect-direct-option-baseline :: result got={ctrl=true,switch_bool=false} want={ctrl=true}
value-typing/positional-group-factory-config.json::group-inner-leaf-carries-true :: result got={ctrl=true,gflag=false,grp=[{gflag=true}]} want={ctrl=true,grp=[{gflag=true}]}
value-typing/positional-group-factory-config.json::group-inner-leaf-carries-false :: result got={ctrl=false,gflag=false,grp=[{gflag=false}]} want={ctrl=false,grp=[{gflag=false}]}
```

同 ledger には他に 3 件 (`bool-dialect-or-leaf-carries-true/false`,
`base-prefix-or-leaf-carries`) が UNEXPECTED として並ぶが、これらは別根の
factory config carry gap で既 issue
`docs/issue/2026-07-12-typeshadow-carry-gap-or-leaf-positional-group.md` の追跡対象
(本 issue の scope 外)。

## 背景

spec fixture `fixtures/value-typing/positional-group-factory-config.json` (未 push) の live 検証で
発見 (2026-07-13)。ケース `group-inner-leaf-carries-true` (argv `["yes","yes"]`) /
`group-inner-leaf-carries-false` (argv `["no","no"]`) の `expect.result` は
`{"ctrl": <bool>, "grp": [{"gflag": <bool>}]}` のみで top-level に `gflag` キーを含まないが、
実装の実際の出力は `gflag` を top-level にも (`false` で) 重複出現させる。

根因: `ensure_entity` が暗黙 default:false を `TFlag` (+count) だけでなく plain bool
(`TBool`) にも同じ注入規則で適用している。group 入れ子のスコープを無視しているのではなく、
**plain bool への暗黙 default:false 注入自体が spec 違反** (詳細は上記「概要」参照)。
DR-099 実装 (`is_tty` を注入対象から除外した箇所) と同じ `ensure_entity` が関連する —
今度は `TBool` 自体を除外する番。

同 fixture と対をなす or 枝側の carry gap
(`fixtures/value-typing/or-leaf-factory-config.json` の case 1/2/4:
`bool-dialect-or-leaf-carries-true` / `bool-dialect-or-leaf-carries-false` /
`base-prefix-or-leaf-carries` が pin する `dec_or_leaf` の factory config carry gap) は
既 issue `docs/issue/2026-07-12-typeshadow-carry-gap-or-leaf-positional-group.md` が追跡中。
この既 issue のタイトル・背景にあった「`dec_positional_group` も未配線」という記述は本 issue の
調査過程で誤りと判明した (group 側は `dec_positional` 再帰経由で `TypeShadow` の全フィールドが
既に carry 済み — `dec_or_leaf` だけが `base`/`int_round` の 2 フィールドに絞られている)。
該当既 issue 側は本 issue と同時に記述を訂正済み。

## 修正方針

`ensure_entity` の暗黙 default:false 注入対象を `TFlag` (+count) のみに絞る。DR-099 実装が
`is_tty` を注入対象から除外した箇所と同じ場所で、今度は `TBool` 自体を除外する。

回帰リスク: spec fixture corpus (2026-07-13 時点で 523 case) のうち、未発火 plain bool の
absent を明示的に pin しているのは本 issue が対象にする上記 4 case のみ。残りの corpus は
この挙動を検証していないため、注入対象を狭める変更が既存 green ケースを壊す可能性は低い。

## 受け入れ条件

- [ ] `fixtures/value-typing/positional-group-factory-config.json` の case
      `group-inner-leaf-carries-true` / `group-inner-leaf-carries-false` が green になる
      (= top-level への `gflag` 重複出現が消え、`grp` row 内側の値のみが正になる)
- [ ] `fixtures/value-typing/or-leaf-factory-config.json` の case
      `bool-dialect-or-leaf-fallback-to-int-branch` / `bool-dialect-direct-option-baseline`
      が green になる (= 未発火の `ctrl` / `switch_bool` が result に `false` で漏れなくなる)
- [ ] 上記 4 case 以外の corpus (`moon test` の divergence ledger) に新規 UNEXPECTED
      divergence が増えない (= 回帰なし)
