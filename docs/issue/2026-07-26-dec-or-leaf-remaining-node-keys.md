---
title: dec_or_leaf の残余キー同型化の棚卸し (repeat/multiple/optional が最優先、DR-067 §2 直接規定)
status: wip
category: design
created: 2026-07-26T22:23:57+09:00
last_read: 2026-07-28T20:58:00+09:00
open_entered: 2026-07-26T22:23:57+09:00
wip_entered: 2026-07-28T22:12:55+09:00
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

# dec_or_leaf の残余キー同型化の棚卸し (repeat/multiple/optional が最優先、DR-067 §2 直接規定)

## 概要

schema `$defs.node` と `dec_or_leaf` の `allowed_keys` の差分は 2026-07-26 調査で 52 キー →
value/default 実装後も約 49 キー残る。優先度階層に沿って段階的に同型化する。

## 背景

優先度階層 (2026-07-26 調査時点):

- **(高)** `repeat` / `optional` / `multiple` — DR-067 §2 が child 内で合法と直接規定、かつ
  「optional な 2 番目 + fallback」の表現手段がこれが無いと存在しない
- **(中)** `default_fn`、`export_key`、filters 系、`env` — `default_fn` は resolve 相の遅延評価が
  要るため消費 0 literal に落とせず意図的にスコープ外にした (decode だけ通すと silent wrong
  answer になるため現状は明示エラー維持)。`env` は DR-042 により席宣言のみで child でも spec 上
  有効 (long/short の inert とは違う)
- **(低)** ネスト or/seq、表示メタ、ref 等

実装前に各キーの child 位置での意味論を spec と突き合わせること。

## 調査結果 (2026-07-27、survey-child-repeat)

### 拒否面と受け皿の実測

- 5 配置中 4 配置 (or 子 / seq 子 / option 直下 seq / ref template 内) は dec_or_leaf の allowed_keys で拒否。**positional Group 子だけ decode は通るが「通るが効かない」** — 消費構造に効かず (lower_positional の Group head が elem_repeat を通さない)、accum entity だけ root に作られて phantom `x:[]` が漏れる (lowering.mbt:1019-1062 / 1225-1290)
- engine 受け皿は未完成: element_head は repeat/optional/multiple を見ない。off-spine repeat (Many/BoundedTail) は greedy/lazy 選好を適用しない縮退実装でコメント自身が「lowering never generates this shape today」と明記 — DR-043 の完全経路選好を満たさない
- template は decode 時に ElementDef→Node 即変換で Map[String,Node] 格納、repeat/multiple の entity metadata が失われる
- 内部生成 id `name#cons` は child scope で generated-generated collision の懸念 (scope-qualified 化が必要)

### 結果形は spec から導出可能

child repeat の結果は child cell が配列 (DESIGN §5.1 + §6.1/DR-044)、親 seq はそれを値として保持 (自動 flatten 規定なし)。repeat+multiple の T[][] は ref-repeat-rows-nested.json が pin 済み

### 裁定事項

- **CHILDDEF-Q1 (spec QUESTIONS.md に起票済み)**: child の default: 綴りは const 同義のままか、value:=const / default:=充填に位置非依存で分けるか。optional+default の fallback 表現の成立可否がこれで決まる
- nested repeat の greedy/lazy CPS 設計、template metadata 表現は実装設計判断 (裁定不要だが規模大)

### 規模見積り

decode 開放だけは小だが silent wrong answer を増やすので単独 land 不可。end-to-end は中〜大 (wire decoder / installer ABI (DecodeCtx に StructuralChild 追加) / lowering / eval / result・entity path / template registry の 6 面、実装 300-600 行 + fixture/wbtest 15-30 case)。Phase 分割: 1) 裁定+fixture 先行 → 2) decode/installer ctx → 3) nested repeat lowering/eval → 4) nested accum/result address → 5) 回帰

## 受け入れ条件

- [ ] repeat/optional/multiple が child 位置で decode を通過する (DR-067 §2 準拠)
- [ ] 中優先度キー (default_fn の扱い方針含む、export_key、filters、env) の child 位置意味論が spec 突き合わせで確定する
- [ ] 低優先度キーの対応要否が判断される (対応しないなら理由を明記)

## TODO

Phase 1 (裁定 + fixture 先行) 完了 (2026-07-28)。spec 側に child repeat/optional/multiple の
fixture 11 file / 25 case を land (spec main=198bce86)、kuu.mbt は expected_skips 8 +
known_divergences 5 で凍結 (main=650f2875)、kuu-cli は conformance 凍結 fail 台帳 23 entry で
凍結 (main=d821936c)。repeat×default の相互作用は spec 側 QUESTIONS.md REPDEF-Q1 として
裁定待ち (Phase 2 をブロックしない)。残: Phase 2 (decode/installer ctx) → 3 (nested repeat
lowering/eval) → 4 (nested accum/result address) → 5 (回帰・台帳掃除)。

Phase 2-5 完了 (2026-07-29、main b0ff53ad〜e159922c の 6 commit)。受け入れ条件 1
(repeat/optional/multiple の child decode 通過) 充足 — decode/lowering/eval/resolve の
end-to-end 実装、conformance 383 file / 857 case 全 pass・skip/divergence 台帳空、kuu-cli も
708/708 で追随済み (lockstep: spec 117b24df / kuu.mbt e159922c / kuu-cli 05660182、3 リポ CI
green)。残: 受け入れ条件 2 (中優先度キー default_fn / export_key / filters / env の child 位置
意味論の spec 突き合わせ) と 3 (低優先度キーの要否判断)。中優先度キーは decode を意図的に
開けていない (dec_or_leaf は installer 語彙駆動化済みなので、意味論確定後は各 installer の
StructuralChild アーム追加で開けられる)。

## 追記 (2026-08-16): exact の structural seq/or leaf 拒否 (B6, kuu.mbt 全コードレビュー由来)

統合レビュー報告 (kuu.mbt 全コードレビュー 2026-08-16、領域別8並列) にて、structural seq/or leaf の `exact` 拒否が本 issue の対象範囲の一部として明示された。

- 場所: src/kuu/wire_decode.mbt:1922
- structural seq/or leaf が `exact` を拒否する (positionals は受理している) — DR-067 §2 違反
- 本 issue が扱う allowed_keys 残余キー同型化の一部と部分重複するが、`exact` は現状の優先度階層 (高: repeat/optional/multiple、中: default_fn/export_key/filters/env、低: ネストor/seq・表示メタ・ref等) に明示列挙されていない。**優先度付けの見直しが必要** — `exact` は他の受理面 (positionals) と非対称なので、次フェーズの棚卸しに含めること。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)
