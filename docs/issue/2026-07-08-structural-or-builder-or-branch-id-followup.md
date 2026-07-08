---
title: structural-or builder と or-branch-id の未実装追跡 (installer.mbt 移植で意図的 skip 凍結)
status: open
category: task
created: 2026-07-08T00:00:22+09:00
last_read:
open_entered: 2026-07-08T00:00:22+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: slice (kawaz/kuu.mbt/slice)
---

# structural-or builder と or-branch-id の未実装追跡 (installer.mbt 移植で意図的 skip 凍結)

## 概要

installer.mbt 移植 (commit d70921d2) で slice 凍結 issue を棚卸しした際、
以下 2 件を意図的に未実装のまま残した。いずれも slice 単体のバグ修正では
閉じず、wire form / spec 側の新規判断が必要なため、spec リポ側でも追跡する。

1. **structural-or builder 未実装**
   (slice `docs/issue/2026-07-06-structural-or-builder-missing.md`):
   flat `ElemDef` から `Or([Seq([typed cells]), ...])` (枝ごとに別の named
   cell を束縛する構造 or) を組む builder が slice に無い。engine 側の
   Node ADT (Or/Seq/NumArg) は形自体をサポート済みだが、flat-ElemDef →
   structural-or の lowering 経路が欠けている。path-search 系の蒸留
   fixture 3 本 (`variable-arity-ambiguous`,
   `held-errors-distinct-depth`, `held-errors-same-depth`) が
   `expected_skips()` に凍結されたまま。**wire form への反映方針と、
   構造 or を定義側でどう表現させるかの新規 DR 判断が必要**。

2. **or-branch-id (匿名 or 枝への requires 宣言) 未対応**
   (slice `docs/issue/2026-07-06-or-branch-id-attribution.md`): 値依存制約
   (DR-055 §1) を anonymous exact 枝 (`{"exact":"json","id":"fmt_json",
   "requires":["schema"]}` のような枝) に宣言した場合、制約違反の
   `element` が枝 id (`fmt_json`) でなく親 name (`format`) に帰属してしまう。
   `ElemDef` が DR-052 の露出直交 id を匿名 exact 枝に持たせる場所を
   持たないのが原因。`known_divergences()` に既知 gap 2 件
   (`constraints-parse/default-interaction.json::case#3`,
   `constraints-parse/requires.json::case#4`) が凍結済み。**ElemDef への
   branch_id 軸追加が必要かどうか、spec 側で採否を判断する必要がある**。

いずれも conformance 実食 (Task 5 想定) で skip / divergence として
loud に可視化される見込み。対応時は spec 側 issue / DR とセットで進める。

## 背景

installer.mbt 移植は slice 側の実装漏れの棚卸しも兼ねていたが、上記 2 件は
「slice 単体で直せるバグ」ではなく「wire form / DR レベルの仕様判断待ち」の
性質を持つため、slice 側 issue を凍結したまま spec 側 (本リポ) にも追跡用の
issue を残す。

参照:
- slice `docs/issue/2026-07-06-structural-or-builder-missing.md`
- slice `docs/issue/2026-07-06-or-branch-id-attribution.md`
- slice `docs/issue/2026-07-06-idx-repeat-held-error-swallowed.md` (structural-or
  builder issue から関連付けられている nested-group positional skip 系)
- `docs/decisions/DR-052-export-key-unification.md` (lexical name と id の直交性)
- `docs/decisions/DR-055-constraint-vocabulary.md` §1 (値依存制約は値の枝への
  requires 合成で書く)

### あわせて記録: transparent-scalar-promotion-no-sibling (slice issue, 別件)

slice `docs/issue/2026-07-06-transparent-scalar-promotion-no-sibling.md` も
同時に棚卸し対象になったが、こちらは `resolve.mbt` (slice 実装) 側の
`build_result` にある SCALAR 昇格 heuristic (「兄弟セル存在」で kv 文脈を
代理判定) の構造的な置き換え案件で、spec 側の新規判断は不要 (= 判定基準を
「`[]` 要素再帰の内側かどうか」に変えるだけで閉じる想定)。現状は latent bug
(現行 fixture では顕在化しない) につき、slice 側 issue のまま残置。本 issue
のスコープには含めない (= 参照情報として記録のみ)。

## 受け入れ条件

- [ ] structural-or builder: wire form への反映方針を DR 化し、slice が
      それに基づき builder を実装、path-search 系 3 fixture の skip が
      VANISHED として消し込まれる
- [ ] or-branch-id: `ElemDef` への branch_id 軸追加の採否を spec 側で判断し
      (DR 化するか、見送り理由を明記するか)、slice 側 issue に結果を反映する
- [ ] 両件とも、対応が完了 (または明示的に見送り確定) した時点で本 issue を
      close する

## TODO

<!-- wip 時のみ -->

## kawaz 裁定 (2026-07-08) — ElemDef 再設計の設計条件

- **id は意味のある名前である必要がない**。installer 等の展開で生まれるノードの id は user ns と被らない自動生成で十分: 無名派生は `#{seq}`、ユーザ定義 id "xx" からの派生は `xx#{seq}` (`#` は user ns に現れない字なので構造的に衝突しない)。seq はパーサ全体で一意なら何でもよい
- **表示はユーザ起源で組む** (DR-066 の 2026-07-08 改訂 = path/provenance 追加を参照): 何段展開してもユーザ定義 Node に辿り着くので、エラー・補完の外向き表示は「発火時の動的パス + ユーザ起源名」(例 `.color.r`)。自動 id を表示面に出さない
- 実装時に反例を探す観点: 真にユーザ起源が無い合成ノード (installer が足す dd 衛星、DR-076 の `:set:true` 合成綴り) が「最寄りのユーザ要素」に着地するか

