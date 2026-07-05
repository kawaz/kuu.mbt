// phase16_wbtest.mbt — STRESS of the 取り分選好 completion oracle's scope-relativization
// (DR-043 末尾の注意, flagged in the 3rd/4th installments). The has_full oracle uses the GLOBAL
// input length; inside a scope whose PARENT keeps consuming after it, that basis is wrong, and
// the greedy split commits/prunes at the global end instead of the scope's boundary. These pin
// the observed behavior so the limitation is recorded, not silently worked around.

///|
fn r16() -> Array[Installer] {
  [
    LongInst,
    ShortInst,
    EnvInst,
    DdInst,
    CommandInst,
    GlobalInst,
    InheritInst,
    RepeatInst,
    MultipleInst,
  ]
}

///|
test "DR-043 flag: a repeat inside a command, with a trailing PARENT positional (oracle stress)" {
  // seq is a command whose body is a greedy repeat xs; the ROOT has a trailing positional tail.
  // A valid interpretation of `seq a b c` exists: {seq:{xs:[a,b]}, tail:c}. But the completion
  // oracle (has_full) measures against the GLOBAL length (4), so seq's greedy xs commits to
  // [a,b,c] (it reaches the global end) and prunes the [a,b] split BEFORE root's tail is tried —
  // leaving nothing for tail. The scope's true boundary is one token earlier than the global end,
  // which the global oracle cannot see. Observed outcome recorded below.
  // (旧値 fail:no complete parse は空 errors バグの凍結だった。構造的失敗が
  // ParseError を emit するようになった = spec DR-053/065 準拠)
  let def = def_cmd([], [pos("tail", TStr)], [
    cmd("seq", def_([], [pos("xs", TStr, repeat=rep(1))])),
  ])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, r16(), reg)
  inspect(
    render_outcome(parse(ScopeNode(sc), ["seq", "a", "b", "c"], defs=reg)),
    content="fail:missing operand for tail",
  )
}

// ── separator × repeat composition (DR-034 separator × DR-043 repeat) ───────────

///|
test "DR-034/043 separator × repeat: `a,b c,d` splits each token and flattens (composition)" {
  // xs is a repeat positional with separator ",". Each firing consumes one token and splits it on
  // "," (the DR-034 separator pipeline); the repeat fires once per token; the flatten accumulator
  // folds every piece into ONE list. `a,b c,d` → xs=[a,b,c,d] (2 firings × 2 pieces). This is the
  // separator/repeat composition DR-043 §検証 names.
  let def = def_([], [pos("xs", TStr, repeat=rep(1), separator=Some(","))])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, r16(), reg)
  inspect(result_str(sc, ["a,b", "c,d"], defs=reg), content="{xs:[a,b,c,d]}")
  // one token with a separator still splits (single firing, two pieces)
  inspect(result_str(sc, ["a,b"], defs=reg), content="{xs:[a,b]}")
  // a token with no separator char is a single piece
  inspect(result_str(sc, ["solo"], defs=reg), content="{xs:[solo]}")
}

///|
test "DR-034 separator (no repeat): one token splits into a list via the append accumulator" {
  // xs is a single positional (no repeat) with separator ",". One token `a,b,c` splits into three
  // pieces, collected by "append" (a separator can yield >= 2 pieces, so the cell is a list). This
  // is the value-side split (DR-034) without the structural repeat.
  let def = def_([], [pos("xs", TStr, separator=Some(","))])
  let sc = build_reg(def, r16(), Map::new())
  inspect(entity_accum(sc, "xs"), content="append")
  inspect(result_str(sc, ["a,b,c"]), content="{xs:[a,b,c]}")
}
