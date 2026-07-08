# complete() API 実装と conformance divergence Batch-1 統合

セッション: complete() (Task #7) の実装完遂と、divergence 修正 Batch-1 (bool/inf 10 件) の統合。main は `b0599d66` → `68157dbc` (6 commits)。

## 成果

### complete() API (MDR-002 §2.4 / DR-060)

- **phase 1 — Ctx 化** (`68128396`, opus47-worker 実装・監査済み): walk 全関数の `(toks, defs)` を `Ctx { toks, defs, mode }` に集約。挙動不変
- **phase 2 — EvalMode 意味論 + complete() 本体** (`6bddefa1`): 設計どおり「walk へ complete モードを通す」形。分岐点は
  1. 境界トリガサイト (Exact / CmdSat / DdSat / NativeMatch / cluster tail) → 沈黙 Reject でなく `Pending` exact 候補
  2. spine / consume_head の枯渇 Held → `Pending` 値候補
  3. 取り分選好の刈り込み無効 (stop/more 両保持)
  - 設計時の 3 点目「drop_optional_missing 無効化」は **不要と判明** — 2 により complete モードでは missing_operand Held 自体が生成されない
- `complete(root, before, defs?, after?)` は outcome.mbt の Pending dedup 収集 1 本。after 整合フィルタ (DR-060 §2) は WordEnd exact のみ検査 (値候補 / Cont 綴りはユーザ入力を発明できないため素通し = v1 制限)
- **codex レビュー (High 2 件、`233656f7` で修正)**: spine `Many` (scope_consume_rep) と `IdxRepeat` (idx_one) が repeat 継続点で Pending を握り潰していた。ハマり所: repeat 続き候補のテストを Ref repeat (consume_head 経由) だけで固定していて、Many spine / IdxRepeat という**別経路の同型パターン**を見落とした。修正は REVIEW-C1/C2 として complete_wbtest.mbt に凍結
- MDR-002 の TODO 節を確定内容に改訂済み

### divergence Batch-1 (`a43bdbb2`, sonnet5-worker-high 実装 + main 統合)

- diverge **17 → 7**。bool-canonical 8 件 + number-inf-nan 2 件
- **Ty に TBool 新設** (TFlag=presence-only / TBool=値型 bool、variant 無し時のみ eq-split 登録)。根拠: 一律 TFlag に eq-split を足すと lowering golden 4 件が regress = flag/bool の区別が仕様上必要 (DR-074 §3)
- **Ty に TFloat + Node に FloatArg 新設** (float = number + inf、DR-074 §1/§7)。`parse_float` = `parse_number` 委譲 + `scan_inf` (2 語 ci + 符号合成)。number 側は inf 拒否のまま
- 残 7 件: constraints-parse×2 (DR-055)、export-key/collision (E)、path-search×3 (D、DR-043 §71 未決着)、int-value-space (C、DR-075)

## ハマり所と教訓

1. **「TNum = float」という思い込みで誤指示**: worker の TFloat 新設を設計スコープ外と誤断して中止指示を出した。DR-074 §1 は number (inf 拒否) と float (= number + inf) を**別型**として規定しており worker が正しかった。→ 委譲先の設計判断を却下する前に spec を裏取りする
2. **ws 競合事故 (half-revert 混入)**: worker が中止指示 (後に撤回) を作業完了報告の**後**に遅延処理して revert を開始、こちらの `jj commit` と競合し node.mbt だけ TFloat が revert された状態がコミットに混入。main への rebase 時にコンパイルエラーで発覚し復元。→ **idle 表示でも未処理の受信指示が残る worker は潜在 writer**。ws でコミットする前に最終指示への ack を取る
3. **jj rebase の conflict 解決手順**: `jj rebase -r <rev> -d <dest>` → `jj new <rev>` → マーカー解決 → `jj squash`。matcher/eval の Ctx 化と divfix の TFloat 追加が重なった 2 ファイルのみ手動解決
4. **`just push` の fmt gate**: moon fmt 未追従だと fmt-check (ci 経由) で push が止まる。実装コミット前に `moon fmt` を習慣化
5. **`just watch` は Monitor から直接使えない**: watch-workflow.sh が PATH 外。gh-monitor hook が示すフルパスコマンドで起動する

## 起票

- kuu.mbt `docs/issue/2026-07-08-floatarg-spine-arm-gap.md`: FloatArg が spine 系 4 関数 (scope_consume / consume_head / scope_consume_rep / head_elem_names_into) に固有アームを持たず、先食い抑制と DR-065 §3 名前集合から漏れる疑い (静的読解、未検証)
- spec 側 `docs/issue/2026-07-08-variant-bool-eq-split-value.md`: variant 持ち bool の eq-split 値形の可否 (Batch-1 の仮置きの追跡)

## 次

- Batch-2: E (export collision → Ambiguous + DR-073 claimants) + C (int-value-space、DR-075 int_round)
- D (path-search 3 件) は DR-043 §71 の向き決着待ち、F (structural-or 2 skip) は ElemDef 再設計と併合

## 追記 (同日後半): Batch-2 以降で divergence 20→3 到達

- **Batch-2** (`5161f0a` 系列, opus47): DR-073 claimants (AmbInterp 化 + promote_collision_ambiguous) と DR-075 IntArg (値空間判定、spine 4 経路 + complete モードミラー) で 7→5
- **constraints-parse** (`5161f0a`, opus47): CRequiresIf を (entity, branch_id, value, targets) に拡張。committed 判定は親 entity、error.element は宣言元の値枝 id — DR-055 §1 + DR-052 直交の非対称。5→3
- **FloatArg spine アーム** (`62f5d9a`, sonnet5): issue 起票 → RED first (4 関数それぞれの実誤動作を個別 FAIL 確認) → 対称アーム追加。issue は resolved → archive
- **Int64 silent wrap** (`b07bec0`, sonnet5): "1e300"→Ok(0) に加え "9223372036854775808"→Ok(Int64::MIN) の符号反転を発見・修正。reason は provisional `int_out_of_range` (not_a_bool 前例)、語彙確定は spec issue `int-value-domain-out-of-range` で追跡
- **残 3 件 = path-search/ambiguous-receptacles のみ** (DR-043 §71 の取り分方向が spec 未決着。実装側の手は尽きた)

### 追加のハマり所

- **jj 並行 ws の divergent change**: main ws と divfix ws の操作が交錯すると同一 change-id が /0 (pushed) と /1 (ローカル) に分裂し、push gate が「(ambiguous)」で止まる。対処: `jj diff --from X/1 --to X/0` で内容一致を確認 → pushed 側 (immutable ◆) に rebase し直し → /1 系列を abandon。**根本回避は「ws を跨ぐ操作の直前に jj log で相手 ws の @ 位置を確認する」**
- 新起票 (実装監査からの発見): `export-key-collision-identity-exposure-gap` (identity 露出 vs mapped key の衝突未検出、spec 精読要)
