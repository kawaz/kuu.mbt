// phase10_wbtest.mbt — 取り分の選好 (DR-043 §取り分の選好). When two closures compete for
// a token run, the split is one interpretation's freedom of division, resolved by a
// declarative preference (greedy default / lazy) with regex-style backtracking on
// downstream failure — NOT reported as ambiguity. The preference lives in the split
// dimension only: structurally different completions (or-branch differences) stay ambiguous.

///|
fn pref_order() -> Array[Installer] {
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

// ── greedy + greedy: the left/outer closure takes the longer share ─────────────

///|
test "DR-043: greedy + greedy splits uniquely — first closure takes the longest share" {
  // Two unbounded string repeats over `a b c d e`. Without preference this is five ways to
  // split (all complete) — but the split is not an ambiguity. greedy tries the longest share
  // for the left closure first; `[a,b,c,d,e],[]` fails the right's min:1, so `[a,b,c,d],[e]`
  // is committed. Unique, no ambiguity.
  let def = def_([], [
    pos("xs", TStr, repeat=rep(1)),
    pos("ys", TStr, repeat=rep(1)),
  ])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, pref_order(), reg)
  inspect(
    result_str(sc, ["a", "b", "c", "d", "e"], defs=reg),
    content="{xs:[a,b,c,d],ys:[e]}",
  )
}

///|
test "DR-043: lazy + greedy — the lazy left closure takes the shortest share" {
  // Marking the first closure lazy flips its preference: it takes the SHORTEST share that
  // lets the rest complete, so `[a],[b,c,d,e]`.
  let def = def_([], [
    pos("xs", TStr, repeat=rep(1, lazy=true)),
    pos("ys", TStr, repeat=rep(1)),
  ])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, pref_order(), reg)
  inspect(
    result_str(sc, ["a", "b", "c", "d", "e"], defs=reg),
    content="{xs:[a],ys:[b,c,d,e]}",
  )
}

// ── backtracking on downstream failure ─────────────────────────────────────────

///|
test "DR-043: greedy backtracks when the preferred share fails downstream" {
  // A string repeat then a NUMBER repeat over `a b 3`. greedy xs first grabs `[a,b,3]`, but
  // then ys (number, min:1) has no token → fail. It backtracks, xs yields the trailing `3`,
  // and ys=[3] (a valid number) completes. So `[a,b],[3]` — regex-style backtracking.
  let def = def_([], [
    pos("xs", TStr, repeat=rep(1)),
    pos("ys", TNum, repeat=rep(1)),
  ])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, pref_order(), reg)
  inspect(
    result_str(sc, ["a", "b", "3"], defs=reg),
    content="{xs:[a,b],ys:[3]}",
  )
  // with no numeric tail at all, no share of xs lets ys get a number => genuine failure
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b", "c"], defs=reg)),
    content="fail:\"c\" is not a number",
  )
}

// ── preference is split-dimension only: or-branch differences stay ambiguous ────

///|
test "DR-043: the preference does not erode ambiguity — an or-branch difference is still ambiguous" {
  // hlcolors := color+, color := [r,g,b] | name. `255 0 0` is ONE rgb triple (a single rep,
  // rgb branch) OR three string names (three reps, name branch). These are structurally
  // different completions (different or-branch), NOT two shares of one closure — so the split
  // preference does not collapse them; they remain ambiguous:2. Preference works in the
  // share dimension only.
  let def = def_([], [pos("hlcolors", TStr, ref_=Some("color"), repeat=rep(1))])
  let reg : Map[String, Node] = Map::new()
  reg.set("color", color_template())
  let sc = build_reg(def, pref_order(), reg)
  inspect(
    render_outcome(parse(ScopeNode(sc), ["255", "0", "0"], defs=reg)),
    content="ambiguous:2",
  )
  // a pure-string run has no rgb reading, so the greedy split is unique
  inspect(
    render_outcome(parse(ScopeNode(sc), ["red", "green", "blue"], defs=reg)),
    content="ok{name=blue,name=green,name=red}",
  )
}
