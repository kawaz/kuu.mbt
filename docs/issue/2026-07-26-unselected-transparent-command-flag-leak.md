---
title: 未選択の transparent command 配下の未発火 flag が root に昇格して result に現れる
status: open
category: bug
created: 2026-07-26T18:34:45+09:00
last_read:
open_entered: 2026-07-26T18:34:45+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
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
