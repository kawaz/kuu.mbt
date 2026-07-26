---
title: env と CLI が同一 accumulator に供給されると最終値が CLI でも sources が env のまま
status: discarded
category: bug
created: 2026-07-26T14:36:41+09:00
last_read:
open_entered: 2026-07-26T14:36:41+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered: 2026-07-26T20:35:46+09:00
resolved_entered:
discard_reason: ["duplicate:issue/2026-07-26-nameless-seq-accum-source-default.md"]
pending_reason:
close_reason:
blocked_by:
origin: 自リポ TODO
---

# env と CLI が同一 accumulator に供給されると最終値が CLI でも sources が env のまま

## 訂正 (2026-07-26, discard 時)

独立した bug ではなく、`docs/issue/2026-07-26-nameless-seq-accum-source-default.md`
(nameless child を畳む accumulator の source 誤り) の一側面だった。

起票時に使った定義が `seq` + nameless child を持っていたため、env×CLI 固有の問題に
見えていたが、単純な accumulator (nameless child なし) で切り分けたところ、
env×CLI の組み合わせ自体は正しく動くことを確認した:

```
定義 A (単純 accum): {"name":"tags","type":"string","long":true,"env":"TAGS",
                      "multiple":{"accumulator":"append","separator":","}}

env のみ (TAGS=x,y):     result={"tags":["x","y"]}  sources=[{"key":"tags","source":"env"}]   ← 正しい
env + CLI (--tags a):    result={"tags":["a"]}      sources=[{"key":"tags","source":"cli"}]   ← 正しい
CLI のみ:                result={"tags":["a"]}      sources=[{"key":"tags","source":"cli"}]   ← 正しい
```

対して定義 B (seq + nameless child) は env の有無に関わらず誤る (CLI のみでも
`default` を報告する)。原因は nameless child を畳む accumulator の wrapper に
実 binding が着席せず 0-fire と誤判定されること。追跡は
`docs/issue/2026-07-26-nameless-seq-accum-source-default.md` で行う。

## 概要

`env` と `multiple` (accumulator) を持つ要素に、env と CLI の両方から値を供給すると、
**最終値は CLI 由来なのに `sources` が `env` を報告する**。

DR-031 の「source は最終値を確定させた効果 / 充填の由来」に違反。
要素ごとの provenance の話ではなく、**cell 単位でも誤っている**。

## 背景

### 再現 (2026-07-26 実測)

kuu-cli の fresh build (`just generate-self-definition && moon build --target native` 後) で確認。

```json
{"options":[{"name":"pair","long":true,"env":"PAIR",
  "multiple":{"accumulator":"append","separator":":"},
  "seq":[{"type":"string"},{"type":"string"}]}]}
```

env のみ (正しい):

```
PAIR=x:y $bin parse def.json --no-config --
→ {"result":{"pair":["x","y"]},"sources":{"pair":"env"}}
```

env + CLI (誤り):

```
PAIR=x:y $bin parse def.json --no-config -- --pair a b
→ {"result":{"pair":[["a","b"]]},"sources":{"pair":"env"}}
                    ^^^^^^^^^^^                      ^^^
                    最終値は CLI 由来              なのに env
```

`result` は CLI が供給した row (`[["a","b"]]`) になっているのに、`sources` は `env` のまま。
消費者は「この値は環境変数由来」と誤解する。

### 仕様との照合

`docs/decisions/DR-031-value-source-precedence.md` の source 確定ルール:

> source は「**最終値を確定させた効果 / 充填の由来**」であり、以下で一意に決まる:
> - 自分の入口 (long/short/alias 等) からの効果 = `cli`
> - 席の充填 = その席の名 (`env` / `config` / `inherit` / `default`)
> - **あと勝ち mutation 後は最後に勝った効果の source**

CLI が env より上位席 (DR-031 のラダー) であり、実際に最終値も CLI 由来になっているので、
`sources` は `cli` であるべき。

### 原因の見当 (未調査)

accumulator の fold と値源ラダーの充填が別経路で走っており、
`sources` が「ラダーが充填した席」を、`result` が「最後に勝った効果」を見ている可能性。
`src/kuu/resolve.mbt` の `result_sources` / accum 系と、ラダー充填の順序を突き合わせる必要がある。

### 関連

- `docs/decisions/DR-031-value-source-precedence.md` (source 確定ルール、あと勝ち mutation)
- `src/kuu/resolve.mbt` の `result_sources` / accum 系
- spec `fixtures/multiple-parse/unset-env-fallback.json` (unset がラダーを再び開く経路の既存 pin。
  こちらは正しく動く)
- 同時期の調査: spec の `docs/QUESTIONS.md` SRCADDR-Q2-β (要素 provenance)。
  本 bug は要素単位でなく cell 単位の誤りなので独立

## 受け入れ条件

- [ ] 上記の再現で `sources` が `cli` を返す
- [ ] env のみ / CLI のみ の対照が従来どおり (`env` / `cli`)
- [ ] separator split の有無、accumulator の種類 (append / merge 等) を変えても一貫する
- [ ] wbtest で pin
- [ ] spec 側に fixture を足す (`fixtures/value-sources/` 配下。env × cli × accumulator の交差は現状 corpus に無い)
