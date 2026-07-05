---
title: 透過要素の SCALAR 昇格判定が兄弟セル存在 heuristic で、兄弟なし kv 文脈に latent 穴
status: open
category: bug
created: 2026-07-06T02:55:15+09:00
last_read:
open_entered: 2026-07-06T02:55:15+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (docs/decisions/DR-052-export-key-unification.md §2)
---

# 透過要素の SCALAR 昇格判定が兄弟セル存在 heuristic で、兄弟なし kv 文脈に latent 穴

## 概要

`result.mbt` の `build_result` にある SCALAR 昇格条件は「同 path に accum
cell / scalar default が居るか」(`has_object_cell_here`) という **兄弟セル
存在 heuristic** で判定している。透過要素 (`export_key:null`) が唯一の
発火であり、かつ非透過な兄弟が preset default cell を持たない kv 文脈では、
この heuristic が偽陰性を起こし `RScalar` に昇格してしまう。

具体構成での再現条件:

```
options = [
  { verbose: flag, export_key: null },   # 透過要素
  { name: string }                        # preset default なし
]
argv = [--verbose]
```

- `defaults` は `apply_export_to_defaults` が `EkNull` 分を drop する
  (`result.mbt:171` 付近) ため、`verbose` の透過セルは defaults 側に残らない
- `name` は default cell を持たないため `has_object_cell_here` が `false`
  を返す
- 結果、`RScalar(true)` に昇格してしまう

DR-052 §2 の規定 (kv 文脈では値ごと消える = `{}` になるべき) に照らすと、
この構成の期待結果は `{}` であり、`RScalar(true)` は誤り。

現行の fixture セットには該当する組合せ (透過要素が唯一の発火 + 非透過
兄弟が preset default なし) が存在しないため、**現時点では顕在化していない
latent bug**。

## 背景

`build_result` の SCALAR 昇格ロジックは「兄弟セルの有無」を kv 文脈判定の
代理指標として使っているが、これは本質的な判定基準ではない。原理的な
判定基準は「今 `[]` (配列/seq) 要素の再帰の内側で処理しているか」であり、
これは `build_result` 呼び出し経路の唯一の入口が `ARRAY` 分岐であるため、
構造的に (= 兄弟の有無を見ずに) 判定可能なはず。

発見経緯: transparent-kv 修正 (commit `333cbf7be8`) の Fable レビュー時に、
現行 heuristic の適用範囲外となる境界ケースとして指摘された。

一次資料:

- `kawaz/kuu` main の `docs/decisions/DR-052-export-key-unification.md` §2
  (kv 文脈での透過要素は値ごと消える)
- slice の `result.mbt` (`build_result` の `has_object_cell_here` 判定、
  `apply_export_to_defaults` の `EkNull` drop 処理、`result.mbt:171` 付近)
- commit `333cbf7be8` (transparent-kv 修正)

## 受け入れ条件

- [ ] 当事者セッションで `build_result` の SCALAR 昇格判定を「兄弟セル
      存在 heuristic」から「`[]` 要素再帰の内側かどうか」を明示的に伝播する
      構造的判定に置き換えるか、裏取りの上で採否を判断する
- [ ] 採用する場合: 上記の再現構成 (透過要素のみ発火 + 非透過兄弟が
      preset default なし) を spec 側 fixture (transparent-kv 系) に追加し、
      期待結果 `{}` で通ることを確認する
- [ ] 見送る場合: 見送り理由 (優先度 / コスト判断) を明記する

## TODO

<!-- wip 時のみ -->
