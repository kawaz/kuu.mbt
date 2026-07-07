// eval_wbtest.mbt — acceptance tests for the CPS evaluator core (MDR-002).
//
// These pin the TWO breakages the re-design exists to fix, on hand-built
// AtomicAST (no lowering involved — the installer layer lands separately, so
// these tests stay valid even if lowering changes shape).

///|
/// The repeat registry template `Seq([head, …])`: the spine walk (scope_consume
/// Ref arm) only reads items[0] as the head; the porous unfold is structural.
fn reg_repeat(defs : Map[String, Node], name : String, head : Node) -> Unit {
  defs.set(name, Seq([head]))
}

///|
test "MDR-002 §1.5 acceptance: greedy repeat in a child command yields the parent's trailing positional (phase16 fix)" {
  // Root R: one trailing positional `tail`, one greedy command `seq` whose
  // body is an unbounded greedy repeat `xs` (min 1). Input `seq a b c`.
  //
  // The slice's global-length oracle committed xs=[a,b,c] (it reaches the
  // global end) and starved `tail` → "fail:missing operand for tail" (the
  // phase16 frozen fail). The CPS oracle instead runs the continuation: the
  // xs=[a,b] split's `stop` resumes R, consumes `c` into tail, and reaches
  // KTop at the global end → Accept; the xs=[a,b,c] split's continuation
  // Helds on tail → pruned. Exactly one complete path remains.
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "xs", StrArg("xs"))
  let child : Scope = {
    greedy: [],
    positional: [Ref("xs")],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("seq", child)],
    positional: [StrArg("tail")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["seq", "a", "b", "c"], defs~)
  match o {
    Success(bs) => {
      // xs reps nest under [seq]; tail lands at the root. The result-object
      // view {seq:{xs:[a,b]}, tail:c} is the resolve layer's fold of exactly
      // these bindings.
      let mut xs_count = 0
      let mut tail_ok = false
      let mut xs_in_seq = true
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
          if b.scope != ["seq"] {
            xs_in_seq = false
          }
        }
        if b.key == "tail" {
          match b.value {
            VStr(s) => if s == "c" && b.scope.length() == 0 { tail_ok = true }
            _ => ()
          }
        }
      }
      // xs took exactly 2 reps (a, b) — the [a,b,c] share was pruned by the
      // continuation oracle, the [a] share by greedy preference (more wins
      // when both complete? no: [a] leaves b unconsumable by tail+end, so it
      // never completes — only [a,b] survives).
      assert_eq(xs_count, 2)
      assert_true(xs_in_seq)
      assert_true(tail_ok)
    }
    _ => fail("expected Success")
  }
}

///|
test "MDR-002 §1.4 control: without the trailing positional, greedy xs takes everything" {
  // Same shape minus `tail`: xs correctly commits to [a,b,c] (greedy default
  // = the longer share, and that share completes).
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "xs", StrArg("xs"))
  let child : Scope = {
    greedy: [],
    positional: [Ref("xs")],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("seq", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["seq", "a", "b", "c"], defs~)
  match o {
    Success(bs) => {
      let mut xs_count = 0
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
        }
      }
      assert_eq(xs_count, 3)
    }
    _ => fail("expected Success")
  }
}

///|
test "MDR-002 §2.6 acceptance: a value-less trigger at the end of input is a missing-operand failure, not a raw positional eat" {
  // Root: permissive string positional `files` + greedy `--port <num>`.
  // Input ["--port"]: the trigger is consumed but the value slot is starved.
  //
  // The slice's greedy_reads required FULL consumption, so the greedy entry
  // vanished ([]), 先食い did not fire, and `files` raw-ate the literal
  // string "--port" → a silent wrong Success. With Pending counted as
  // "reads", the raw-eat is suppressed and the parse fails with a proper
  // missing-operand error for `port`.
  let root : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port")])],
    positional: [StrArg("files")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--port"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut port_missing = false
      for e in fd.errors {
        if e.element == "port" && e.kind == KParse {
          port_missing = true
        }
      }
      assert_true(port_missing)
    }
    _ => fail("expected Failure")
  }
}

///|
test "positional spine + greedy interjection sanity (order-free trigger between positionals)" {
  // prog a --v b : greedy flag --v interjects between two positionals.
  let root : Scope = {
    greedy: [Seq([Exact("--v"), Bind("v", VBool(true))])],
    positional: [StrArg("x"), StrArg("y")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "--v", "b"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut got_v = false
      let mut got_x = false
      let mut got_y = false
      for b in bs {
        if b.key == "v" {
          got_v = true
        }
        if b.key == "x" {
          match b.value {
            VStr(s) => if s == "a" { got_x = true }
            _ => ()
          }
        }
        if b.key == "y" {
          match b.value {
            VStr(s) => if s == "b" { got_y = true }
            _ => ()
          }
        }
      }
      assert_true(got_v)
      assert_true(got_x)
      assert_true(got_y)
    }
    _ => fail("expected Success")
  }
}

///|
test "dd sever: past `--`, a trigger-looking token falls raw into the positional" {
  let root : Scope = {
    greedy: [Seq([Exact("--v"), Bind("v", VBool(true))]), DdSat("--")],
    positional: [StrArg("x")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--", "--v"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut x_is_trigger = false
      for b in bs {
        if b.key == "x" {
          match b.value {
            VStr(s) => if s == "--v" { x_is_trigger = true }
            _ => ()
          }
        }
      }
      assert_true(x_is_trigger)
    }
    _ => fail("expected Success")
  }
}

///|
test "residual token failure: an unconsumable trailing token is a KTop held error" {
  // No positionals, no greedy match for "zzz" → every path stops short of
  // the global end. The KTop continuation surfaces the residual head as a
  // held Error (element "", kind parse) — the slice synthesized this at the
  // top level from silently-dropped partial Accepts; under CPS it emerges
  // naturally where the residual is observed.
  let root : Scope = {
    greedy: [],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["zzz"], defs=Map([]))
  match o {
    Failure(fd) => {
      assert_true(fd.errors.length() >= 1)
      assert_eq(fd.errors[0].message, "unexpected token")
    }
    _ => fail("expected Failure")
  }
}

///|
test "REVIEW-H1 probe: repeat head = ScopeNode (off-spine KDone) with outer trailing positional" {
  // The reviewer's threat scenario: a repeat whose HEAD is itself a ScopeNode
  // containing an inner repeat. The head is evaluated through consume_head's
  // generic fallback -> plain eval() -> KDone, so the INNER repeat's 取り分
  // oracle cannot see the outer scope's trailing positional. If KDone
  // reintroduces breakage-1 here, the inner xs eats a,b,c and tail starves.
  // Correct outcome: xs=[a,b], tail=c (same shape as phase16, one level in).
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "xs", StrArg("xs"))
  let inner : Scope = {
    greedy: [],
    positional: [Ref("xs")],
    entities: [],
    constraints: [],
  }
  reg_repeat(defs, "grp", ScopeNode(inner))
  let root : Scope = {
    greedy: [],
    positional: [Ref("grp"), StrArg("tail")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "c"], defs~)
  match o {
    Success(bs) => {
      let mut xs_count = 0
      let mut tail_ok = false
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
        }
        if b.key == "tail" {
          tail_ok = true
        }
      }
      assert_eq(xs_count, 2)
      assert_true(tail_ok)
    }
    _ => fail("expected Success")
  }
}

///|
test "DR-043 sequential repeats: xs ys over a b c d e — greedy xs takes the longer share, ys gets the rest" {
  // DR-043's own primary 取り分選好 example: two adjacent unbounded repeats
  // (both min 1, greedy default). The split is ONE interpretation's freedom
  // of division, not an ambiguity: greedy xs prefers the longest share whose
  // continuation still completes -> xs=[a,b,c,d], ys=[e]. Exactly one path.
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "xs", StrArg("xs"))
  reg_repeat(defs, "ys", StrArg("ys"))
  let root : Scope = {
    greedy: [],
    positional: [Ref("xs"), Ref("ys")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "c", "d", "e"], defs~)
  match o {
    Success(bs) => {
      let mut xs_count = 0
      let mut ys_count = 0
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
        }
        if b.key == "ys" {
          ys_count = ys_count + 1
        }
      }
      assert_eq(xs_count, 4)
      assert_eq(ys_count, 1)
    }
    _ => fail("expected Success")
  }
}
