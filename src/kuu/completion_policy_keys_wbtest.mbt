// completion_policy_keys_wbtest.mbt — policy 段の 2 つの突き合わせキーの単体 pin
// (docs/issue/2026-08-12-completion-query-residual-minors.md の RE-4 / RE-6)。
//
// どちらも「同綴りの候補 / 行が複数あるときに何を同一視するか」の判定で、成立には退化構成
// (別 scope の同名要素 / 同綴り別 option + insert_form="eq") が要る。conformance fixture 側の
// 完成度目当ての定義では組みにくいので、純粋関数として直接その構成を渡して固定する。

///|
fn policy_key_candidate(
  spelling : String,
  origin : String,
  term : @abi.TermHint,
  scope : Array[String],
) -> ScopedCandidate {
  {
    candidate: {
      spelling,
      is_value: false,
      type_name: "",
      origin,
      term,
      is_alias: false,
      hidden: false,
      deprecated: false,
      completer: None,
    },
    scope,
    face: OptionFace,
  }
}

///|
/// 保証 (RE-4): DR-117 §5 の word_end / cont ペア判定は**同じセルの 2 つの入口**についての
/// 規則である。曖昧読みで root と子 scope に同名要素が併存すると (origin, spelling) だけの
/// キーでは別 scope の候補どうしが誤ってペア成立し、insert_form="eq" 下で片方が畳み消される。
/// 帰属 scope はペア同一性の一部。
test "merge_insert_form: 別 scope の同名候補はペアを形成しない (RE-4)" {
  // root の `--mode` (word_end) と 子 scope `sub` の `--mode` (cont)。origin も spelling も同じ。
  let cross_scope = [
    policy_key_candidate("--mode", "mode", WordEnd, []),
    policy_key_candidate("--mode", "mode", Continue, ["sub"]),
  ]
  let merged = merge_insert_form(cross_scope, "eq")
  // 別 scope = 別セルなので、どちらも単独候補のまま残る (§5「単独候補の形を書き換えない」)。
  assert_eq(merged.length(), 2)
  for pc in merged {
    assert_false(pc.eq_form)
  }

  // 対照: 同一 scope の同一 origin なら従来どおりペアが成立し、eq 側へ 1 件に畳む。
  let same_scope = [
    policy_key_candidate("--mode", "mode", WordEnd, ["sub"]),
    policy_key_candidate("--mode", "mode", Continue, ["sub"]),
  ]
  let folded = merge_insert_form(same_scope, "eq")
  assert_eq(folded.length(), 1)
  assert_true(folded[0].eq_form)
}

///|
/// 保証 (RE-6): 表示行の畳みは**最終表示綴り**でも突き合わせる。`insert_form="eq"` では
/// 畳みが行の綴りを `--mode` -> `--mode=` に書き換えるが、突き合わせキーが畳み前の綴りの
/// ままだと、最初から `--mode=` として emit された行と併存して**表示上同一の行が 2 本**残る。
test "collapse_duplicate_rows: 畳み後の綴りも突き合わせキーになる (RE-6)" {
  // or ブランチ由来で word_end / cont が別 origin になり §5 のペアが成立しなかった 2 行が
  // 先に来て、ここで `--mode=` へ畳まれる。その後に §5 のペア成立で最初から `--mode=` と
  // なった行が来る。
  let rows : Array[QueryRow] = [
    { spelling: "--mode", description: "", nospace: false },
    { spelling: "--mode", description: "mode of operation", nospace: true },
    { spelling: "--mode=", description: "", nospace: true },
  ]
  let collapsed = collapse_duplicate_rows(rows, "eq")
  assert_eq(collapsed.length(), 1)
  assert_eq(collapsed[0].spelling, "--mode=")
  assert_true(collapsed[0].nospace)
  // 説明は先に見つかった非空を保つ (畳みの既存規則)。
  assert_eq(collapsed[0].description, "mode of operation")

  // 対照: "space" 側は綴りを書き換えないので、従来どおり 1 行に畳まれる。
  let space_rows : Array[QueryRow] = [
    { spelling: "--mode", description: "", nospace: false },
    { spelling: "--mode", description: "d", nospace: true },
  ]
  let space_collapsed = collapse_duplicate_rows(space_rows, "space")
  assert_eq(space_collapsed.length(), 1)
  assert_eq(space_collapsed[0].spelling, "--mode")
  assert_false(space_collapsed[0].nospace)
}
