---
title: Pending→ParseError (missing_operand) 変換経路の path が Held 直接経路と非対称 (Cand.link escape の漏れ出し疑い)
status: resolved
category: bug
created: 2026-07-15T15:21:24+09:00
last_read:
open_entered: 2026-07-15T15:21:24+09:00
wip_entered: 2026-07-15T15:48:34+09:00
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-15T16:45:55+09:00
discard_reason:
pending_reason:
close_reason: ["dr/DR-066","implemented"]
blocked_by:
origin: audit-held-path-rooted-escape 調査の副次発見 (archive 済み、close_reason の note 参照)
---

# Pending→ParseError (missing_operand) 変換経路の path が Held 直接経路と非対称 (Cand.link escape の漏れ出し疑い)

## 概要

audit-held-path-rooted-escape の調査 (2026-07-15) で実証された派生発見。Pending→ParseError
(missing_operand) 変換経路 (eval.mbt の変換箇所、調査時点で 3634-3639 付近) は Cand.path を
ParseError.path にそのままコピーするが、Cand.path は Cand.link の Rooted-escape を経由した
「宣言元 scope 基準」の値になっていることがある。一方 Held 直接経路は DR-066 §4 (発火時の動的
パス = walk 位置のコピー先 scope 基準) に従う。両者が食い違う (= 同一エラーで path が 2 通り
出る) ことがある。

## 背景

実機実証 (KUU_FIXTURES 注入): global option (number, global:true) を子 command `a` に持つ定義で
`["a","--level"]` (値 starve) → errors 2 件併存:

- `level@2/parse/missing_operand|path=[]` (宣言元基準、Pending 変換経路由来)
- `level@2/parse/missing_operand|path=["a"]` (コピー先基準、Held 経路由来)

DR-066 §4 の「発火時の動的パス」規範に照らすと Pending 変換経路側が設計不整合の疑い —
Cand.link (complete() 専用の内部実装、node.mbt コメントで purely an implementation detail と
明言) が ParseError 生成に漏れ出している副作用の可能性。

## 判明した事実 (2026-07-15、実機実証済み)

### (1) 発生源特定

- 1 件目 `path=[]` は `step_greedy` catch-all (eval.mbt:1703-1725) が
  `Rooted(inner,depth=1)` を off-spine eval 経由で評価し、`Cand.link=1` が
  `nest_cands` (eval.mbt:238) の prepend をスキップした産物
- 2 件目 `path=["a"]` は early-close 後の root 再評価 (`KResumeScope`,
  cont.mbt:113) で root 自身の非 Rooted 宣言 (`link=0`) が独立に Pending
  生成し、正常に prepend されたもの
- `push_error` (eval.mbt:3719) は path 込み全フィールド等価 dedup のため、
  上記 2 件が併存する
- global option 特有の現象 (非 global の command-local option では 1 件のみ、
  実証済み)

### (2) 統括裁定

- `path=["a"]` が DR-066 §4「発火時の動的パス」の規範通り、`path=[]` は
  `Cand.link` (completion 専用の内部機構、node.mbt:701-711 で purely an
  implementation detail と明言) が KTop 変換 (eval.mbt:3603-3619) へ
  漏れ出したことによる規範違反
- 同一 `(element, args_pos, kind, reason)` の 2 件併存は同一失敗の技術的
  重複であり、1 件 (`path=["a"]`) に統合すべき

### (3) 既存影響

- `global:true` を含む fixture 11 件のうち `missing_operand` を含むものは
  ゼロ、既存 pin への影響なし

## 受け入れ条件

- [x] 修正案 A (KTop 変換で `c.link>0` の候補を変換対象から除外) の前提
      「root 再評価が必ず `link=0` の代替候補を供給する」を adversarial
      マトリクス検証する (子 scope に他 greedy entry があり
      `greedy_reads=true` で early-close しないケース等の反例探索)
      → **前提が根本的に崩壊すると判明** (`nest_cands` は CmdSat 境界を
      跨ぐたびに必ず `link` を 1 減算するため、depth 段の境界を全て
      通過すれば必ず `link=0` になる。実機で `c.link` を dump し、KTop
      到達時点の全候補が既に `link=0` であることを確認済み — 「`link>0`
      を除外」は何も除外しない no-op で、誤った `path=[]` の候補は
      `link=0` のまま残ってしまう)
- [x] 前提が成立するなら案 A、反例があれば案 B (`Cand` に発火時の walk 位置
      `path` を分離保持し KTop 変換で使用) で実装する
      → 案 B を実装 (`Cand.fire_path` 新設、`nest_cands` で `link` に
      関わらず無条件 prepend、KTop の missing_operand 変換は `c.path`
      でなく `c.fire_path` を読む)。simple 再現・sibling flag・nested
      depth2 の全反例パターンで 1 件 (正しい path) に収束することを
      wbtest で実機確認
- [x] spec fixture で global option 値 starve の errors 期待
      (`path=["a"]` 1 件) を pin する (ロックステップ、統括側で後続手配)
      → `fixtures/command-scope/global-missing-operand-path.json` (kawaz/kuu)
      に depth 0/1/2 の 3 case で追加、全 case で path 1 件収束を pin 済み
- [x] 既存 test green を維持する (344 → 346、conformance mismatches=0
      skipped=0)

## TODO

- [x] adversarial マトリクス検証で修正案 A/B を確定する (→ 案 B)
- [x] 修正実装 + wbtest 追加 (spec fixture pin は統括側で後続手配)
- [x] 既存 test green 確認
