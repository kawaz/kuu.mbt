# W2-7 vivify + 座への操作語彙 — routing 活性化・時系列・null 補形の設計判断

> 対象: spec DR-127 §3 / §3.2 / §4 / §4.1、DR-130 §4.1 / §5、DR-131 §2b / §7、
> kuu.mbt 計画 `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 W2-7 行。
> 実装: `src/kuu/cell_fold.mbt` (typed 降下) / `src/kuu/resolve.mbt` (残余分岐 + null 補形) /
> `src/kuu/front_door.mbt` (effects 射影 + sources 整合) / `src/internal/engine/lowering.mbt`
> (LinkRoute + parse 差し替え) / `src/abi/value.mbt` (`Binding.value_residual`)。
> pin: `src/kuu/value_seat_wbtest.mbt` (12 本) + `src/kuu/output_contract_wbtest.mbt` (期待値更新)。

## 判明した事実

- **DR-127 §4 の時系列表 5 行は W2-4 の共有 fold の 1 つの口で成立する** — 「部分書き = 非空
  segment 列の `set_at_declared`、parser 産出の丸ごと置換 = 従来どおり座そのものへの set」を
  binding 出現順に適用するだけで、専用の時系列機構は不要だった (計画が最高リスクと見た
  「W2-4 fold との噛み合わせ」は、W2-4 §4 の口の設計がそのまま吸収した)。
- **routing の活性化射程は FieldType 終端 (record フィールド、静的) のみ**。ElementShape
  (array 要素終端) / RuntimeResolved (map/value) は座の存在自体が実行時解決で、裁定前の
  枝ローカル fold (DR-127 §4.2 = W2-8) が持ち主 — W2-7 では従来どおり不活性
  (`residual_route` が gate)。W2-6 findings の「静的合法な entry の実行時不活性」の穴は
  record 分について塞がった。
- **値空間残余は `Binding.value_residual` で運ぶ** (observation とは別フィールド)。
  observation.path はセル空間の消費済み segment (`pair[0]` の位置) を含む観測アドレスで
  あって値残余と一致しない (DR-127 §6) — DR-127 波及節 kuu.mbt 項の「target を
  (cell, path_residual) + 観測アドレスへ拡張」の実装形。`LinkTarget` node と matcher entry
  (Long/Eq/Short) にも同じフィールドが通り、`bindings_through_link` が stamp する。
- **operand のフィールド側 type パース (§3.2) は lowering の型差し替えで実現** — long space
  form / eq-split / short cluster / positional の 4 入口とも、FieldType 終端 entry の
  parse identity を `LinkRoute.parse_ty` (registry 解決済みフィールド type) に差し替える。
  `parse_token_checked` 経由なので DR-126 §4 の乖離検査も自動で効く。
- **「ctx.old を要する fn」は実行時の old() 参照追跡で判定する** — cell fn descriptor には
  old 依存を宣言する席が無い (io_type 席自体が無い)。`FnCtx` に `old_consulted_` を持たせ、
  fn 実行後に参照有無を読む。unset は old を読まず null を返すので空座で成立し、incr は
  読むので空座 Reject (DR-127 §3 / DR-131 §7 の文言どおりの挙動判定)。
- **Reject の面は W2-8 まで resolve 相の Err** — Sentinel (default/empty) の残余座適用・
  空座への ctx.old fn・座の解決失敗は `ladder_err` (reason は `invalid-range`、乖離は
  DR-126 §4 語彙) で全体パース失敗になる。単枝では DR-127 §4「無ければ全体パース失敗」と
  観測が一致する。兄弟枝が勝つ形 (§4.2) は W2-8 の枝ローカル fold が持つ。
- **record null 補形は build_result の値持ち上げ点 1 箇所で足りる** — `TypeSeat` 台帳
  ((path, name) → 宣言 ValueType、`collect_type_seats` + `apply_export_to_types`) を
  `build_result` に通し、`null_fill_value` が scalar セル値と accumulator 要素の両方を
  補形する (issue の受け入れ条件どおり array/map/union 内の record も再帰対象)。parser
  出力・Binding 値は不変 (DR-130 §4.1 の分離)。
- **sources の同型維持は result との zip (`align_sources_to_result`) が最小** — 補形は
  result 側だけで座を増やすので、`project_sources` の最後に result と shadow を並走させ、
  shadow に無い座を `Scalar(Null)` で写す。scalar seat / accumulator (collect_sources 産) の
  両経路を 1 箇所で覆う (座別 shadow の型併走版を書くより狭い変更で、W2-9 の座 re-tag とも
  干渉しない)。
- **`set(null)` (unset の null Value) は残余座では通常の set** (DR-131 §2b) — 器がある座は
  null が座り committed は保たれる。器そのものが無い座への null は no-op 成功 (vivify は
  set 専用 (DR-127 §3) なので器を作らず、座は論理 null のまま、セルは未 commit でラダーへ
  落ちる)。
- **conformance fixture (計画 §3 の (2)(5)) は本段では書けない** — record を名乗る builtin
  type factory が spec に無い (RECB 裁定 → DR-132 で fixture/* 仮想型が立った。実装窓は
  タスク #136)。`value_seat_wbtest.mbt` が実装側の唯一の pin。

## 実用的な示唆 / 段階実装の残余 (現在形)

- **`:set:VALUE` variant の dsl literal は entry 自身の型で decode される** (normalize 相の
  `classify_long_form`)。残余座に合わない値は発火時の乖離 Error (`seat_fn_output_breach` を
  producer="set" で通す) が受け止める — decode 自体をフィールド type で行う静的化は未実装
  (normalize 相は link 解決前で、やるなら normalize への route 供給が要る)。wbtest
  「variant literal の out 不適合も発火時に乖離 Error」が現行挙動の pin。
- **Enum body の残余 entry** は enum 値の exact match が消費構造なので parse 差し替えの対象外
  (enum 値は entry 宣言の語彙)。残余座への着地値は同じ発火時乖離検査が受ける。
- **resident output contract の一般化** (issue `2026-08-02-resident-output-contract-generalization`)
  は「値残余座への fn 戻り値」分を本段で消化。provider / filter / collector / 通常セル着地の
  cell_fns の自己宣言照合は、descriptor に ValueType を名乗る io_type 席が無いため ABI 拡張が
  先行して要る (issue に追記済み)。
- **effects 射影 (parse 相) は残余の解決失敗で座を触らず effect をそのまま観測に落とす** —
  parse 相は停止できないため。resolve 相 (と W2-8 の枝 fold) が失敗の持ち主。
- **値空間 segment の負 index の effects 表記** (解決済み非負 index、DR-127 §6) は未着手 —
  binding.observation は lowering 時の字面で、実行時解決値への書き換えは W2-9 (観測面の
  仕上げ) の領分。FieldType 終端の残余は record フィールド名 + 静的 array index しか
  含まないため、W2-7 の射程では観測乖離は起きない。

## W2-8 / W2-9 への申し送り

1. **W2-8 (枝ローカル fold)**: resolve 相の残余 Err (`resolve.mbt` の残余分岐) が発行する
   Reject 群を、裁定前の枝内判定へ引き上げる。判定素材 (container 有無 / old_consulted /
   Sentinel 種別) は共有 fold 側に既にあるので、`eval.mbt` に置く fold からも
   `CellSeats::set_at_declared` / `value_at_declared` を呼べる形にするのが最短。W2-4 §3.3 の
   「engine から共有 fold を呼べるようにするか」の判断と同着。
2. **W2-8 が ElementShape / RuntimeResolved 終端の routing を解禁する** — `residual_route`
   (`lowering.mbt`) の gate を広げ、operand パース実体が実行時に決まる経路 (map/value) の
   扱いを §2.2 表の実行時列どおりに実装する。
3. **W2-9 (観測面)**: 残余 binding の whole-cell carrier は最後に書いた binding の source を
   セル全体のタグにしている (W2-4 以前からの last-winner 意味論)。座単位の re-tag
   (`{until: link, since: cli}`) は `value_source_shadow` の座別化 + carrier の由来保存が要る。
   effects path の実行時 index 解決もここ。
4. **DR-132 実装窓 (#136)**: fixture/* 仮想型が入り次第、`value_seat_wbtest.mbt` の時系列
   5 行と vivify ケースを conformance fixture (2)(5) へ移送する (lockstep push)。

## 検証 (2026-08-02 実測)

- `just test`: 682 tests / 682 passed、conformance `decoded=396 ran_cases=889 skipped=0
  mismatches=0`。known_divergences / expected_skips 両台帳は空のまま。
- `moon check --deny-warn` green、`moon info` 差分は matcher entry の labeled param 追加のみ。
- 既存 pin 済みエラーメッセージの変更なし (新設メッセージのみ追加)。

## 関連

- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §3 / §3.2 / §4 / §4.1 / §6
- spec `docs/decisions/DR-130-null-result-projection.md` §4.1 / §5
- spec `docs/decisions/DR-131-sentinel-reduction.md` §2b / §7
- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 W2-7 行
- `docs/findings/2026-08-02-w2-4-fold-unification.md` §5.4 (set_at 契約拡張の申し送り元)
- `docs/findings/2026-08-02-w2-6-value-space-static-resolution.md` (routing 不活性の穴)
- `docs/issue/archive/2026-08-02-record-null-fill-missing-in-projection.md` (本段で close)
- `docs/issue/2026-08-02-resident-output-contract-generalization.md` (fn 分を消化、残余は ABI 拡張待ち)
