---
title: build_result の ACCUMULATE fold が Update / Default op を解釈しない (実装未対応)
status: wip
category: task
created: 2026-07-09T21:38:57+09:00
last_read:
open_entered: 2026-07-09T21:38:57+09:00
wip_entered: 2026-07-10T03:37:33+09:00
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

# build_result の ACCUMULATE fold が Update / Default op を解釈しない (実装未対応)

## 概要

`build_result` の ACCUMULATE 分岐 (`resolve.mbt` L354 付近、段 6 accumulator fold) は
Empty (クリア) と Unset (クリア + uncommitted 化 → sources=default、issue
`accum-filters-non-set-op-semantics` のサイクルで対応) を解釈するが、Update / Default
op は未解釈で placeholder 値 (`VBool(false)`) が累積配列に混入する。

- **Update**: old (その時点の累積状態) に transform を適用して書く (DR-077 §1 +
  DR-045/015 の合成で意味論は既に決まっている — 「未定義」ではなく実装未対応)。
  transform の型 (`T => T`) と累積状態 (`T[]`) の不一致は実行時 Err で自然に決まる。
  update 適用結果は filters (段 5) → post_filters (段 7) を通る (DR-077 §1
  「old → transform → filters → cell」、PIPELINE §3.2)
- **Default**: 明示の default 選択 (committed=true) — accum セルでは default 値
  ([] または宣言 default) へ戻す

## 背景

issue `accum-filters-non-set-op-semantics` の実装中 (2026-07-09) に impl-prefilters
worker が段 6 の op 未解釈として確認。同 issue は段 5 (filters 適用条件) + Unset fold
のみをスコープとし、Update/Default fold は本 issue に切り出した。

## 受け入れ条件

- [ ] ACCUMULATE fold で Update op が old + transform で正しく処理される
- [ ] ACCUMULATE fold で Default op が明示 default (committed=true) として処理される
- [ ] Update 適用結果が filters (段5) → post_filters (段7) を通る
- [ ] transform の型不一致が実行時 Err として自然に検出される
- [ ] spec 側に accum × update / accum × default 発火の conformance fixture が整備されている

## TODO

<!-- wip 時のみ -->

- [ ] spec 側の conformance fixture を先行整備 (発火の綴り・old の初期値・型不一致 Err の輪郭)
- [ ] 段 7 (累積後 post_filters、issue `accum-post-filters-stage7`) と実装箇所が近いため同時着手を検討

## 2026-07-09 追記: accum × unset × 下位値源 (env/config) の source タグも本 issue の射程

Unset fold 対応 (issue accum-filters-non-set-op-semantics のサイクル) で harness の
proj_sources は「accum セルの Unset binding → source タグを default に固定」する実装に
なった。これは下位値源を持たない definition (fixture filters-cell-ops.json) では正しいが、
**unset 後に env / config 席が値を供給するケースではラダー再解決をしていないため誤タグに
なる** (DR-045: unset はラダーを開放し後段が上書き可 → source は env 等になるべき)。

accum セルの env/config 席供給自体に未実装 (issue env-separator-split-gap / 
config-string-pieceprocessor-gap) があり、当該組合せは fixture の無い未検証領域。
本 issue の fold op 解釈の完全化と同時に、accum × unset × 下位値源の ladder 統合 +
fixture 追加を扱うこと。

## 2026-07-09 追記: coverage gap (codex レビュー指摘) も本 issue で拾う

- `Empty` × accum × `filters` の conformance fixture が無い (Unset のみ)。Empty は fold の
  クリア対応済みなので fixture は今でも書ける — sources=cli (committed) と Unset の
  sources=default の対比が輪郭価値
- `Default` op: scalar 実装は :default 発火時に default 値を mkb で Set 化して `filters` に
  通している一方、DESIGN §8.3 (精密化後) は「発火は operand を運ばない → 適用対象の piece が
  生じない」+「書き戻される default 席の値の chain 通過は値源席の規定 (DR-049/050) の管轄」。
  default 席の値が `filters` を通るべきかは DR-050 の post_filters ラベル曖昧性
  (issue design-6-2-piece-post-label-collision) の解消とセットで確定させ、scalar 実装の
  現挙動と突き合わせること
