---
title: parse conformance gap まとめ batch1 (export-key 衝突 / transparent-kv null / 空発火 command scope / global shadow / 二重 repeat 取り分)
status: open
category: bug
created: 2026-07-05T23:54:17+09:00
last_read:
open_entered: 2026-07-05T23:54:17+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (fixtures 実食で顕在化, DESIGN §15.5 / DR-042 / DR-043 / DR-052)
---

# parse conformance gap まとめ batch1

## 概要

kawaz/kuu の fixtures を JSON 直読み conformance runner
(`poc/json_conformance_wbtest.mbt`) で実食した結果、`known_divergences()` に
台帳登録されているが個別 issue になっていない slice 実装 gap を 5 件まとめる。
いずれも **実測 (moon test の diverge 出力) に基づくフラグ + 一次資料の提示**であり、
真因の特定と是正方針の判断は slice 当事者セッションに委ねる (下記の現象・仮説は
裏取り前提、鵜呑みにしない)。

各 gap は現行 `known_divergences()` のコメント配下に登録済みで、台帳と本 issue は
相互参照の関係にある (台帳 = 「今どこが乖離しているか」の機械照合、本 issue =
「なぜ・どう直すか」の追跡)。

## gap 一覧

### 1. export-key 衝突が Success になる

- **現象**: `export-key/collision.json::case#1` — 2 要素が同一 export_key `x` を
  共有。fixture は衝突を **ambiguous** outcome とするが、slice は
  `ok{a=true,b=true}` (Success) を返す。
- **一次資料**: `kawaz/kuu` の DESIGN §15.5 (露出キーの一意性検査は実行時、同一
  入力で両方が露出して衝突した時のみ ambiguous エラー)。
- **仮説 (要裏取り)**: 衝突検査が Outcome 判定と別経路にあり、Outcome に surface
  していない。slice 第 12 弾 note 3 の「衝突検査が Outcome と別経路」の実装課題に
  対応。

### 2. transparent-kv の sole-binding で EkNull 値が scalar 昇格する

- **現象**: `export-key/transparent-kv.json::case#2` — result `got=true`
  `want={keep=false}`。唯一の実バインディングである EkNull 値が drop されず
  scalar (`true`) に昇格している。
- **一次資料**: `kawaz/kuu` の DR-052 §2 (kv 文脈では EkNull は drop が仕様)。
- **仮説 (要裏取り)**: slice の phase22 が co-fired-sibling ケースのみカバーし、
  sole-binding (単独バインディング) ケースの drop を実装していない。

### 3. 空発火 command scope が `{}` を描画しない

- **現象**: `variant-effects/effect-order-global.json::case#1` — result
  `got={out=B}` `want={build={},out=B}`。case#2 も同型 (`got={out=A}`
  `want={build={},out=A}`)。link cell のみ発火した command が scope を描画せず、
  空の `build:{}` が欠落する。
- **一次資料**: 台帳コメントは DR-018 (command が発火したら scope を持つ) を引く。
  presence の観点では DR-051/052 (発火した scope は空でも `{}` を持つ) も関わる。
  **どちらが是正の根拠として正なのかは当事者で確認してほしい** (部外観測では
  presence 規約の適用範囲を断定できない)。
- **仮説 (要裏取り)**: 発火判定は通っているが、子を持たない scope の空描画パスが
  無い。

### 4. global shadow subtree の値が root にも出る

- **現象**: `command-scope/shadowing-subtree.json::case#1` — result
  `got={a={averb=false,b={}},averb=true,rverb=false}`
  `want={a={averb=true,b={}},rverb=false}`。shadow された global の値が子 scope
  配下にネストするだけでなく root にも重複出現している (`averb` が root と `a`
  配下の両方に、しかも値が食い違う)。
- **一次資料**: `kawaz/kuu` の DR-042 (global shadow は子配置のみ、root には出さない)。
- **仮説 (要裏取り)**: shadow 同期が root エントリを消さずに子へコピーしている
  (shadow sync の二重書き)。

### 5. 二重 receptacle の取り分 (DR-043 greedy 未実装)

- **現象**: `path-search/ambiguous-receptacles.json` の 3 case。隣接する 2 つの
  min:0 repeat positional (`xs*`, `ys*`)。fixture は DR-043 取り分選好で是正済み
  (greedy 既定 = 左最長で success 1 本)。slice の phase10 model の実挙動:
  - case#1 (argv `[]`) / case#2 (argv `[z]`): `fail:no complete parse` — min:0
    repeat が空のまま許容されず、0/1 トークンで完全経路が立たない。
  - case#3 (argv `[a, b]`): `{xs=[a],ys=[b]}` の**均等分割**を返す (want は greedy
    最長 `{xs=[a,b],ys=[]}`)。
- **一次資料**: `kawaz/kuu` の DR-043「取り分の選好」/ LOWERING.md §B.8。
- **仮説 (要裏取り)**: slice が隣接 min:0 repeat の DR-043 取り分選好を未実装で、
  (a) min:0 の空許容が効かず、(b) 取り分が greedy でなく均等分割になっている。
- **注意 (上流未決着)**: fixture の greedy の**向き** (左最長 vs 右最長) は kuu 側
  DR-043「未決着 — 取り分の向き」で未決着。向きが反転すれば case#3 の want は
  `{xs=[],ys=[a,b]}` 側に反転するが、slice が均等分割・空非許容である限り gap
  自体は残る。slice を DR-043 準拠にする際、向きの上流決着を待つか暫定で左最長に
  合わせるかは当事者判断。

## 受け入れ条件

- [ ] 各 gap の仮説を裏取りし、真因を特定 (推測で塞がない)
- [ ] 是正 or 意図的据え置きの判断を各 gap ごとに下し、`known_divergences()` の
      該当エントリを解消 or コメント更新する
- [ ] gap 5 は上流 DR-043「向き」の決着状況を確認した上で方針を決める
- [ ] 各是正の裏取り結果を本 issue または関連 DR/journal に残す
