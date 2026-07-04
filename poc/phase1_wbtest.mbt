// phase1_wbtest.mbt — the evaluator core contracts (DR-038 / DR-041).
//
// Each test is a spec: it states what it guarantees, why the expected result is
// what it is, and the governing DR. The evaluator is the largest redesign risk
// (DR-039), so these pin its behavior before any installer exists.

// ── Contract 1: 完全経路の一意性 (DR-038) ──────────────────────────────────────
// A parse succeeds iff EXACTLY ONE complete (all-consuming) path exists:
// 0 => fail with the held Error, 1 => commit, 2+ => ambiguous.

test "DR-038: zero complete paths => fail, held Error is shown" {
  // A lone number positional fed a non-number has no complete path. The parse
  // fails and surfaces the retained Error (DR-037), not a generic message.
  let g = scope([], [NumArg("n")])
  inspect(render_outcome(parse(g, ["abc"])), content="fail:\"abc\" is not a number")
}

test "DR-038: exactly one complete path => commit" {
  // Two string positionals consume two tokens one way only.
  let g = scope([], [StrArg("a"), StrArg("b")])
  inspect(render_outcome(parse(g, ["x", "y"])), content="ok{a=x,b=y}")
}

test "DR-038: two complete paths => ambiguous (a 受け皿 makes the short path also complete)" {
  // Two unbounded string positionals and one token: the token can land in either
  // list. Both readings fully consume the input => genuinely ambiguous. This is
  // DR-038's point that ambiguity emerges when a 受け皿 lets the short path close.
  let g = scope([], [Many(StrArg("xs")), Many(StrArg("ys"))])
  inspect(render_outcome(parse(g, ["z"])), content="ambiguous:2")
}

// ── Contract 2: 多重 Accept (DR-041 §3) ───────────────────────────────────────
// A matcher enumerates ALL readings of a token as equal branches. Ambiguity is
// therefore definition- and value-parser-dependent (DR-038 §決定的な例).

test "DR-041 §3: -n1.0f is ambiguous when -f is defined (value-attach vs split)" {
  // `-n` takes a number, `-f` is a flag. The tolerant number parser accepts both
  // "1.0f" and "1.0", so the cluster yields TWO readings: n=1.0f (whole) and
  // n=1.0 + `-f` fired. Both fully consume the single token => ambiguous (DR-038).
  let short = NativeMatch(
    ShortCombine(prefix="-", entries=[
      { ch: 'n', name: "n", kind: TNum, depr: false },
      { ch: 'f', name: "f", kind: TFlag, depr: false },
    ]),
  )
  let g = scope([short], [])
  inspect(render_outcome(parse(g, ["-n1.0f"])), content="ambiguous:2")
}

test "DR-041 §3: -n1.0 is unambiguous — no split point yields a valid suffix" {
  // Same grammar, but "1.0" has no viable value/flag split, so a single reading
  // survives. Ambiguity is not intrinsic to the token shape; it needs a def to
  // absorb the suffix.
  let short = NativeMatch(
    ShortCombine(prefix="-", entries=[
      { ch: 'n', name: "n", kind: TNum, depr: false },
      { ch: 'f', name: "f", kind: TFlag, depr: false },
    ]),
  )
  let g = scope([short], [])
  inspect(render_outcome(parse(g, ["-n1.0"])), content="ok{n=1}")
}

test "DR-041 §3: -n1.0f collapses to one reading when -f is NOT defined" {
  // Drop `-f` from the definition: the "f" suffix can no longer be a flag, so the
  // only reading is n=1.0 (from the whole "1.0f"). Ambiguity is definition-driven.
  let short = NativeMatch(
    ShortCombine(prefix="-", entries=[{ ch: 'n', name: "n", kind: TNum, depr: false }]),
  )
  let g = scope([short], [])
  inspect(render_outcome(parse(g, ["-n1.0f"])), content="ok{n=1}")
}

// ── Contract 3: 先食い (DR-041 §4) ─────────────────────────────────────────────
// greedy takes priority at a positional consumption point; the positional face
// is porous; a fired greedy raw-consumes its own value slot as a bound unit.

test "DR-041 §4: greedy interjects between positionals (cp a --verbose b)" {
  // src and dst are positionals; --verbose fires between them. The positional
  // face is porous (DR-041 §4), so a=src, --verbose fires, b=dst.
  let g = scope([flag("--verbose", "verbose")], [StrArg("src"), StrArg("dst")])
  inspect(
    render_outcome(parse(g, ["a", "--verbose", "b"])),
    content="ok{dst=b,src=a,verbose=true}",
  )
}

test "DR-041 §4: greedy interjects between multiple reps (cp src... --verbose dst)" {
  // The reps of a Many are also porous: --verbose interjects mid-list, and the
  // trailing dst is still uniquely pinned (arity forces src=[a], dst=b).
  let g = scope([flag("--verbose", "verbose")], [
    Many(StrArg("src")),
    StrArg("dst"),
  ])
  inspect(
    render_outcome(parse(g, ["a", "--verbose", "b"])),
    content="ok{dst=b,src=a,verbose=true}",
  )
}

test "DR-041 §4: a fired greedy raw-consumes its value slot (--color -v => color=\"-v\")" {
  // --color is a string-value option; -v is a defined flag. Once --color fires,
  // its value slot raw-consumes the next token unconditionally (getopt 同型), so
  // color=\"-v\" even though -v is defined. -v never fires.
  let g = scope([strv("--color", "color"), flag("-v", "v")], [])
  inspect(render_outcome(parse(g, ["--color", "-v"])), content="ok{color=-v}")
}

// ── Contract 4: prefix ガードなし (DR-041 §5) ─────────────────────────────────
// An option-shaped but undefined token is not refused by form; it falls through
// to the positional. String positional succeeds; number positional holds an Error.

test "DR-041 §5: undefined -x falls into a string positional (no prefix guard)" {
  // -v is the only defined greedy trigger; -x reads nowhere, so the permissive
  // string positional eats it. Typo-into-positional is an accepted consequence.
  let g = scope([flag("-v", "v")], [StrArg("a")])
  inspect(render_outcome(parse(g, ["-x"])), content="ok{a=-x}")
}

test "DR-041 §5: undefined -x into a number positional is a held Error" {
  // Same fall-through, but the positional is a number: value_parser rejects "-x".
  // Per DR-041 §5 this is a DR-037 Error (this branch was intended, value bad),
  // shown because no complete path exists.
  let g = scope([flag("-v", "v")], [NumArg("n")])
  inspect(render_outcome(parse(g, ["-x"])), content="fail:\"-x\" is not a number")
}

// ── Contract 5: スコープ境界は greedy 面を断つ (DR-042 ⑤) ──────────────────────

test "DR-042 ⑤: parent greedy does not interrupt a child scope's positional consumption" {
  // The child scope needs exactly two positionals. The parent greedy --opt could
  // fire on the literal "--opt" token, but if it did the child would be left one
  // token short and fail. The only complete path has the child raw-eating "--opt"
  // as its first positional => the parent greedy face is severed inside the child.
  let child = ScopeNode({
    greedy: [],
    positional: [StrArg("a"), StrArg("b")],
    entities: [],
    constraints: [],
  })
  let g = scope([flag("--opt", "opt")], [child])
  inspect(render_outcome(parse(g, ["--opt", "x"])), content="ok{a=--opt,b=x}")
}

// ── Contract 6: DESIGN §15.4 ambiguous example ────────────────────────────────

test "DESIGN §15.4: --color 255 0 0 is ambiguous (arity vs positional 受け皿)" {
  // --color has variable arity: 3 numbers (r,g,b) OR 1 string name. With a
  // trailing positional 受け皿, both complete: [r=255,g=0,b=0] or
  // [name=255, rest=0,0]. Two all-consuming paths => ambiguous.
  let color_opt = Or([
    Seq([Exact("--color"), NumArg("r"), NumArg("g"), NumArg("b")]),
    Seq([Exact("--color"), StrArg("name")]),
  ])
  let g = scope([color_opt], [Many(StrArg("rest"))])
  inspect(
    render_outcome(parse(g, ["--color", "255", "0", "0"])),
    content="ambiguous:2",
  )
}
