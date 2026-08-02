# DR-132 実装窓 — fixture/* residents と conformance fixture (2)(3実行時)(4)(5)(6)(7値空間) の解禁

> 対象: spec DR-132 (fixture ns 2 住人)、DR-127 §波及の fixture 8 種の残り、DR-130 §4/§5/§8.1。
> 実装: `src/kuu/fixture_residents.mbt` (2 住人 + conformance 登録) /
> `src/kuu/json_conformance_test.mbt` (registry 注入 + 複合値 render) /
> `src/kuu/lower_conformance_wbtest.mbt` (registry 注入)。
> pin: `src/kuu/fixture_residents_wbtest.mbt` (受理輪郭 4 本) + spec `fixtures/link-parse/` 新設 4 本 14 case。

## 判明した事実

- **2 住人は TypeExt 実装 2 struct + conformance 登録 1 関数で閉じる** —
  `fixture/int_range` (output_type = `Record([("start","int"),("end","int")])`、最初の `..` で
  1 回だけ分割・バックトラックなし、全失敗を `not_an_int_range` の ValueSpaceMiss に畳む) と
  `fixture/json` (output_type = `ValueType::Value`、`@json.parse` → Value 変換、`not_json`)。
  engine / lowering / fold への変更は **ゼロ** — W2-2〜W2-9 で入れた型参照解決・residual
  routing・枝ローカル fold がそのまま ns 付き registry 住人にも働いた。
- **conformance 実行文脈への注入点は 6 箇所** — runner の `canonical_registry_for_test` (2 ファイル)
  に加え、`json_conformance_test.mbt` が `parse_definition` を素の canonical registry で呼ぶ箇所が
  4 箇所 (parse fixture decode / definition_error / help / lower 断面) あり、全部に
  `extensions=canonical_registry_for_test()` を渡さないと fixture ns の定義が
  `unknown-vocab` skip になる。`lower_conformance_wbtest` の `registry_with_installers`
  (順列不変検査の corpus 横断 decode) も同様。
- **conformance render の複合値対応は render_val / json_to_value の Array/Object 拡張だけ** —
  effects operand の比較は両側 (got = 実 Value / exp = fixture JSON) が同じ render 関数へ
  漏斗するので、object を key ソートで構造 render すれば missing key と explicit null の区別
  (DR-130 §8.1) も自動で保たれる。result / sources 側は既に構造比較で複合対応済み (W2-5)。
- **typed long (registry 型) の operand ValueSpaceMiss は「無言の失敗」(errors 空) が現行規範** —
  `--r 1.5..3` は failure + errors [] になる。これは既存 pin
  (spec `fixtures/piece-filters/reject.json::non-matching-rejected` — 「DR-037 Reject は診断を
  保持しないため errors は空」) と同じ規約であり、実装ギャップではない。builtin
  number/int/float/bool の専用 node が長形 operand の字句失敗を errors に載せる (`not_a_number`
  等) のは、これらの node が失敗を Held 族で報告する設計だから — **位相の帰属は type resident の
  自己宣言 (TypeParseDisposition) が正本**で、`registry_wbtest.mbt` の「third-party type controls
  its Reject/Error phase」「ValueSpaceMiss must fall back to the child default seat」が
  この意味を pin している。typed_arg の ValueSpaceMiss を一括で Held (committed) 化する変更は
  この 3 pin を壊すことを実測して撤回した (child-default preemption fallback が死ぬ)。
- **同じ入口の 2 位相が errors 集合の有無として観測できる** —
  `--end 1.5` (link 経路、フィールド type int の `not_an_integer` = RecognizedButInvalid = Held)
  は errors に載り、`--r 1.5..3` (string 形、`not_an_int_range` = ValueSpaceMiss = Reject) は
  errors 空。fixture `value-residual-field-write.json` の case 4/5 が対で pin。
- **枝ローカル fold の合成 ParseError の element は合流先実体** (`j`) — link の binding は
  id 層の合流で合流先セルに属し (DR-045)、effects の entity と同じ宣言名軸 (DR-121 §5) に乗る。
  operand の型パース失敗 (合流前、binding 生成前) が入口 entry 名 (`end`) に帰属するのとは
  位相が違う。`value-runtime-resolution.json` の failure 3 case が element=`j` で pin
  (reason は実装の開いた語彙のため fixture では非表明)。
- **DR-132 §4 の綴り例の link 入口 `{"name":"end","long":true}` は型なしのため canonical
  語彙では flag になり operand を食わない** — fixture は `"type":"string"` を明示した
  (§2.2 の「string 入口でもフィールド型 int が読む」の pin としてむしろ本旨に合う)。
  DR の例示は面の綴りが主眼で定義の完全性は緩い、という読みで docs は触っていない。

## 実用的な示唆

- fixture ns の住人を増やすときは `install_conformance_fixture_residents` に足すだけでよい。
  通常 registry (install_canonical) への常設はしない (DR-132 §1 — pin 都合で輪郭を変えうる)。
- 新しい「conformance 実行文脈」(runner の別断面) を作るときは parse_definition に
  必ず fixture registry を渡す — 素の呼び出しは fixture ns 定義を静かに skip 台帳へ落とす。

## 検証 (2026-08-02 実測)

- `just test`: 708 tests / 708 passed、conformance `decoded=400 ran_cases=903 skipped=0
  mismatches=0` (+4 fixture / +14 case)。known_divergences / expected_skips 両台帳は空のまま。
- `moon check --deny-warn` / `moon fmt` / `moon info` green。既存 pin の変更なし。
- spec 側 lint 3 種 (lint-reference / lint-descriptors / lint-fixtures) green (400 件適合)。

## 関連

- spec `docs/decisions/DR-132-fixture-namespace-conformance-residents.md`
- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §波及 (fixture 8 種)
- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §3 (対応表、全行済へ現行化)
- `docs/findings/2026-08-02-w2-7-vivify-and-seat-operations.md` §W2-8/W2-9 への申し送り 4 (本窓の起点)
