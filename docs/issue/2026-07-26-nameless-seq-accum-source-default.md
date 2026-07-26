---
title: nameless child を畳む accumulator が発火しても source が default のまま
status: open
category: bug
created: 2026-07-26T20:34:32+09:00
last_read: 2026-07-26T21:28:15+09:00
open_entered: 2026-07-26T20:34:32+09:00
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

# nameless child を畳む accumulator が発火しても source が default のまま

## 概要

`multiple` (accumulator) を持つ要素の `seq` 子が **nameless** の場合、CLI で発火しても
`sources` が `default` を報告する。値は入っているのに「未発火」と言っている。

2026-07-26 に「named seq/or の accumulator が発火後も wrapper に default を残す」bug を直したが、
**nameless child のケースが残っていた**。

## 背景

### 再現 (実測、fresh build)

```
A: 単純 accum      {"name":"tags","type":"string","long":true,"multiple":"append"}
   --tags v      → result={"tags":["v"]}         sources=[{"key":"tags","source":"cli"}]      ← 正しい

B: seq + nameless  {"name":"pair","long":true,"multiple":"append",
                    "seq":[{"type":"string"},{"type":"string"}]}
   --pair a b    → result={"pair":[["a","b"]]}   sources=[{"key":"pair","source":"default"}]  ← 誤り

C: seq + named     {"name":"pair","long":true,"multiple":"append",
                    "seq":[{"name":"k","type":"string"},{"name":"v","type":"string"}]}
   --pair a b    → result={"pair":[{"k":"a","v":"b"}]}
                   sources=[{"path":["pair"],"key":"k","source":"cli"},
                            {"path":["pair"],"key":"v","source":"cli"}]                        ← 正しい
```

**B だけが誤る。** nameless child の値は wrapper の結果アドレスに畳まれるが、
実 binding は child cell に着席しない (child に entity が無い) ため、wrapper address に
SourceEntry が無く 0-fire と誤判定されて `accum_cells` の default fallback が入る。

### 仕様との照合

DR-031 の source 確定ルール: source は「最終値を確定させた効果 / 充填の由来」。
CLI で `["a","b"]` が入っているので `cli` であるべき。

DR-121 §3.2 は「structural aggregate の複数値 (tuple) は要素ごとに entry」と裁定しているが、
**その addressing 形式が未確定**なので実装は保留中
(spec `docs/issue/2026-07-26-array-element-provenance-sources-addressing.md`)。
本 issue は「要素ごとにするか」以前の問題で、**wrapper に 1 エントリ出すなら少なくとも
`default` は誤り**という話。

## 想定される直し方 (実装側の判断)

以前の修正 (`fix(resolve): accum の default 席は 0 回発火のときだけ足す`) と同型。
「wrapper address に entry が無い = 0 fire」という判定が、nameless child のケースで
成立しない。発火の有無を別の手段で判定する必要がある。

DR-121 §3.2 の要素ごと addressing が決まれば本件も自然に解消する可能性があるので、
**先にそちらの裁定を待つ選択もある**。ただし現状は「値があるのに default」という
明確な誤報なので、暫定でも直す価値がある。

## 受け入れ条件

- [ ] 定義 B で `--pair a b` の source が `default` でない
      (`cli` にするか、要素ごとの entry にするかは DR-121 §3.2 の addressing 次第)
- [ ] 定義 A / C は従来どおり (回帰なし)
- [ ] 0 回発火の accum は従来どおり `default` (`sources-under-command.json` の
      `unfired-cells-default-under-command` が pin 済み)
- [ ] wbtest で pin
- [ ] spec 側に fixture 追加 (nameless child の accum × sources は corpus に 0 件)

## 関連

- spec `docs/decisions/DR-121-sources-result-address.md` §3.2 (structural aggregate の複数値)
- spec `docs/issue/2026-07-26-array-element-provenance-sources-addressing.md` (addressing の裁定待ち)
- spec `docs/decisions/DR-031-value-source-precedence.md` (source 確定ルール)
- `src/kuu/resolve.mbt` の `collect_accum` / `collect_sources_tree` の accum fallback
- 先行修正: archive の `2026-07-26-sources-projection-skips-export-key-under-commands.md`
  (named seq/or の accumulator が発火後も default を残していた分)

## TODO

<!-- wip 時のみ -->
