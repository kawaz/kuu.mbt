---
title: accum セルの filters(each) が非 Set 効果 (Default/Unset/Update) の placeholder 値にも走り得る
status: open
category: design
created: 2026-07-09T17:53:58+09:00
last_read:
open_entered: 2026-07-09T17:53:58+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: codex (gpt-5.5) による accum 配線レビュー (2026-07-09、対象 d52143a7..56275676) の観点 1 指摘
---

# accum セルの filters(each) が非 Set 効果 (Default/Unset/Update) の placeholder 値にも走り得る

## 概要

accum 配線 (commit c976da76) で `resolve_entity_raw` の CLI 座席は accum セルの同名 Binding を op 未解釈のまま温存して返すが、後段の `apply_entity_filters` は Empty 以外の全 op の Binding に `e.filters` を適用する。Default/Unset/Update は operand なしまたは後段 fold 前提の効果で placeholder 値を持つため、accum + filters + これら効果の組合せで placeholder に filter が走り、誤 reject や無意味な transform が起き得る。

## 背景

codex レビュー (2026-07-09) の指摘。実測は未確認 — 該当する fixture が存在しない未検証領域 (accum × filters × Default/Unset/Update の組合せを踏む fixture が現状 spec に無い)。

「filters(each、DR-009 段 5) の適用対象は実値 piece = Set operand のみ」という裁定が導出候補 (Default/Unset は cell 全体への操作で piece ではない。Empty の既存 skip と同じ理由付けに一般化できる)。ただし spec に明文が無いため DR 明確化 or DESIGN 追記が要る。accum × Update は DR-077 的に意味論自体が未定義で、issue `accum-entity-filters-wiring` の残置論点と同根。

## 未裁定の論点 (着手時に spec 裁定)

- [ ] filters(each) の適用対象を「Set operand のみ」に限定する裁定を DR 明確化 or DESIGN 追記として確定する
- [ ] accum × Update の意味論自体 (DR-077 関連、issue `accum-entity-filters-wiring` の残置論点) を先に裁定する必要があるか

## 受け入れ条件

- [ ] 未裁定の論点が裁定される (kawaz 確認または一次資料からの導出)
- [ ] `apply_entity_filters` の適用条件が op ベース (Set のみ、または裁定に従う条件) に修正される
- [ ] spec 側に accum × 非 Set 効果 (Default/Unset/Update) 混在の conformance fixture が追加され、placeholder への誤適用が再現・回帰防止される

## 2026-07-09 具体ケースと実測 (kawaz 依頼)

**定義** (wire 形):
```json
{"name": "ports", "type": "number", "long": [":set", "reset-ports:unset"],
 "multiple": "append", "filters": ["in_range:1:100"]}
```

**argv**: `--ports 5 --reset-ports` (5 を積んだ後にリセット操作)

**現実装の実測** (resolve_scope への直接 probe、cli 列 = [Set(VNum 5), Unset(placeholder VBool(false))]):
```
Err kind=filter pos=2 reason=filter_rejected msg=in_range requires a number value
```
= **リセット操作をしただけで全体 failure になる誤動作**。Unset 効果 Binding の placeholder
値 VBool(false) (eval.mbt mk_eff: 「The operand is a placeholder — these ops carry no operand」)
に number 用 filter in_range が適用されるため。

**scalar (accum なし) では起きない**: scalar の CLI 座席 fold は Unset を「セル開放」として
解釈し、Unset binding 自体は filters に届かない。accum 分岐 (commit c976da76) が
「op 未解釈で温存」するため accum × filters で初めて露出した (codex レビューの指摘どおり)。

**推奨対処**: apply_entity_filters の filters(each) 適用条件を「op が Set (値を運ぶ piece)」に
限定する — Unset/Default/Empty/Update は cell への操作であって piece ではない (Empty の既存
skip の一般化)。期待挙動: `--ports 5 --reset-ports` は cell 開放 (accum × unset の畳み意味論
は build_result 側の既存 fold に従う) で、filter は 5 にのみ適用される。
