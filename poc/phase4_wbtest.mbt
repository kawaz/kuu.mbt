// phase4_wbtest.mbt — repeat as ref-recursion (DR-043). repeat lowers to a recursive
// `Seq([head, Opt(Ref(self))])` template + a porous spine unfold. These pin: the
// share-out uniqueness of `cp src... dst`, greedy interjection between reps, the min
// unroll, repeat over a ref element (a shared or-template), and the zero-progress guard.

fn full_order() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst,
  ]
}

// ── cp src... dst: the share-out is unique (DR-038 emergence) ──────────────────

test "DR-043: `cp src... dst` splits uniquely — src takes all but the last token" {
  // src is a repeat (min 1); dst is a single positional. The path-search enumerates
  // every split, but only src=[all-but-last], dst=[last] fully consumes: dst needs
  // exactly one trailing token, which pins the boundary (DR-038 一意性 creation).
  let def = def_([], [pos("src", TStr, repeat=rep(1)), pos("dst", TStr)])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, [RepeatInst], reg)
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b", "c"], defs=reg)),
    content="ok{dst=c,src=a,src=b}",
  )
  // two tokens => src=[a], dst=b
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b"], defs=reg)),
    content="ok{dst=b,src=a}",
  )
  // one token cannot satisfy both (src min 1 AND dst) => no complete parse
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a"], defs=reg)),
    content="fail:no complete parse",
  )
}

test "DR-043: the repeat lowers to the ref-recursion template Seq([head, Opt(Ref(self))])" {
  // Structural: the installer registered the DR-043 canonical shape for `src`. This
  // is the AtomicAST form (a recursive cons list), distinct from the porous unfold the
  // evaluator performs at run time.
  let def = def_([], [pos("src", TStr, repeat=rep(1)), pos("dst", TStr)])
  let reg : Map[String, Node] = Map::new()
  let _ = build_reg(def, [RepeatInst], reg)
  inspect(
    reg.get("src"),
    content=(
      #|Some(Seq([StrArg(src), Or([Ref(src), Seq([])])]))
    ),
  )
}

// ── porous: greedy interjects between reps (DR-043: unfold stays on the backbone) ─

test "DR-043/041 §4: a greedy option interjects between repeat reps (cp a --verbose b)" {
  // --verbose fires between src and dst; src cannot raw-eat --verbose (先食い), so
  // src=[a], --verbose fires, dst=b. The ref-recursion unfold stays on the current
  // backbone, so the reps are porous exactly like a Many.
  let def = def_(
    [opt("verbose", TFlag, long=["verbose"])],
    [pos("src", TStr, repeat=rep(1)), pos("dst", TStr)],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, [LongInst, RepeatInst], reg)
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "--verbose", "b"], defs=reg)),
    content="ok{dst=b,src=a,verbose=true}",
  )
  // interjection mid-list: two srcs, --verbose between them, then dst
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b", "--verbose", "c"], defs=reg)),
    content="ok{dst=c,src=a,src=b,verbose=true}",
  )
}

// ── min unroll (DR-043: min は必須段の unroll) ─────────────────────────────────

test "DR-043: repeat min:2 requires at least two reps before the tail is optional" {
  // min:2 unrolls one mandatory head then the >= 1 recursive tail (>= 2 total). With
  // a trailing dst, `cp a b c` => src=[a,b], dst=c; two tokens cannot satisfy min:2 + dst.
  let def = def_([], [pos("src", TStr, repeat=rep(2)), pos("dst", TStr)])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, [RepeatInst], reg)
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b", "c"], defs=reg)),
    content="ok{dst=c,src=a,src=b}",
  )
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b", "c", "d"], defs=reg)),
    content="ok{dst=d,src=a,src=b,src=c}",
  )
  // only two tokens: src min:2 consumes both, dst unfilled => fail
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b"], defs=reg)),
    content="fail:no complete parse",
  )
}

// ── repeat over a REF element: hlcolors = repeat of a shared `color` template ──

fn color_template() -> Node {
  // color := [r,g,b] (three numbers) | colorname (a string). DR-025's --color shape,
  // used here as an export:false template that hlcolors refs (DR-043 ref元への repeat).
  Or([
    Seq([NumArg("r"), NumArg("g"), NumArg("b")]),
    StrArg("name"),
  ])
}

test "DR-043: repeat over a ref element (hlcolors := color+, color is an or-template)" {
  // hlcolors refs the shared `color` template and repeats it (min 1). Each color is a
  // string name here, so `hlcolors red blue` => two colors. The head's consumption is
  // borne by the ref target, so the zero-progress guard reduces to "color consumes >= 1".
  let def = def_([], [pos("hlcolors", TStr, ref_=Some("color"), repeat=rep(1))])
  let reg : Map[String, Node] = Map::new()
  reg.set("color", color_template()) // color is defined once and reffed
  let sc = build_reg(def, [RepeatInst], reg)
  inspect(
    render_outcome(parse(ScopeNode(sc), ["red", "blue"], defs=reg)),
    content="ok{name=blue,name=red}",
  )
  // the ref-recursion template for hlcolors was registered with a Ref head
  inspect(
    reg.get("hlcolors"),
    content=(
      #|Some(Seq([Ref(color), Or([Ref(hlcolors), Seq([])])]))
    ),
  )
  // `255 0 0` is genuinely ambiguous: ONE rgb color [255,0,0] vs THREE string colors
  // ["255","0","0"] (StrArg is permissive). This is the DR-025 --color 4-pattern
  // ambiguity surfacing correctly through repeat-over-or-template (DR-038 counts both
  // complete paths). The definition would need `--` or a stricter name type to resolve.
  inspect(
    render_outcome(parse(ScopeNode(sc), ["255", "0", "0"], defs=reg)),
    content="ambiguous:2",
  )
}

// ── zero-progress static guard (DR-043) ────────────────────────────────────────

test "DR-043: a repeat head that consumes no token is a zero-progress error" {
  // A ref element whose target head binds without consuming (a Bind template) would
  // loop forever when unfolded. The static guard rejects it at build time.
  let def = def_([], [pos("loop", TStr, ref_=Some("noprogress"), repeat=rep(1))])
  let reg : Map[String, Node] = Map::new()
  reg.set("noprogress", Bind("x", VBool(true))) // binds 0 tokens
  match parse_definition(def, [RepeatInst], registry=reg) {
    Err(m) => inspect(m, content="repeat element 'loop' has a zero-progress head")
    Ok(_) => abort("expected zero-progress error")
  }
}
