---
title: build_result の ACCUMULATE fold が Update / Default op を解釈しない (実装未対応)
status: resolved
category: task
created: 2026-07-09T21:38:57+09:00
last_read: 2026-07-10T10:41:00+09:00
open_entered: 2026-07-09T21:38:57+09:00
wip_entered: 2026-07-10T03:37:33+09:00
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-10T04:55:12+09:00
discard_reason:
pending_reason:
close_reason: ["implemented:commit b8967505ae0b05965f9b00807320e4e75ab22705 (fix(resolve): accum セルの cell 操作 op 解釈とラダー fall-through)、push 済み CI green (run 29045866863)","done:ACCUMULATE fold の Update op → 静的 definition-error (DInvalidRange) に裁定変更。DR-077 §2 ファミリ + min>1 前例からの導出 (accum 宣言・transform とも静的に既知のため実行時まで遅延しない)。alias long_override 経由・count×multiple (update 糖衣) のすり抜けも codex レビュー検出を受けて静的検査でカバー、Update binding 全生成源 (long DSL / count 糖衣 / TCount short) を逆引き確認済み","done:Default op → [] + committed=true (ラダー非開放) で fold 解釈。宣言 default 配列の意味論は未規定と判明、spec issue multiple-declared-default-semantics に切り出し (kawaz 裁定待ち)","done:Update 適用結果の filters (段5)→post_filters (段7) 通過、および型不一致の実行時 Err は update が静的に塞がれたため非該当化 (受け入れ条件から除外)","done:spec fixture default-cell-ops (2 case) / filters-cell-ops empty case / unset-env-fallback (3 case) 追加 (spec commit 28fa57c4eb87127be3f42ca0c6d43b59df1e7291)。accum×update の fixture のみ definition_error format 未確定 (DR-065 予約) のため spec issue definition-error-fixture-format に切り出し (kawaz 裁定待ち)、wbtest で pin 済み","done:追記1 (accum×unset×下位値源の source タグ) は ladder fall-through 実装で解消、unset 後に env が値を供給する場合 sources=env が正しく出る","done:追記2 (Empty fixture / Default op の filters 疑義) は Empty fixture 追加で解消、filters 疑義は DESIGN §14.3 確定 (design-6-2 close) で解消済み","note:sources=default (op=default) は DR-031 明文との既存矛盾が発覚、既存 scalar pin (unset-ladder.json) と一貫の現状維持とし spec issue default-op-source-tag-contradiction で kawaz 裁定待ち","done:conformance decoded=152/ran_cases=388/skipped=0/mismatches=0、moon test 174 本全 pass"]
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
