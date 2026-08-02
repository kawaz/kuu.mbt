# W2-8 枝ローカル効果列 fold — 裁定前の値残余解決、共有 fold の下層化、routing 全活性化

> 対象: spec DR-127 §4.2 / §4 / §4.1 / §2.2 / §1 / §3、DR-037、
> kuu.mbt 計画 `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 W2-8 行 / §4 リスク 1 / §6.2。
> 実装: `src/internal/fold/cell_fold.mbt` (共有 fold の移設先) / `src/internal/engine/branch_fold.mbt`
> (枝ローカル fold 本体、新規) / `src/internal/engine/eval.mbt` (`parse_tree` の裁定前フック) /
> `src/internal/engine/lowering.mbt` (`ResidualRouting` — ElementShape / RuntimeResolved の routing 活性化) /
> `src/kuu/resolve.mbt` / `src/kuu/front_door.mbt` (共有 fold の参照切替)。
> pin: `src/kuu/value_seat_wbtest.mbt` (+9 本、既存 3 本を parse 相 reason へ更新) /
> `src/internal/fold/cell_fold_wbtest.mbt` (単体 pin の移設)。

## 判明した事実

- **W2-0 spike の位置に本実装が置けた。** `parse_tree` の効果集計前に完全枝 (`p == toks.length()`)
  だけを走査し、値残余の解決に失敗した Accept を `Held(合成 ParseError, bs)` へ写す。**枝落としの
  面は Held 等価** (W2-0 findings が本命とした第 3 案) — 合成 ParseError の `args_pos` が
  `max_reach` に寄与し、`push_error` / faildef / `collect_actions` は既存の Held 経路をそのまま
  通るため、A/B 変種の非対称 (push_error するのに max_reach 無寄与) が消え、専用の counting 分岐を
  1 つも足していない。partial Accept は畳まない (裁定 = 完全経路の系の外。落ちる理由は token 残余
  として既に観測されている)。Held 等価の counting 配線は production pin 済み (監査 m3) —
  WithHeld (既定) で落ちた枝の `@act:help` が `fired_action` に載ること、DeepestOnly で合成
  ParseError の args_pos が max_reach 競合に参加して action が発火することを各 1 本 pin
  (除外側の分岐は既存 Held と同一アームなので寄与側で配線を固定)。
- **第 4 の fold は作っていない。** 共有 fold (`cell_fold.mbt`) を `src/kuu/` から internal 共有
  パッケージ `src/internal/fold/` へ移し、engine (kuu の下流) からも import できるようにした。
  W2-4 findings §3.3 が障壁とした「engine が cell fn registry を import しない」は実測で解消済みの
  前提だった — `@node.Registry` は `@extension.Registry` の薄い wrapper で、`lookup_cell_fn` の
  実体は extension 層にあり engine は既に import している (`parse_tree` の `extensions` 引数が
  まさにそれ)。`fold_seat_effect` の registry 引数を `@extension.Registry` へ変えるだけで registry
  の移動は不要だった。
- **eval.mbt の `is_committed` / `element_value` 系は明示分離** (W2-4 §5.1 の宿題の裁定)。あちらは
  parse 途中の制約 gate (DR-055/DR-047) のための「fn 未発火の効果記号列に対する構文的 committed
  判定」で、operand 未確定の位置から cell fn を呼べない (`has_pending_invoke` がその手当て)。
  枝ローカル fold は完全枝・裁定直前に fn 発火込みで値状態を畳む — 入力も答えも別物なので統合
  しない。区別は `cell_fold.mbt` ヘッダに常設した。
- **fold の実行で判明した失敗を持つ枝は完全経路に数えない** (DR-037、監査 M1 で確定)。失敗は
  2 位相で、どちらも合成 ParseError 付きの Held へ写して裁定前に除外する — 語彙だけが違う:

  | 位相 | 素材 | 合成 reason |
  |---|---|---|
  | Reject (経路解決の失敗、DR-127 §3/§4.1/§4.2) | Sentinel の残余座適用 / 空座への `ctx.old` 依存 Value fn (old_consulted 判定) / 座の解決失敗 (`SeatFault` — 器不在・スカラ降下・record 宣言外フィールド・map キー不在・array index の正規化後範囲外) / 構造終端 (array 要素・map 値型) の宣言不適合 | `unresolvable_link_path` |
  | Error (実行して判明した失敗) | cell fn 未登録 / fn 実行失敗 / record フィールド終端の out 乖離 (DR-126 §4 の breach 語彙) | resolve 相と同一 (`unknown-vocab` / fn の reason / breach の reason) |

  判定対象の効果は `b.op` に依らない — Set の operand も Value fn の戻り値も、座へ座る非 null 値
  すべてが適合検査を通る (DR-127 §3.2「保証は値を運んだ経路で変わらない」)。fold が実行しない
  もの (畳んでいないセルの fn 等) は「判明した失敗」ではないので落とさず、resolve 相が持ち主。
  wbtest「判明済み失敗 (out 乖離) の枝は完全経路に数えず、成立枝が勝つ」(同一 trigger の 2 bare
  variant `:stringy`/`:unset` — 2 読みとも完全経路になり、旧実装では Ambiguous だった形) が pin。
- **保守姿勢: 宣言を特定できないセルは落とさない。** fold は binding の (scope, key) から
  `collect_seat_decls` (全 scope の Entity index、`scope_path ++ declaring_path` 鍵) で宣言を
  引き、引けない形・accumulator セルは枝選別せず resolve 相へ委ねる。枝を誤って落とすと正しい
  解釈が消えるのに対し、落とし漏れは単枝観測 (resolve 相 Err = 全体パース失敗) に一致するだけで
  DR-127 §4 の範囲に留まる。**同一鍵の宣言候補は複数保持し (後勝ち上書き禁止、監査 M3)**、
  fold が使う面 (宣言 ValueType / 宣言 default / accumulator か) で全候補が一致するときだけ
  採用、食い違えば保守的スキップ — duplicate raw command path (DR-120 合法、export_key で結果
  キー分離) で同名 target が別宣言を持つ形の誤枝刈りを防ぐ (wbtest pin)。なお同じ形で resolve
  相の entity 解決が候補を区別しない既存 gap が露出した (issue
  `2026-08-02-dup-label-scope-resolve-gap`) — fold とは独立の残課題。
- **ElementShape / RuntimeResolved の routing を活性化** (W2-6/W2-7 の不活性を解消)。
  `residual_route` は 3 値 (`Unrouted` / `RoutedField` / `RoutedRuntime`) を返し、array 要素・
  map/value 終端も `LinkRoute.residual` 付きで route する。**operand のパース実体は entry 自身の
  宣言型のまま** (`parse_ty = None`) — DR-127 §3.2 のフィールド type 差し替えは record フィールド
  終端に固有の規定で、array 要素 (構造的 ValueType) / map / value にはパース実体を名乗る registry
  住人が居ない。発火時の out 適合検査は `residual_terminal_out` が届く範囲 (array 要素は届く、
  map の内側は宣言が primitive を言えないため None) が引き続き受ける。
- **合成 ParseError の形**: `element` = 対象セル名 (link target)、`args_pos` = 当該 binding の
  `at_pos`、無ければ消費位置 (`toks.length()`) — §6.2 裁定どおり。`kind: Parse`、
  `reason: "unresolvable_link_path"` (W2-0 spike の綴りを維持)、`message` に座の診断
  (`seat_fault_message` — `missing-field:zzz` / `index-out-of-range:3` 等) を含める。`path` は
  宣言 scope の path (Entity index が持つ owning scope の command path)。実測: 範囲外 index の
  operand `9` (token 位置 3) → `args_pos=3` に帰属 (wbtest pin)。
- **全枝落ちの失敗レポートには枝ごとの理由が並ぶ** (DR-053 §2 全保持)。実測 (`--u` 単独、
  `:set`/`:incr` 同綴り): `missing_operand` (starved な :set 読み) と `unresolvable_link_path`
  (落ちた :incr 読み) の 2 件。errors[0] だけ見ると合成エラーを見落とすため、wbtest の
  `seat_failure` は全 error 結合に変更した。
- **構造終端 (array 要素 / map 値型) の座に座る値は、構造宣言への適合検査を set 時に通る**
  (統括裁定 2026-08-02 — DR-126 §4 系の「宣言に適合する値しか座に座れない」は要素型宣言にも
  及ぶ)。これらの座は operand を entry 自身の型で読む (registry パース実体が無い) ため、
  well-formed な読みでも宣言不適合が起こりうる — record フィールド終端の乖離検査 (resolve 相の
  Error) と違い、ここは**枝 Reject** (合成 reason は他の枝落としと同じ `unresolvable_link_path`、
  message に breach の詳細)。判定は `residual_terminal_structural` (`cell_fold.mbt`) — record
  フィールド終端と `value` (全域 = 恒真) と union 終端 (含有 variant 間で構造宣言が一意に
  定まらない) は `None` を返し検査対象外。適合検査の実体は W2-5 の `seat_fn_output_breach`
  (構造走査) を再利用。
- **同綴りの operand 変種 + bare 変種は、後続トークンがあるとき bare 側の読みを形成しない**
  (実測 2026-08-02: `long: [":set", ":unset"]` + min:0 の rest positional で `--u 5` は
  ambiguous にならず :set 読みのみ。`--u` 単独では bare 読みだけが完全経路になる)。したがって
  「枝 Reject → 兄弟枝が勝つ」の実 2 読み pin はこの形では作れず、**variable-arity or**
  (`fixtures/path-search/variable-arity-ambiguous.json` の形: seq(number,number) | string) +
  **optional link positional** (`repeat {min:0, max:1}` + `link: "arr[0]"`) で構成した —
  string 読みだけが positional を発火させて要素型不適合で落ち、seq 読みが勝つ。link 無し /
  適合型の対照は両方 ambiguous:2 を実測 (= 2 読みの実在と、fold が解決可能な枝を落とさない
  対極の両方を裏取り)。なお link は or / seq / ref entry には置けない (定義時
  `link with ref/or/seq is not supported`) ため、匿名 or 枝で operand の型を割る構成は不可。

## 実用的な示唆 / 残余 (現在形)

- **「兄弟枝が勝つ」の実 ambiguity は variable-arity or + optional link positional で作る**
  (判明した事実の最終 bullet)。ctx.old / Sentinel 系の Reject は Invoke 変種 (long dsl) にしか
  乗らず、bare 変種は後続トークンがあると読みを形成しないため、これらの実 2 読み pin は現状の
  定義語彙では構成できない — 単枝 (全枝落ち) の形で pin している。record を名乗る builtin type が
  spec に無いため conformance fixture (計画 §3 の (3) 実行時分 / (4)) は DR-132 実装窓 (#136) で
  移送する (lockstep push)。それまで wbtest が唯一の pin。
- **W2-7 の単枝 Err pin 3 本は位相が移った** (「W2-8 まで resolve 相の Err」の予定どおり)。
  空座 ctx.old / Sentinel(default) / old 読み null 返しの 3 本は、いまは parse 相の
  `unresolvable_link_path` として観測される。実装完了の RED エビデンスはこの 3 本 (実装直後に
  旧 reason `invalid-range` のまま fail → 更新) — 逆向きに読めば、この 3 本が「fold 以前は
  resolve 相まで到達していた」ことの回帰網でもある。
- **parse 相 fold は env / config を引けない** (W2-4 findings §3.2 と同根の既知残差)。明示の
  `default` 効果が座へ戻す値は宣言 default 止まりで、resolve 相のラダー値と容器の中身が違う場合
  (env/config が当該セルへ供給し、かつ後続の実行時解決が容器の中身の形に依存する場合) に枝選別と
  resolve の判定がずれうる。`project_effects` の公開 API 形と一体の論点なので W2-9 で判断する。
- **effects の値空間 index は字面のまま** (`arr[-1]`)。解決済み非負 index への書き換え (DR-127 §6、
  統括裁定 3) は W2-9 の領分 — wbtest「負 index は発火時点の現在長で解決される」が現状の観測
  (`effects=arr,arr[-1]`) を pin しており、W2-9 で更新される予定の座。sources の座単位 re-tag も
  同様 (whole-cell carrier が全要素へ写る: `sources={arr=[link,link,link]}`)。
- **fold は値残余を持つセルだけ畳む** — 既存経路 (値残余ゼロ) では `binding_has_value_residual`
  の一走査だけで、Entity index の構築も走らない。既存 889 cases の不変はこの構造で担保
  (conformance 実測 889/0 不変)。
- **cell fn の多重実行は FiringRecord 一本化で解消済み**
  (`docs/findings/2026-08-02-firing-record-unification.md`)。枝ローカル fold の枝内実行結果は
  勝ち枝の FiringRecord として配達され、effects 射影と resolve 相は消費者になる — 危険域
  (**value_residual セル × 非決定 Value fn** の枝選別値と座値の乖離) は wbtest で閉じを pin。
- **resolve 相の残余分岐は最終防衛線として全判定を保持する** — CLI 以外の供給経路や fold の
  保守的スキップがここへ届くため。resolve.mbt 側のコメントに分業 (fold = 枝選別 / resolve =
  乖離検査・fn 失敗・最終防衛) を常設した。

## 検証 (2026-08-02 実測)

- `just test`: 694 tests / 694 passed (構造適合検査の追加前)、conformance `decoded=396 ran_cases=889 skipped=0
  mismatches=0`。known_divergences / expected_skips 両台帳は空のまま。
- `moon check --deny-warn` green、`moon fmt` / `moon info` 適用済み (fold パッケージの
  `pkg.generated.mbti` 新設、engine 側は非公開関数のみで mbti 差分なし)。
- 既存 pin メッセージの変更は W2-7 の単枝 Err 3 本 (位相移動、上記) のみ。新設 wbtest 14 本
  (監査 m2 の本数訂正込み): 解決可能な値残余の読みの fold 通過 / 全枝落ち + 原因合成 /
  map キー実在の部分書き / map キー不在の全枝落ち / 負 index の現在長解決 / 範囲外 index の
  args_pos 帰属 / subcommand scope 配下の枝選別 / 要素型不適合の枝 Reject → 兄弟枝が勝つ
  (実 2 読み) / 解決可能な枝は落とさない (ambiguous 保存、対極) / map 値型不適合の単枝 Failure /
  判明済み失敗 (out 乖離) の枝除外 → 成立枝が勝つ (M1) / 同名 command 2 本の保守的スキップ (M3) /
  Held 等価の WithHeld action 寄与 (m3) / DeepestOnly max_reach 競合参加 (m3)。
- 検証時点の総数: `just test` = **701 tests / 701 passed**、conformance 889/0 不変 (監査対応後)。

## 関連

- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §1 / §2.2 / §3 / §4 / §4.1 / §4.2
- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 W2-8 行 / §4 リスク 1 / §6.2
- `docs/findings/2026-08-02-w2-spike-fold-placement.md` (W2-0 spike — 置き場と Held 等価の設計入力)
- `docs/findings/2026-08-02-w2-4-fold-unification.md` §3.3 / §5.1 (第 3 fold の宿題の出所)
- `docs/findings/2026-08-02-w2-7-vivify-and-seat-operations.md` §申し送り 1/2 (RED 化起点と routing 解禁)
