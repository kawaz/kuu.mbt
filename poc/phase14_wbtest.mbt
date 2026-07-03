// phase14_wbtest.mbt — repeat's named accumulator (DR-043/036 "flatten"), the min>=2 and
// finite-max unfold (LOWERING §B.8), and `optional: true` as the `repeat:{min:0,max:1}` sugar
// (DR-043 — not an independent concept). The finite-max tail keeps 先食い and 取り分選好, so
// bounded repeats compose like the unbounded (Ref) ones.

fn r14() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst,
  ]
}

// ── P3: the flatten accumulator is formalized as a named registry entry (DR-036) ──

test "DR-043/036: repeat installs the built-in 'flatten' accumulator; multiple installs 'append'" {
  // A repeat positional's cell folds via "flatten" (the cons [T,[T,…]] → T[] collapse); a
  // multiple option's cell folds via "append" (DR-034). Both realize a value LIST, but the AST
  // now records WHICH registry accumulator (DR-036), so the lowered form is self-describing —
  // this is the formalization of the flatten accumulator by name.
  let def = def_(
    [opt("tag", TStr, long=["tag"], multiple=true)],
    [pos("src", TStr, repeat=rep(1))],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, r14(), reg)
  inspect(entity_accum(sc, "tag"), content="append")
  inspect(entity_accum(sc, "src"), content="flatten")
  // and the fold still works end-to-end (the naming did not change the observable list)
  inspect(result_str(sc, ["--tag", "x", "a", "b"], defs=reg), content="{tag:[x],src:[a,b]}")
}

// ── P5: min >= 2 (unbounded above, recursive Ref tail) ─────────────────────────

test "DR-043 min:2: at least two heads, unbounded above (a recursive Ref tail)" {
  // repeat {min:2} unrolls one mandatory head + a Ref(>=1) tail on the spine => at least two,
  // no upper bound. `a` alone fails the minimum; `a b` and `a b c` succeed and flatten to a list
  // (unbounded max => the "flatten" accumulator, >= 2 possible).
  let def = def_([], [pos("f", TStr, repeat=rep(2))])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, r14(), reg)
  inspect(entity_accum(sc, "f"), content="flatten")
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a"], defs=reg)),
    content="fail:no complete parse",
  )
  inspect(result_str(sc, ["a", "b"], defs=reg), content="{f:[a,b]}")
  inspect(result_str(sc, ["a", "b", "c"], defs=reg), content="{f:[a,b,c]}")
}

// ── P5: finite max (bounded, nested-optional unfold, NO recursive tail) ─────────

test "DR-043/LOWERING §B.8 max finite: {min:1,max:3} accepts 1..3, rejects a 4th" {
  // A bounded repeat lowers to `head + BoundedTail(head, 2)` (1 mandatory + up to 2 more), with
  // NO Ref recursion — the bound is the tail's depth. `a` => [a]; `a b c` => [a,b,c]; a 4th token
  // cannot be consumed (max 3) and nothing follows, so there is no complete parse. max>=2 => the
  // cell still accumulates (flatten), so even a single value renders as a 1-element list.
  let def = def_([], [pos("f", TStr, repeat=rep(1, max=Some(3)))])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, r14(), reg)
  inspect(entity_accum(sc, "f"), content="flatten")
  inspect(result_str(sc, ["a"], defs=reg), content="{f:[a]}")
  inspect(result_str(sc, ["a", "b", "c"], defs=reg), content="{f:[a,b,c]}")
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b", "c", "d"], defs=reg)),
    content="fail:no complete parse",
  )
}

test "DR-043 exact count {min:2,max:2}: exactly two heads, no more no fewer" {
  // min == max == 2 => exactly two heads (2 mandatory + BoundedTail budget 0). `a` fails the min;
  // `a b` => [a,b]; `a b c` fails (the 3rd token exceeds max and is left unconsumed).
  let def = def_([], [pos("f", TStr, repeat=rep(2, max=Some(2)))])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, r14(), reg)
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a"], defs=reg)),
    content="fail:no complete parse",
  )
  inspect(result_str(sc, ["a", "b"], defs=reg), content="{f:[a,b]}")
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b", "c"], defs=reg)),
    content="fail:no complete parse",
  )
}

// ── P5: finite max composes with 取り分選好 (greedy default / lazy) ─────────────

test "DR-043 max × 取り分選好 greedy: two bounded greedy repeats — the left takes the longest share" {
  // xs {min:1,max:3} then ys {min:1,max:3} over `a b c d`. The bounded tail carries the SAME
  // greedy preference as the unbounded Ref path: xs takes the longest share (up to its max 3)
  // that still lets ys get >= 1 => xs=[a,b,c], ys=[d]. Unique (the preference prunes the other
  // shares — they are divisions of one interpretation, not competing complete paths, DR-038 無傷).
  let def = def_(
    [],
    [
      pos("xs", TStr, repeat=rep(1, max=Some(3))),
      pos("ys", TStr, repeat=rep(1, max=Some(3))),
    ],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, r14(), reg)
  inspect(result_str(sc, ["a", "b", "c", "d"], defs=reg), content="{xs:[a,b,c],ys:[d]}")
}

test "DR-043 max × 取り分選好 lazy: a lazy bounded repeat takes the shortest share" {
  // Marking xs lazy flips its preference to the shortest share: xs takes just its mandatory `a`,
  // and greedy ys takes the rest (up to its max 3) => xs=[a], ys=[b,c,d]. Confirms greedy/lazy
  // both flow through the bounded tail (併用 with finite max).
  let def = def_(
    [],
    [
      pos("xs", TStr, repeat=rep(1, max=Some(3), lazy=true)),
      pos("ys", TStr, repeat=rep(1, max=Some(3))),
    ],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, r14(), reg)
  inspect(result_str(sc, ["a", "b", "c", "d"], defs=reg), content="{xs:[a],ys:[b,c,d]}")
}

// ── P4: `optional: true` is the {min:0,max:1} sugar (reduced, not an independent concept) ──

test "DR-043/044 optional = repeat{min:0,max:1}: the sugar lowers IDENTICALLY to the closure" {
  // `optional: true` is NOT an independent concept — it REDUCES to repeat {min:0, max:1}. Two
  // defs, one with optional=true and one with the explicit repeat, must lower to the SAME
  // AtomicAST and parse identically. This proves the sugar (one reduction), not a parallel path.
  // UNIFORM ARRAY (DR-044 §1, kawaz 裁定): declaring repetition makes the cell an ARRAY regardless
  // of cardinality — max=1 is NOT special-cased to scalar. So the cell folds via "flatten", an
  // absent optional is `[]` (not missing / null), and one match is `[x]`. Scalar is opt-in via a
  // collector (next test).
  let d_opt = def_([], [pos("x", TStr, optional=true)])
  let d_rep = def_([], [pos("x", TStr, repeat=rep(0, max=Some(1)))])
  let r1 : Map[String, Node] = Map::new()
  let r2 : Map[String, Node] = Map::new()
  let s_opt = build_reg(d_opt, r14(), r1)
  let s_rep = build_reg(d_rep, r14(), r2)
  // structural equality of the lowered scope: the sugar and the closure are the same AtomicAST
  inspect(canon_scope(s_opt) == canon_scope(s_rep), content="true")
  inspect(entity_accum(s_opt, "x"), content="flatten")
  // parse: 0 or 1 token accepted; the result is a uniform array — [] when absent, [x] when present
  inspect(result_str(s_opt, [], defs=r1), content="{x:[]}")
  inspect(result_str(s_opt, ["a"], defs=r1), content="{x:[a]}")
  // a 2nd token (nothing follows) still fails (max 1 bounds the closure)
  inspect(
    render_outcome(parse(ScopeNode(s_opt), ["a", "b"], defs=r1)),
    content="fail:no complete parse",
  )
}

test "DR-034 unwrap_single: opt-in scalar folds a 0/1 array back to a scalar" {
  // The uniform-array default gives `optional` an array `[x]` / `[]`. An app that wants a SCALAR
  // opts in to the unwrap_single collector (DR-034 縮退ケース, the same parts as any collector):
  // `[x]` → `x`, `[]` stays `[]` (nothing to unwrap). This is how scalar is recovered WITHOUT the
  // engine special-casing max=1 — the shaping is a collector concern, not a structural one.
  let def = def_([], [pos("x", TStr, optional=true)])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, r14(), reg)
  // present: [a] unwraps to a
  inspect(
    render_rval(unwrap_single(result_rval(sc, ["a"], defs=reg))),
    content="{x:a}",
  )
  // absent: [] has nothing to unwrap, stays []
  inspect(
    render_rval(unwrap_single(result_rval(sc, [], defs=reg))),
    content="{x:[]}",
  )
}

test "DR-043 optional completeness: optional needs the repeat installer (it IS repeat sugar)" {
  // Since optional reduces to a repeat, a def using optional but omitting RepeatInst is an
  // unowned-vocab error naming "repeat" — confirming optional is not a free-standing concept but
  // vocabulary owned by the repeat installer.
  let def = def_([], [pos("x", TStr, optional=true)])
  match parse_definition(def, [LongInst]) {
    Err(m) =>
      inspect(m, content="unknown special vocab 'repeat' — no installer claimed it")
    Ok(_) => abort("expected a repeat completeness error for optional")
  }
}
