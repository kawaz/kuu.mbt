# FiringRecord — cell fn 多重実行の一本化 (DR-114 §6.1「発火時に 1 回」)

> 対象: spec DR-114 §6.1/§7、DR-038 (経路 identity)、DR-045 (効果純データ)、DR-081 §2、
> DR-127 §4.2/§6、DR-131。設計正本:
> `docs/findings/2026-08-02-w2-9-observation-finish.md` の「実行一本化の設計」節、
> issue `2026-08-02-cell-fn-multi-fire-unify` (本窓で close)。
> 実装: `src/internal/fold/firing_record.mbt` (FiringRecord / FiringLedger / FiringCursor /
> FiringDeliveries、新規) / `src/internal/engine/branch_fold.mbt` (枝内実行の record 化 +
> 裁定後 fold `branch_fold_plain_records`) / `src/internal/engine/eval.mbt` (`parse_tree` の
> `ladder?` / `firings?`) / `src/kuu/resolve.mbt` (`parse_fold_ladder`、record 消費 gate、
> resolve 連鎖の `firings?` 配線) / `src/kuu/front_door.mbt` (射影の record 消費) /
> `src/kuu/facade_types.mbt` (payload の side payload field)。
> pin: `src/kuu/firing_record_wbtest.mbt` (5 本、新規)。

## 判明した事実

- **cell fn は発火 1 件につき 1 回実行になった** (DR-114 §6.1)。実行体は「勝ち枝確定後の
  1 回の fold」に集約: 値残余セル分は DR-127 §4.2 の枝ローカル fold の**枝内実行結果を
  勝ち枝からそのまま引き継ぎ** (再実行しない)、値残余の無い Invoke セルは裁定後の 1 回の
  fold (`branch_fold_plain_records`) が実行する。旧 3 実行者のうち effects 射影
  (`projected_effect`) と resolve 相 CLI seat (`resolve_entity_raw`) は FiringRecord の
  **消費者**になった。実測 (カウンタ fn): parse → effects → resolve → output の全経路で
  実行回数 = 発火数 (旧構造は発火数 × 3)。
- **FiringRecord は Binding / Outcome の Eq に参加しない side payload** (W2-9 監査 M2 の設計
  制約 (a) を採用)。record = { `transition` (共有 fold の実行結果) / `old_used` (実行時の
  `ctx.old`) / `old_consulted` / `resolved_residual` (DR-127 §6 の解決済み観測アドレス片) }。
  効果列との対応は「セル (scope+key) ごとの record 対象 binding (`records_firing` = Invoke
  または値残余付き) の出現順」で取り、binding の綴り (op / operand、DR-045) と裁定前 dedup
  (DR-038 の `Array[Binding]` 構造等価) は完全不変。配達は `parse_tree` の `firings?`
  (経路 binds との対、requires filter の経路選別後も構造等価で引き直す) → facade の
  `ParsedBindings` / `Interpretation` / `ResolvedBindings` の priv field。
- **resolve 相の消費は「自席で計算した old と record の `old_used` の一致」を gate にする**。
  parse と resolve に同じ `ValueSources` を渡す既存契約 (facade doc「A provider must return
  the same value for the same key throughout both phases」) の下では常に一致して消費される。
  不一致 (契約違反 = 両相で別の値源、または ladder closure の縮退) は従来どおり再実行 —
  未供給・不整合経路の現行挙動を値比較が構造的に保つ (taint 簿記は不要)。effects 射影は
  gate なしの無条件消費 (観測は best-effort、record の実行こそが「発火時の 1 回」の実体)。
- **危険域 (value_residual セル × 非決定 Value fn) が閉じた**: 枝選別 (DR-127 §4.2) に使った
  値と resolve が座へ書く値が同一の record 由来になる。wbtest (呼ぶたびに値が変わる fn) で
  fold 値 = effects operand = result 座値の一致と実行 1 回を pin。
- **W2-4 findings §3.2 の残差 (明示 `default` 効果後の old の乖離) が閉じた**: `parse()` の
  `sources?` が parse 相 fold の ladder closure (`parse_fold_ladder` — config_file セルの
  path 解決込みで `resolve_ladder_below_cli` と同素材) に効くため、`default` 効果の落ち先が
  resolve 相と同じ full ladder になる。env / config 供給の両形を wbtest で pin
  (`--reset-n --n` + env N=5 → effects `default, set(6)` / result 6)。`parse()` に値源を
  渡さない呼び出しは従来どおり宣言 default 止まりの観測 + resolve 相の自力解決 (後方互換、
  conformance 904/0 不変で確認)。
- **record が無い発火は resolve 相の残余分岐が従来どおり実行する** (最終防衛線の保持、設計 5):
  fold の保守的スキップ (宣言を特定できない / 候補が食い違うセル)、accum セル、engine 直呼び
  (`parse_tree` を `firings` なしで呼ぶ経路)、CLI 以外の供給経路。
- **公開 API 変更 (mbti diff)**: `@fold` に FiringRecord / FiringLedger / FiringCursor /
  FiringDeliveries / `records_firing` / `firing_cell_key` を新設、`@engine.parse_tree` に
  optional `ladder?` / `firings?` を追加。**kuu facade (`src/kuu/pkg.generated.mbti`) の公開面は
  不変** — `parse` / `resolve` のシグネチャはそのまま、既存 `sources?` が Supplies を兼ねる
  (新しい Supplies 型は導入していない。issue の「供給付きの形を足す」は既存 `sources?` の
  意味論拡張 — parse に渡した値源が parse 相 fold にも効く — で満たした)。

## 実用的な示唆 / 残余 (現在形)

- 第三者 resident が uuid / 乱数 / 時刻等の非決定 Value fn を登録しても、effects / result /
  枝選別の観測値は一致する (fn の実行は発火ごとに 1 回)。
- `parse` と `resolve` に別の値源を渡す契約違反では record が消費されず fn が 2 回走る
  (wbtest で挙動 pin 済み — result は従来どおり resolve 側の値源で決まる)。
- ladder closure の scope 降下は command path のみ対応。structural / index 付き scope で
  config_file セルの動的 path が絡む形は宣言 default へ縮退する (old 不一致 gate が守るため
  観測は現行と同じ、実行回数だけ従来どおり 2 回になる)。必要になれば縮退範囲を狭められる。

## 検証 (2026-08-02 実測)

- `moon test` = **721 tests / 721 passed** (新設 wbtest 5 本込み)、conformance
  `decoded=400 ran_cases=904 skipped=0 mismatches=0`。known_divergences / expected_skips
  両台帳は空のまま。既存 716 tests・904 cases は完全不変。
- `moon check --deny-warn` green、`moon fmt` / `moon info` 適用済み。
- 新設 wbtest 5 本: 値残余なしセルの発火 1 回性 + 非決定 fn の 3 経路一致 / 値残余セルの
  枝内実行引き継ぎ (fold 値と座値の同一) / env 供給が default 後の old に効く / config 供給が
  default 後の old に効く / 値源不一致時は record 不消費 (再実行 = 現行挙動の防衛線)。

## 関連

- spec `docs/decisions/DR-114-universal-fn-integration.md` §6.1 / §7
- spec `docs/decisions/DR-038` (経路 identity) / `DR-045` (効果純データ) / `DR-081` §2 /
  `DR-127-link-fixed-path-dsl.md` §4.2 / §6 / `DR-131`
- `docs/findings/2026-08-02-w2-9-observation-finish.md` 「実行一本化の設計」(設計正本)
- `docs/findings/2026-08-02-w2-8-branch-local-fold.md` (枝ローカル fold = 引き継ぎ元)
- `docs/findings/2026-08-02-w2-4-fold-unification.md` §3.2 (本窓で閉じた残差の出所)
