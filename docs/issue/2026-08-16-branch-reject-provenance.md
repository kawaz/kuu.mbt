---
title: abi.Branch / ParseError が Reject の出自 (provenance) を運ばない — 敗北 or 枝の診断が残余に混入する
status: open
category: design
created: 2026-08-16T12:17:34+09:00
last_read:
open_entered: 2026-08-16T12:17:34+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: DR-138 §6b 実装サイクル (2026-08-16) の (A) 案調査
---

# abi.Branch / ParseError が Reject の出自 (provenance) を運ばない — 敗北 or 枝の診断が残余に混入する

## 概要

or の**敗北した alternative** が残した held 診断が、別の読みが成立した後でも最終エラー集合に
残る。DR-037 は「解けた枝が 1 個ならその枝で確定、他枝の Reject / Error は捨てる」と定めるが、
実装はこれを表現できない — `abi.Branch` の `Rejected(ParseError, Array[Binding])` が
**その Reject がどこから来たか**を運ばないため、捨てて良い診断とそうでないものを区別できない。

known_divergences に 1 件登録済み (解消時に台帳から外れる):

```
or-parse/option-structural-or-outer-repeat.json::max-cap-leaves-residue
  --sel a b c → got {@3/unexpected_token, n@1/not_a_number, n@3/not_a_number}
                want {@3/unexpected_token}
```

fixture が正。失敗の判定自体は正しく (誤成功ではない)、余分な診断が 2 件付く。

## 背景 — Or ローカルでは原理的に解けない (計装で確認済み)

「or の解決点で敗北枝の Held を落とす」案を、**branch を produce する Or arm 全 9 箇所**
(`eval` / `consume_compound` / `step_greedy` / CPS 版 2 箇所を含む) に入れて反証した。
計装データ:

```
MAKE zzn@1 → RES range=2 acc=1 resolved=true    ← 落ちる
MAKE zzn@3 → RES range=2 acc=0 resolved=false
MAKE zzn@1 / MAKE zzn@3 → RES acc=0 resolved=false  ← この読みが生き残る
PUSH zzn@1
```

生き残る評価では **その Or に Accept が 1 つも無い** (acc=0)。つまりその読みの中では全枝が
落ちており、DR-037 の「0 個 → 保持された Error を見せる」が正しく効いている。消してほしい
理由は「**別の読みが成立している**」ことであって、Or ローカルの情報では届かない。

## 試して反証した案 (すべて巻き戻し済み)

1. **number 系 resident を disposition 準拠へ** (`@abi.Held` 直書きをやめ `type_parse_branch` へ)
   → `piece-filters/parse-rescue` と `value-typing/number-inf-nan` の 3 case がエラーを失って回帰。
   単発の値スロットはこの直書き Held に依存している
2. **`eval_required_ext` の Rejected→Held 昇格を止める** → 単独では無効 (leaf が Held 直書きのため)
3. **1 + 2 の組み合わせ** (`NodeExt::choice_leaf` を新設し resident 自身に選択葉の印を持たせる)
   → **or-parse は green になる**が、`path-search/held-errors-{distinct,same}-depth` が
   `got={}` で回帰。全枝が落ちた時に診断がゼロになり、DR-037「0 個」条項に反する
4. **3 + 「held が 1 件も無い時だけ Reject 由来を見せる」救済** → `piece-filters/reject` /
   `regex-match` / `link-parse/value-residual-field-write` の 6 case が回帰。filter の Reject と
   値残余の枝 Reject は**黙って落ちるのが正**なので、救済が広すぎる

## 行き止まりの正体

必要な区別は「**この Reject は選択文脈の値空間ミス由来か**」だが、`ParseError` にも
`abi.Branch` にもその出自を運ぶ場所が無い。以下が `Rejected(ParseError, _)` の時点で
**すべて同じ形**になる:

- 選択葉 (or の alternative) の型ミス → 兄弟枝が成立すれば捨てて良い
- filter の Reject (DR-037) → 常に黙って落ちる
- 値残余の解決失敗 (DR-127 §4.2) → 常に黙って落ちる

## 受け入れ条件

- [ ] Reject の出自を区別する形が入っている (`abi.Branch` の新 variant、または `ParseError` の
      provenance フィールド。wire 非公開の内部区別で足りるはず)
- [ ] 「兄弟枝が成立したら捨てる / 全枝落ちなら見せる」が出自ごとに正しく分岐している
- [ ] 上記 4 案で回帰した fixture 群 (`path-search/held-errors-*` / `piece-filters/reject` /
      `regex-match` / `link-parse/value-residual-field-write` / `number-inf-nan` /
      `parse-rescue`) がすべて green のまま
- [ ] known_divergences から当該 1 件が外れている (VANISHED も fail する運用なので自動検出される)

## 付随して片付けたいもの

- `Or(alts)` と `Or(alternatives)` の**別名束縛が混在**している (branch を produce する arm が
  9 箇所、うち 2 箇所が `alternatives`)。全評価器が match する中核なので、provenance 変更の
  ついでに束縛名と走査の網羅性を揃えると事故が減る

## 統括メモ

`abi.Branch` は全評価器が match する中核 enum なので、**先に spec 側へ「診断 provenance」の
DR を起こす**必要がある可能性が高い。DR-037 は Reject / Error の 2 値しか定めておらず、
「どの Reject が、どの範囲の成立によって捨てられるか」は未規定。実装先行だと発明になる。
