---
title: FloatArg の spine アーム欠落 (先食い/complete) と TBool/TFloat の残ギャップ
status: resolved
category: bug
created: 2026-07-08T11:47:59+09:00
last_read:
open_entered: 2026-07-08T11:47:59+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-08T12:26:54+09:00
discard_reason:
pending_reason:
close_reason: ["done:spine 4関数(scope_consume/consume_head/scope_consume_rep/head_elem_names_into)にNumArg/IntArg対称のFloatArgアーム追加(complete分岐込み)","done:RED先行で先食み(greedy raw-eat)×3+DR-065名前集合脱落×1の計4件の実誤動作を実証してからGREEN化","done:commit 8ef5bf88 (git sha 62f5d9a)、regression testはeval_wbtest.mbt末尾4本"]
blocked_by:
origin: 自リポ TODO (kuu.mbt 参照実装コードの静的読解で発見)
---

# FloatArg の spine アーム欠落 (先食い/complete) と TBool/TFloat の残ギャップ

## 概要

kuu.mbt (参照実装、コミット `10af5d4128eb`) の `src/core/eval.mbt` にある spine 系の match 関数群で、`FloatArg` が固有アームを持たず汎用 catch-all (`other`/`_` → `eval(...)`) に落ちている。兄弟型 `NumArg` は同じ関数群すべてで固有アームを持ち `suppressed(sc, ctx, pos, severed)` (先食い抑制) チェックを経由するが、`FloatArg` はこのチェックを経由しない。

該当箇所 (いずれも `NumArg` に固有アームがあり `FloatArg` が無い):

- **`scope_consume`** (eval.mbt:933-) — spine 上の直接消費。`FloatArg` は末尾の `other => { eval(other, ctx, pos) を呼んで継続 }` (1188 行目以降) に落ちる。
- **`consume_head`** (eval.mbt:1348-) — repeat head の消費。`FloatArg` は末尾の `_ => eval(head, ctx, pos)` (1444 行目) に落ちる。このすぐ上のコメントが該当理由をそのまま説明している: 「ReqArg / FilterArg get their own arms so 先食い (suppressed) applies — eval() does not see the parent scope, so falling through would let a greedy trigger token be raw-eaten as the repeat head's value.」FloatArg にはこの理由がそのまま当てはまるのに固有アームが無い。
- **`scope_consume_rep`** (eval.mbt:1578-) — repeat unfold 経由の消費。`FloatArg` は末尾の `_ => { eval(inner, ...) }` (1622 行目) に落ちる。
- **`head_elem_names_into`** (eval.mbt:1479-) — repeat head の value-primitive 名収集 (DR-065 §3 held-error parity、`drop_optional_missing` が参照)。`StrArg`/`SepArg`/`NumArg`/`FilterArg`/`ReqArg` は明示アームで `out` に名前を積むが `FloatArg` にアームが無く、catch-all の再帰対象にも含まれないため FloatArg head の名前が集合に入らない。

一方、非 spine の単純な `eval()` (eval.mbt:280-) には `FloatArg` の固有アームが既にあり、EOF での `Pending([pend_value(TFloat, name)], [])` も正しく出している。ギャップは spine 系の上記 4 関数だけに限定される。

## 背景

`value_prim` (installer.mbt:162-) は `TFloat` を専用ノード `FloatArg` に lowering する (DR-074 §1 の広い受理域 = number + inf、`NumArg`/`parse_number` とは別 lexicon `parse_float`)。この専用ノード導入時、非 spine の `eval()` には対応するアームが追加されたが、spine 系の 4 関数への横展開が漏れたと見られる。

`consume_head` の既存コメントが `ReqArg`/`FilterArg` について「固有アームが無いと先食い抑制が効かず、repeat head の値として greedy トリガトークンが raw-eat されてしまう」と明記しており、同じ懸念が `FloatArg` にもそのまま当てはまる。

## 影響 (推測、要検証)

- **先食い抑制の欠落**: 裸の positional `FloatArg` (Exact トリガを伴わない) や repeat head としての `FloatArg` (`Many(FloatArg(...))` / indexed repeat) が spine 上に現れた場合、隣接する greedy トリガのトークンを `suppressed` チェック無しに raw-eat してしまう可能性がある。`consume_head` のコメントが `ReqArg`/`FilterArg` について明示している事故パターンと同型。
- **repeat head 名前集合からの脱落**: `head_elem_names_into` に `FloatArg` が無いため、`FloatArg` を head に持つ optional repeat の「もう1回分」用 missing_operand 抑制 (DR-065 §3) が効かない可能性がある。

いずれも実際に誤った振る舞いを引き起こすかはユニット/wbtest での再現確認が必要 (未検証、上記は静的コード読解からの仮説)。

## 関連 (別軸、本 issue のスコープ外)

- TBool の reason 語彙ギャップは spec リポ (kawaz/kuu) の issue `docs/issue/2026-07-07-bool-invalid-reason-vocab-gap.md` で追跡中
- TFloat/number の細部規則 fixture 網羅は spec リポ (kawaz/kuu) の issue `docs/issue/2026-07-06-value-typing-s7-fixtures.md` で追跡中
- 本 issue はこれらとは独立な、kuu.mbt 実装コード側の spine アーム対称性の欠落 (実装バグ疑い) を扱う

## 受け入れ条件

- [ ] `scope_consume` / `consume_head` / `scope_consume_rep` / `head_elem_names_into` の 4 関数に `NumArg` と対称な `FloatArg` 固有アームを追加 (`parse_number`→`parse_float`、`TNum`→`TFloat`)
- [ ] 上記の欠落が実際に誤動作を引き起こすことを示す regression test (裸 positional FloatArg + 隣接 greedy トリガの先食い合戦、`Many(FloatArg(...))` repeat head のケース) を先に RED で書き、修正後 GREEN にする
- [ ] 修正が `eval_wbtest.mbt:829` 付近の既存 DR-074 §1 FloatArg テスト群を壊さないことを確認
