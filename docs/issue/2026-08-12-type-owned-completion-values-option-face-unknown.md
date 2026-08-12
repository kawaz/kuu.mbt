---
title: 型所有の展開値候補が option 配置で UnknownFace に落ち説明を引き直せない (RE-1)
status: open
category: bug
created: 2026-08-12T00:00:00+09:00
last_read:
open_entered: 2026-08-12T00:00:00+09:00
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

# 型所有の展開値候補が option 配置で UnknownFace に落ち説明を引き直せない (RE-1)

## 概要

engine の `expand_type_completion_values` が供給する「型所有の展開値候補」は
`is_value:false` / `origin` = 持ち主要素名 / 綴りは宣言外 (例:
`completion_script` 型が供給する `zsh` / `bash` / `fish`) という形をとる。
`src/kuu/completion_query.mbt` の `candidate_face` は exact 候補を「その面が
実際に宣言している綴り」で判定する 4 連 (command 名 → command alias →
option_spellings → option alias) を通すが、綴りが宣言外なのでいずれにも
当たらず、最後の positional 名前照合だけが拾う。したがって option 配置では
`UnknownFace` に落ち、DR-116 §4 の説明引き直しが効かない。positional 配置は
名前照合に掛かって `PositionalFace` に入るため説明が付く — 同じ型・同じ
候補形なのに配置面で観測が割れる非対称。

## 背景

実測 (2026-08-12、probe):

- positional 配置
  `{"positionals":[{"name":"shell","type":"completion_script","help":"target shell"}]}`
  → 応答 `zsh\ttarget shell` / `bash\ttarget shell` / `fish\ttarget shell`
  (説明あり)
- option 配置
  `{"options":[{"name":"shell","type":"completion_script","long":true,"help":"target shell"}]}`
  で `app --shell <TAB>` → 応答 `zsh` / `bash` (説明なし)

positional 側は `src/kuu/completion_query_wbtest.mbt` の test
"DR-116 §4: positional 配置の型所有展開値は positional の説明を引き直す" で
pin 済み。本 issue は option 側の欠落。

優先度: リリース比の後退ではない (v0.0.24 も説明を引けていなかった) ので
実装修正は次サイクルで良い。

## 受け入れ条件

- [ ] option 配置でも型所有の展開値候補が対応する option の help を引き直す
- [ ] 一意性が崩れる構成 (同名の option と positional が併存等) での挙動を
      裏取りした上で対応する
- [ ] 回帰防止テストを追加する

## 修正方向 (未裏取りの一案)

fable レビュー提案。宣言綴り照合 4 連の後・`UnknownFace` へ落とす前に
「origin 名が値スロットを持つ要素に一意に当たるなら当該面を採る」fallback
を足す。ただし一意性が崩れる構成 (同名の option と positional が併存) での
挙動と、面を取り違えるリスクを裏取りしてから採否を決めること。
