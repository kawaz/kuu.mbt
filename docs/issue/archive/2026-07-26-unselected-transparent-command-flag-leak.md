---
title: 未選択の transparent command 配下の未発火 flag が root に昇格して result に現れる
status: resolved
category: bug
created: 2026-07-26T18:34:45+09:00
last_read:
open_entered: 2026-07-26T18:34:45+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-26T20:29:32+09:00
discard_reason:
pending_reason:
close_reason: ["implemented:resolve.mbt の collect_defaults/collect_accum/internal_cells/collect_config_file_seats へ @engine.scope_selected gate 追加 (2 commit)","implemented:範囲は当初報告より広く、flag default だけでなく accum セル・内部セル (config_file/none) も同型に漏れていた","implemented:内部セルの漏れは negative list 経由で root の同名セルを巻き添え除外する実害あり (config_file/none とも)","implemented:accum は identity 側で result に無いキーが sources にある非対称も発見・修正 (DR-121 §2)","implemented:既存 fixture failure-actions/ambiguous-under-command-scope.json の誤った期待値 (root への rest 漏れ) も訂正","implemented:検証は decoded=350 ran_cases=792 skipped=0 mismatches=0 / wbtest 515 passed、追加 wbtest 15 本","done:spec 側 fixture 4 本 (export-key/unselected-scope-no-default-leak, unselected-scope-nested-promotion, unselected-scope-internal-cell-mask, failure-actions訂正) は作成済み・未push"]
blocked_by:
origin: kuu (spec)
---

# 未選択の transparent command 配下の未発火 flag が root に昇格して result に現れる

## 概要

`export_key: null` (透過) の command が**選ばれていない**のに、その配下の未発火 flag の
preset default が root へ昇格して `result` に現れる。DR-051 (値の無い要素は結果に出ない) 違反。

さらに `sources` には現れないため、**`result` と `sources` が非対称**になる
(DR-121 §2「result にキーがあるものは sources にもある」に反する)。

2026-07-26 の P0 fixture 採取中に発見。

## 背景

### 再現 (実測、fresh build)

```json
{"commands":[
  {"type":"command","name":"a","options":[{"name":"keep","type":"flag","long":true}]},
  {"type":"command","name":"c","export_key":null,"options":[{"name":"keep","type":"flag","long":true}]}]}
```

```
$bin parse def.json --no-env --no-config -- a --keep
→ result:  {"a":{"keep":true}, "keep":false}
                                ^^^^^^^^^^^^ c 配下の keep が root に昇格している
   sources: [{"path":["a"],"key":"keep","source":"cli"}]
                                ^ root の keep に対応する entry が無い
```

`c` は選ばれていないので、その配下は absent であるべき。

#### 対照: transparent command を消すと出ない

```json
{"commands":[{"type":"command","name":"a","options":[{"name":"keep","type":"flag","long":true}]}]}
```

```
→ result: {"a":{"keep":true}}   ← root に keep が出ない (正しい)
```

#### 対照: 通常の command (identity) なら出ない

`c` の `export_key: null` を外すと root に `keep` は現れない。**透過昇格の経路だけで起きる。**

### なぜ問題か

1. **DR-051 違反**: 未選択 command の配下セルは値源を持たないので absent であるべき
2. **result と sources の非対称**: DR-121 §2 は「sources が席を持つのは値源ラダーが確定した
   値セル」と規定し、`result` にキーがあるものは (presence marker を除き) `sources` にもある。
   本件は result にあって sources に無いので、消費者が `result.keep` の由来を引けない
3. **透過昇格の意味論**: DR-052 §2 の昇格は「選ばれた透過スコープの子が親へ上がる」であって、
   選ばれていないスコープの子まで昇格させる規定ではない (`fixtures/export-key/command-promote.json`
   の `promote-empty-child` は「選ばれた」場合を pin している)

## 受け入れ条件

- [ ] 未選択の transparent command 配下のセルが `result` に現れない
- [ ] 選択された transparent command 配下は従来どおり昇格する
      (`fixtures/export-key/command-promote.json` が pin 済み、期待値不変)
- [ ] transparent command が複数あり片方だけ選ばれた場合も、選ばれた側だけが昇格する
- [ ] wbtest で pin
- [ ] spec 側に fixture を追加 (未選択 transparent command × 配下の preset default 持ちセル、
      という断面は corpus に無い)

## 関連

- spec `docs/decisions/DR-051-*.md` (absent 規則)
- spec `docs/decisions/DR-052-export-key-unification.md` §2 (透過昇格)
- spec `docs/decisions/DR-121-sources-result-address.md` §2 (席の単位、result と sources の対応)
- spec `fixtures/export-key/command-promote.json` (選ばれた透過 command の昇格を pin)
- 同時期の断面調査: spec `docs/issue/2026-07-26-projection-verification-structural-gaps.md`
