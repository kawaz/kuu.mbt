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
    greedy: [Seq([Exact("--port"), NumArg("port", false)])],
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

///|
test "REVIEW-C1 fired_action survives a failing value slot in the same greedy entry" {
  // A failure-action entry that ALSO takes a value: Seq([--help, FailMark,
  // NumArg]). When the value fails to parse, the FailMark marker bound
  // earlier in the SAME Seq must still reach parse() on the Held's partial
  // state — fired_action and the held error coexist (spec DR-048/DR-053 §4).
  // The slice dropped the Seq-internal acc on Held, losing the action.
  let root : Scope = {
    greedy: [Seq([Exact("--help"), FailMark("help"), NumArg("n", false)])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--help", "abc"], defs=Map([]))
  match o {
    Failure(fd) => {
      assert_eq(fd.fired_action, Some("help"))
      let mut saw_parse_err = false
      for e in fd.errors {
        if e.element == "n" && e.reason == "not_a_number" {
          saw_parse_err = true
        }
      }
      assert_true(saw_parse_err)
    }
    _ => fail("expected Failure")
  }
}

///|
test "REVIEW-C2 eval_many: a Pending after successful reps carries the reps' bindings" {
  // Whitebox: one rep of StrArg("v") consumes the only token, the next rep
  // starves -> Pending. Its partial state must include v=x (the same
  // contract as eval_seq: Pending = starved branch WITH its state).
  let ctx : Ctx = { toks: ["x"], defs: Map([]), mode: ModeParse }
  let brs = eval_many(StrArg("v"), ctx, 0, [])
  let mut pending_has_acc = false
  for b in brs {
    match b {
      Pending(_, bs) =>
        if bs.length() == 1 && bs[0].key == "v" {
          pending_has_acc = true
        }
      _ => ()
    }
  }
  assert_true(pending_has_acc)
}

///|
test "REVIEW-C3 head_name knows FilterArg: optional extra rep at EOF is a stop, not an error" {
  // Repeat of a FilterArg head followed by a mandatory positional z, input
  // exhausts after one rep. The genuine failure is "z missing"; the "one
  // more n" probe finding no token is a legitimate stop and must NOT add a
  // missing-operand-for-n error (drop_optional_missing needs the head's
  // name, which FilterArg supplies via head_name).
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "ns", FilterArg("n", 100))
  let root : Scope = {
    greedy: [],
    positional: [Ref("ns"), StrArg("z")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["5"], defs~)
  match o {
    Failure(fd) => {
      for e in fd.errors {
        // no error may blame the repeat element n for "missing operand"
        assert_false(e.element == "n" && e.reason == "missing_operand")
      }
      let mut z_missing = false
      for e in fd.errors {
        if e.element == "z" && e.reason == "missing_operand" {
          z_missing = true
        }
      }
      assert_true(z_missing)
    }
    _ => fail("expected Failure")
  }
}

///|
test "REVIEW-C4 non-scope root: residual of a partial Accept surfaces even when another branch held an error" {
  // Or branch 1 accepts "a" leaving "xyz" residual (partial Accept);
  // branch 2 helds a not_a_number on "xyz". 0 complete paths -> failure.
  // Both failure reasons must be retained (DR-053 §2 全保持): gating the
  // residual synthesis on "errors empty" would mask the partial reading.
  let root = Or([Exact("a"), Seq([Exact("a"), NumArg("n", false)])])
  let o = parse(root, ["a", "xyz"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut saw_residual = false
      let mut saw_parse = false
      for e in fd.errors {
        if e.reason == "unexpected_token" && e.argv_pos == 1 {
          saw_residual = true
        }
        if e.reason == "not_a_number" {
          saw_parse = true
        }
      }
      assert_true(saw_residual)
      assert_true(saw_parse)
    }
    _ => fail("expected Failure")
  }
}

///|
test "REGRESSION dd sever transparent to positional inline ScopeNode child (DR-041 dashdash)" {
  // deep-review R4a: root's DdSat("--") fires; the positional walk then
  // enters a ScopeNode child; without the sever pass-through the child's
  // greedy face resurrects and reads "-x" as the child's -x option
  // (Success x=true, a="w"). Spec DR-041/042 ⑤: dd's continuation is raw
  // for the WHOLE spine, including any inline child scope reached via the
  // positional face — so "-x" must land as the child's positional a, and
  // "w" is a residual token → Failure.
  let child : Scope = {
    greedy: [Seq([Exact("-x"), Bind("x", VBool(true))])],
    positional: [StrArg("a")],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [DdSat("--")],
    positional: [ScopeNode(child)],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--", "-x", "w"], defs=Map([]))
  match o {
    Failure(fd) => {
      // no x binding should exist (child greedy face is severed) and the
      // residual "w" surfaces as a KTop unexpected_token at argv_pos 2.
      let mut saw_residual = false
      for e in fd.errors {
        if e.reason == "unexpected_token" && e.argv_pos == 2 {
          saw_residual = true
        }
      }
      assert_true(saw_residual)
    }
    _ => fail("expected Failure (child greedy must be severed under dd)")
  }
}

///|
test "REGRESSION step_greedy Held carries acc so FailMark survives to DeepestOnly fired_action" {
  // deep-review "step_greedy acc": two greedy entries — a FailMark help
  // action, and a numeric option. Under faildef=DeepestOnly the ONLY
  // candidate path for fired_action collection is the deepest one:
  // consume --help (bind help + FailMark) → consume --num → NumArg("xyz", false)
  // parse fail @ argv_pos 2. Without acc on the Held branch, the FailMark
  // binding accumulated before the Held is dropped and fired_action
  // becomes None. With it, fired_action = Some("help").
  let root : Scope = {
    greedy: [
      Seq([Exact("--help"), Bind("help", VBool(true)), FailMark("help")]),
      Seq([Exact("--num"), NumArg("n", false)]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(
    ScopeNode(root),
    ["--help", "--num", "xyz"],
    defs=Map([]),
    faildef=DeepestOnly,
  )
  match o {
    Failure(fd) => assert_eq(fd.fired_action, Some("help"))
    _ => fail("expected Failure")
  }
}

///|
test "REGRESSION consume_head ReqArg respects 先食い (raw-eat suppression)" {
  // deep-review LENS-T2b: `fs` is a Ref-repeat over ReqArg head. Without
  // the ReqArg arm in consume_head, the fallback eval() sees no scope and
  // cannot apply suppressed(), so the "more" rep of fs raw-eats the
  // greedy trigger "-v" as another f value. Correct: -v fires the greedy
  // entry (verbose=true), fs has ONE binding.
  let defs : Map[String, Node] = Map([])
  defs.set("fs", Seq([ReqArg("f")]))
  let root : Scope = {
    greedy: [Seq([Exact("-v"), Bind("verbose", VBool(true))])],
    positional: [Ref("fs")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "-v"], defs~)
  match o {
    Success(bs) => {
      let mut f_count = 0
      let mut verbose_ok = false
      for b in bs {
        if b.key == "f" {
          f_count = f_count + 1
        }
        if b.key == "verbose" {
          match b.value {
            VBool(v) => if v { verbose_ok = true }
            _ => ()
          }
        }
      }
      assert_eq(f_count, 1)
      assert_true(verbose_ok)
    }
    _ => fail("expected Success (verbose fires, fs=[a])")
  }
}

///|
test "REGRESSION Many spine takes preference (greedy default, no Ambiguous)" {
  // deep-review LENS-T6: two adjacent Many closures without preference
  // return Ambiguous (3-way split of ["a","b"] between xs and ys). DR-043
  // "取り分次元は代表 1 本に確定" — greedy default (Many has no lazy_
  // knob) picks the more-rep-first split: xs=[a,b], ys=[].
  let root : Scope = {
    greedy: [],
    positional: [Many(StrArg("xs"), false), Many(StrArg("ys"), false)],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b"], defs=Map([]))
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
      assert_eq(xs_count, 2)
      assert_eq(ys_count, 0)
    }
    _ => fail("expected Success xs=2 ys=0 (no Ambiguous)")
  }
}

///|
/// DR-043 lazy on the min:0 UNBOUNDED spine form (issue 2026-07-08 min0-lazy-repeat-gap,
/// resolved): `Many`'s 2nd field mirrors this test's greedy-default sibling above, with the
/// tie-break flipped. `Many(xs, true)` adjacent to `Many(ys, false)` on ["a","b","c"] takes the
/// SHORTEST xs share (0 reps) instead of the longest — same shape as preference-lazy.json's
/// min:1 case (`xs=[a]` there, the mandatory minimum; here the mandatory minimum is 0).
test "DR-043: Many(lazy=true) prefers the shortest (0-rep) share, mirroring the greedy default" {
  let root : Scope = {
    greedy: [],
    positional: [Many(StrArg("xs"), true), Many(StrArg("ys"), false)],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "c"], defs=Map([]))
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
      assert_eq(xs_count, 0)
      assert_eq(ys_count, 3)
    }
    _ => fail("expected Success xs=0 ys=3 (lazy prefers shortest)")
  }
}

///|
test "REGRESSION scope-shaped Ref head: more-branch drops internal missing_operand only" {
  // deep-review LENS-T3: Ref("r")'s head is ScopeNode(inner) with a
  // single StrArg("f") positional. Input ["a"] consumes 1 rep (f=a);
  // the OPTIONAL "more" rep enters inner at EOF, producing Held(pe_missing
  // "f"). Before the fix, head_name(ScopeNode)="" left drop_optional_missing
  // inert, so "f missing" leaked into FailureData.errors alongside the
  // real downstream failure ("n missing"). With head_elem_names the
  // internal "f" is dropped, only the head-external "n" missing remains.
  let defs : Map[String, Node] = Map([])
  let inner : Scope = {
    greedy: [],
    positional: [StrArg("f")],
    entities: [],
    constraints: [],
  }
  defs.set("r", Seq([ScopeNode(inner)]))
  let root : Scope = {
    greedy: [],
    positional: [Ref("r"), NumArg("n", false)],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a"], defs~)
  match o {
    Failure(fd) => {
      let mut saw_n_missing = false
      let mut saw_f_missing = false
      for e in fd.errors {
        if e.reason == "missing_operand" && e.element == "n" {
          saw_n_missing = true
        }
        if e.reason == "missing_operand" && e.element == "f" {
          saw_f_missing = true
        }
      }
      assert_true(saw_n_missing)
      assert_false(saw_f_missing)
    }
    _ => fail("expected Failure")
  }
}

///|
test "REGRESSION Or-wrapped greedy: find_help_entry / tried_triggers walk Or arms" {
  // deep-review REVIEW-O4: help_entry / tried_triggers must reflect Or-
  // bundled greedy entries (step_greedy treats each alt as its own
  // interjection). Before the outcome.mbt fix, an Or-wrapped --help was
  // invisible to both materials. Input ["--typo"] fails — help_entry
  // should carry "--help" and tried_triggers should list both "--help"
  // and "--verbose".
  let root : Scope = {
    greedy: [
      Or([
        Seq([Exact("--help"), Bind("help", VBool(true)), FailMark("help")]),
        Seq([Exact("--verbose"), Bind("v", VBool(true))]),
      ]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--typo"], defs=Map([]))
  match o {
    Failure(fd) => {
      assert_eq(fd.help_entry, Some("--help"))
      let mut saw_help = false
      let mut saw_verbose = false
      for t in fd.tried_triggers {
        if t == "--help" {
          saw_help = true
        }
        if t == "--verbose" {
          saw_verbose = true
        }
      }
      assert_true(saw_help)
      assert_true(saw_verbose)
    }
    _ => fail("expected Failure")
  }
}

///|
/// DR-053 §4 (issue 2026-07-08 greedy-once-and-idxrepeat-premises §3, resolved): tried_triggers is
/// the triggers available AT THE FAILURE POSITION (§4 immediately follows §2's "primary の定義:
/// argv 位置が最深の Error" in the same DR), not always root's — DR-041 §4 "読める最内スコープが勝つ"
/// means a failure INSIDE a subcommand's own scope should surface that scope's OWN greedy triggers.
/// `sub zzz` ("zzz" is an unconsumed residual inside "sub"'s scope, whose only positional-face
/// element is none — a bare unexpected_token) used to report only root's "sub" command name;
/// now it reports "sub"'s own `--port` trigger, the one actually offered at the failure site.
test "DR-053 §4: tried_triggers reflects the failure position's OWN scope, not root's" {
  let child : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port", false)])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["sub", "zzz"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut saw_port = false
      let mut saw_sub = false
      for t in fd.tried_triggers {
        if t == "--port" {
          saw_port = true
        }
        if t == "sub" {
          saw_sub = true
        }
      }
      assert_true(saw_port)
      assert_false(saw_sub) // root's "sub" is NOT the failure-position scope
    }
    _ => fail("expected Failure (residual 'zzz' inside sub's scope)")
  }
}

///|
test "REVIEW-D1 取り分選好オラクルは制約違反の全消費を「完全」と数えない (DR-047 §2 × DR-043)" {
  // more 側 (xs=[a,b]) は全消費だが CRequires(xs,[y]) に違反 = 完全解決経路
  // ではない。stop 側 (xs=[a], y=[b]) が唯一の完全解決経路なので Success。
  // KTop が制約を評価して違反を Held 化することで、has_full_k (選好オラクル)
  // と parse() の「完全経路」定義が 1 箇所に統一される — 旧実装は選好層が
  // 違反経路を完全と誤認して stop 側を刈り、false Failure になっていた。
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "xs", StrArg("xs"))
  let root : Scope = {
    greedy: [],
    positional: [Ref("xs"), Many(StrArg("y"), false)],
    entities: [],
    constraints: [CRequires("xs", ["y"])],
  }
  let o = parse(ScopeNode(root), ["a", "b"], defs~)
  match o {
    Success(bs) => {
      let mut xs_count = 0
      let mut y_count = 0
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
        }
        if b.key == "y" {
          y_count = y_count + 1
        }
      }
      assert_eq(xs_count, 1)
      assert_eq(y_count, 1)
    }
    _ => fail("expected Success (xs=[a], y=[b])")
  }
}

///|
test "REVIEW-D2 制約照合は scope-exact: 子スコープの同名 key は root 制約を発火させない (DR-055 §1 lexical)" {
  // 子スコープの x (scope=["c"]) だけが commit される入力。root 宣言の
  // CRequires("x",[...]) の対象は root の x セルなので不活性 = Success。
  let child : Scope = {
    greedy: [],
    positional: [StrArg("x")],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("c", child)],
    positional: [],
    entities: [],
    constraints: [CRequires("x", ["z"])],
  }
  let o = parse(ScopeNode(root), ["c", "v"], defs=Map([]))
  match o {
    Success(_) => ()
    _ => fail("expected Success (root x is uncommitted)")
  }
}

///|
test "REVIEW-D3 誤充足も塞ぐ: requires のターゲットは子スコープの同名 binding では満たされない" {
  // root の file が commit、requires ターゲット out は子スコープにしか
  // commit されない → root の out は不在なので requires_violated の Failure
  // が正 (旧実装は key 名一致で誤充足して Success にしていた)。
  let child : Scope = {
    greedy: [Seq([Exact("--out"), Bind("out", VBool(true))])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [
      Seq([Exact("--file"), Bind("file", VBool(true))]),
      CmdSat("sub", child),
    ],
    positional: [],
    entities: [],
    constraints: [CRequires("file", ["out"])],
  }
  let o = parse(ScopeNode(root), ["--file", "sub", "--out"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut viol = false
      for e in fd.errors {
        if e.element == "file" && e.reason == "requires_violated" {
          viol = true
        }
      }
      assert_true(viol)
    }
    _ => fail("expected Failure (root out is not committed)")
  }
}

///|
test "REVIEW-D4 入れ子スコープの constraints も完全経路の成立条件 (DR-047 §2 に宣言スコープ免除なし)" {
  // 子スコープ宣言の CConflicts(x,[y]) が sub 内の --x --y 同時 commit を
  // 弾く。旧実装は root 直下の constraints しか評価していなかった。
  let child : Scope = {
    greedy: [
      Seq([Exact("--x"), Bind("x", VBool(true))]),
      Seq([Exact("--y"), Bind("y", VBool(true))]),
    ],
    positional: [],
    entities: [],
    constraints: [CConflicts("x", ["y"])],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["sub", "--x", "--y"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut viol = false
      for e in fd.errors {
        if e.element == "x" && e.reason == "conflicts_with_violated" {
          viol = true
        }
      }
      assert_true(viol)
    }
    _ => fail("expected Failure (child-scope conflicts)")
  }
}

///|
test "REVIEW-D5 先食いはトリガ一致で成立: 値不正の --port は positional に raw 落ちしない (DR-041 §4)" {
  // 旧 greedy_reads は「entry 全体が消費成功したか」を見ていたため、値が
  // number として読めない `--port xyz` で entry が Held に落ちると suppress
  // が外れ、寛容 positional 2 つが f="--port", g="xyz" を silent Success で
  // 食っていた。トリガ一致意味論では --port は「ここで読まれる」ので、
  // 結末は port の not_a_number を含む Failure。
  let root : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port", false)])],
    positional: [StrArg("f"), StrArg("g")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--port", "xyz"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut port_err = false
      for e in fd.errors {
        if e.element == "port" && e.reason == "not_a_number" {
          port_err = true
        }
      }
      assert_true(port_err)
    }
    _ => fail("expected Failure (not a silent positional eat)")
  }
}

///|
test "REVIEW-D6 CmdSat トリガ一致も先食い: 子スコープ不成立でも command 名は raw 落ちしない" {
  // `build` が最終トークンで子スコープの必須 positional x が満たせない場合、
  // 旧実装は CmdSat の読みが立たず build が親 positional f に raw 落ちして
  // silent Success になっていた。トリガ (command 名) 一致で suppress し、
  // 結末は x の missing_operand を含む Failure。
  let child : Scope = {
    greedy: [],
    positional: [StrArg("x")],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("build", child)],
    positional: [StrArg("f")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["build"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut x_missing = false
      for e in fd.errors {
        if e.element == "x" && e.reason == "missing_operand" {
          x_missing = true
        }
      }
      assert_true(x_missing)
    }
    _ => fail("expected Failure (missing operand for x)")
  }
}

///|
/// DR-074 §1: `FloatArg` accepts the wider float lexicon (number + inf, case-insensitive) that
/// `NumArg` (canonical `number`) rejects — the two node kinds are how the CLI-lowered AST carries
/// the type-dependent accept-域 once `Ty::TNum`/`Ty::TFloat` info is otherwise gone (fixtures
/// value-typing/number-inf-nan.json's `--t`(float)/`--n`(number) split).
test "DR-074 §1: FloatArg accepts inf (ci, signed), NumArg rejects it" {
  let root : Scope = {
    greedy: [
      Seq([Exact("--t"), FloatArg("t")]),
      Seq([Exact("--n"), NumArg("n", false)]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  // float accepts inf, case-insensitive, and a signed spelling.
  for tok in ["inf", "Infinity", "-inf", "+INF"] {
    match parse(ScopeNode(root), ["--t", tok], defs=Map([])) {
      Success(bs) => {
        let mut t_ok = false
        for b in bs {
          if b.key == "t" {
            match b.value {
              VNum(_) => t_ok = true
              _ => ()
            }
          }
        }
        assert_true(t_ok)
      }
      _ => fail("expected Success for --t \{tok}")
    }
  }
  // number rejects inf (type-dependent accept-域 boundary, DR-074 §1) — the SAME lexeme fails here.
  match parse(ScopeNode(root), ["--n", "inf"], defs=Map([])) {
    Failure(fd) => {
      let mut n_not_a_number = false
      for e in fd.errors {
        if e.element == "n" && e.reason == "not_a_number" {
          n_not_a_number = true
        }
      }
      assert_true(n_not_a_number)
    }
    _ => fail("expected Failure for --n inf")
  }
  // nan is Error for BOTH types (§1: no lexeme, no opt-in) — float does not treat nan as an inf variant.
  match parse(ScopeNode(root), ["--t", "nan"], defs=Map([])) {
    Failure(fd) => {
      let mut t_not_a_number = false
      for e in fd.errors {
        if e.element == "t" && e.reason == "not_a_number" {
          t_not_a_number = true
        }
      }
      assert_true(t_not_a_number)
    }
    _ => fail("expected Failure for --t nan")
  }
}

///|
/// REGRESSION scope_consume: a BARE positional `FloatArg` (not wrapped in a greedy
/// Seq/Exact satellite) must respect 先食い (suppressed) just like NumArg/IntArg/ReqArg do
/// (docs/issue/2026-07-08-floatarg-spine-arm-gap.md). Without a dedicated FloatArg arm in
/// `scope_consume`, the item falls to the generic `other => eval(other, ctx, pos)` catch-all,
/// which has no access to the parent scope and so cannot call `suppressed()` — it tries to
/// parse the token as a float regardless of a competing greedy trigger at that position. Here
/// the trigger text IS itself a valid float lexeme (DR-074 §1's `"inf"`), so the raw-eat does
/// NOT fail loudly — it silently SUCCEEDS as `x=inf`, stealing the token that should have fired
/// the greedy `verbose` trigger and leaving `x` never correctly re-evaluated as starved. Correct
/// behavior: 先食い means the greedy trigger wins at this position, `x`'s positional slot never
/// gets a token, and the parse ends in Failure (missing_operand for x) — NOT a silent Success.
test "REGRESSION scope_consume FloatArg respects 先食い (raw-eat suppression)" {
  let root : Scope = {
    greedy: [Seq([Exact("inf"), Bind("verbose", VBool(true))])],
    positional: [FloatArg("x")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["inf"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut x_missing = false
      for e in fd.errors {
        if e.element == "x" && e.reason == "missing_operand" {
          x_missing = true
        }
      }
      assert_true(x_missing)
    }
    _ =>
      fail(
        "expected Failure (missing operand for x; the greedy 'inf' trigger wins 先食い — a raw-eaten x=inf is the bug)",
      )
  }
}

///|
/// REGRESSION consume_head: a Ref-repeat over a `FloatArg` head must respect 先食い, mirroring
/// the established ReqArg precedent above ("REGRESSION consume_head ReqArg respects 先食い").
/// Without the FloatArg arm in `consume_head`, the repeat's "one more rep" attempt raw-eats the
/// greedy trigger token "inf" as ANOTHER float value (again silently, since "inf" parses) instead
/// of stopping at 1 rep and letting the greedy `verbose` entry fire on it. Correct: `fs` = [1.5],
/// `verbose` = true.
test "REGRESSION consume_head FloatArg respects 先食い (raw-eat suppression)" {
  let defs : Map[String, Node] = Map([])
  defs.set("fs", Seq([FloatArg("f")]))
  let root : Scope = {
    greedy: [Seq([Exact("inf"), Bind("verbose", VBool(true))])],
    positional: [Ref("fs")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["1.5", "inf"], defs~)
  match o {
    Success(bs) => {
      let mut f_count = 0
      let mut verbose_ok = false
      for b in bs {
        if b.key == "f" {
          f_count = f_count + 1
        }
        if b.key == "verbose" {
          match b.value {
            VBool(v) => if v { verbose_ok = true }
            _ => ()
          }
        }
      }
      assert_eq(f_count, 1)
      assert_true(verbose_ok)
    }
    _ =>
      fail(
        "expected Success (verbose fires via 'inf' trigger, fs=[1.5] — raw-eating fs=[1.5,inf] with no verbose is the bug)",
      )
  }
}

///|
/// REGRESSION scope_consume_rep: `Many(FloatArg(...))` as a repeat head must respect 先食い
/// (DR-043 spec, same concern as the Ref-based case above but through the `Many` node instead of
/// a registry Ref). Without the FloatArg arm in `scope_consume_rep`, the catch-all `_ => eval(inner,
/// ...)` ignores `suppressed()` and the "more rep" branch raw-eats "inf" as f=[1.5, inf] — and since
/// `Many`'s greedy-only 取り分選好 (eval.mbt ~1231 `has_full_k(more) => more`) prefers the MORE-rep
/// branch whenever it reaches a full parse, this wrong reading wins OUTRIGHT (not merely Ambiguous).
/// Correct: f=[1.5], verbose=true (1 rep, then the greedy trigger fires on "inf").
test "REGRESSION scope_consume_rep Many(FloatArg) respects 先食い (raw-eat suppression)" {
  let root : Scope = {
    greedy: [Seq([Exact("inf"), Bind("verbose", VBool(true))])],
    positional: [Many(FloatArg("f"), false)],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["1.5", "inf"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut f_count = 0
      let mut verbose_ok = false
      for b in bs {
        if b.key == "f" {
          f_count = f_count + 1
        }
        if b.key == "verbose" {
          match b.value {
            VBool(v) => if v { verbose_ok = true }
            _ => ()
          }
        }
      }
      assert_eq(f_count, 1)
      assert_true(verbose_ok)
    }
    _ =>
      fail(
        "expected Success (verbose fires via 'inf' trigger, f=[1.5] — raw-eating f=[1.5,inf] with no verbose is the bug)",
      )
  }
}

///|
/// REGRESSION head_elem_names_into: a `FloatArg` repeat head's name must be collected into the
/// DR-065 §3 held-error-parity name set (`drop_optional_missing` reads this to suppress a spurious
/// missing_operand for an optional repeat's "one more" phantom rep) — mirroring the existing
/// StrArg/NumArg/IntArg/ReqArg arms. This is a narrower, more direct probe of the same 4th function
/// named in the issue than the end-to-end parse() scenarios above.
test "REGRESSION head_elem_names_into collects a FloatArg head's name" {
  let out : Array[String] = []
  head_elem_names_into(FloatArg("f"), out)
  assert_eq(out, ["f"])
}

// ── DR-066 §4: path/provenance on held Errors ────────────────────────────────

///|
/// A held Error at the ROOT scope carries `path: []` (root 直下, DR-066 §4):
/// no CmdSat/Scoped boundary was crossed on the way out, so there is no
/// ancestor to record.
test "DR-066 §4: a root-level held Error carries path: []" {
  let root : Scope = {
    greedy: [],
    positional: [NumArg("n", false)],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["abc"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "n" && e.reason == "not_a_number" {
          found = true
          assert_eq(e.path, [])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure (\"abc\" is not a number)")
  }
}

///|
/// A held Error one CmdSat deep carries `path: [<command name>]` (DR-066 §4
/// snoc form: `path` = ancestors, `element` = self). The error fires INSIDE
/// the child scope (a bare `NumArg` parse failure straight from `eval`,
/// `path: []` at construction) and crosses exactly one command boundary on
/// its way out through `step_greedy`'s CmdSat arm.
test "DR-066 §4: a held Error one command deep carries path: [\"sub\"]" {
  let child : Scope = {
    greedy: [],
    positional: [NumArg("n", false)],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["sub", "abc"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "n" && e.reason == "not_a_number" {
          found = true
          assert_eq(e.path, ["sub"])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure (\"abc\" is not a number)")
  }
}

///|
/// A held Error two CmdSat levels deep carries `path: ["a", "b"]` (root-first,
/// DR-066 §4): the error crosses TWO command boundaries on its way out — "b"
/// prepends first (innermost, its own step_greedy loop), then "a" prepends in
/// front of that (its parent's), landing root-first as the CPS Held bubbles
/// out through both KNest/CmdSat crossings.
test "DR-066 §4: a held Error two commands deep carries path: [\"a\", \"b\"] (root-first)" {
  let grandchild : Scope = {
    greedy: [],
    positional: [NumArg("n", false)],
    entities: [],
    constraints: [],
  }
  let child : Scope = {
    greedy: [CmdSat("b", grandchild)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("a", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "abc"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "n" && e.reason == "not_a_number" {
          found = true
          assert_eq(e.path, ["a", "b"])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure (\"abc\" is not a number)")
  }
}

///|
/// A constraint violation (KConstraint, evaluated at KTop after the whole
/// parse completes — spec DR-047 §2) declared in a CHILD scope still carries
/// the child's path (DR-066 §4): `constraint_err` starts the Held at `path:
/// []` (deliberately NOT `ScopedCons.path`, see the comment there) and it
/// picks up "sub" crossing the SAME CmdSat boundary as any other Held on its
/// way back out through the continuation chain (KNest → KResumeScope → …).
test "DR-066 §4: a constraint violation declared in a child scope carries the child's path" {
  let child : Scope = {
    greedy: [Seq([Exact("--x"), Bind("x", VBool(true))])],
    positional: [],
    entities: [],
    constraints: [CRequires("x", ["y"])],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["sub", "--x"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "x" && e.reason == "requires_violated" {
          found = true
          assert_eq(e.path, ["sub"])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure ('x' requires 'y', unsatisfied)")
  }
}

///|
/// A residual-token Error (spec DR-065 §3: unconsumed trailing token at KTop)
/// carries `path: []` — it is inherently a root/global-position stumble (the
/// WHOLE parse, not any one scope, failed to consume the rest), so there is
/// no ancestor scope to attribute it to even when it surfaces after crossing
/// into a nested scope during the walk.
test "DR-066 §4: a residual-token Error carries path: []" {
  let root : Scope = {
    greedy: [],
    positional: [Exact("go")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["go", "zzz"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.reason == "unexpected_token" {
          found = true
          assert_eq(e.path, [])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure (residual token 'zzz')")
  }
}

///|
/// DR-066 §4 (issue 2026-07-08 pending-starvation-missing-operand-path): a Pending's
/// starved value slot converts to a `missing_operand` Error at parse()'s top level
/// (MDR-002 §2.3). That conversion point sat OUTSIDE the CPS scope-boundary prepend
/// (`nest_branches` / `step_greedy`'s CmdSat case) that a Held's `ParseError.path`
/// already rode through, so nested-scope starvation always surfaced `path: []` no
/// matter how deep the starved slot actually was. `sub --port` (no value token after
/// `--port`) starves the value slot at input end one command-scope deep.
test "DR-066 §4: a Pending-starvation missing_operand Error inside a nested command carries the ancestor path" {
  let child : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port", false)])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["sub", "--port"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "port" && e.reason == "missing_operand" {
          found = true
          assert_eq(e.path, ["sub"])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure (missing operand for port)")
  }
}

///|
/// KNOWN GAP (issue 2026-07-08 greedy-once-and-idxrepeat-premises §2, kawaz 裁定待ち):
/// `idx_repeat_eval`'s greedy-max is deterministic with NO downstream backtrack (see its doc
/// comment) — unlike the normal Ref-repeat path, which `ref_choice` backs off one rep at a time on
/// downstream failure (fixture repeat-parse/backtrack.json fixes this for the common case). A
/// permissive head (bare `StrArg`, matches any token) followed by a mandatory positional starves
/// that positional: greedy-max consumes ALL 3 tokens into the repeat, leaving nothing for `tail`,
/// and there is no backtrack to try `g=[a,b], tail=c` instead. This test PINS the current (gap)
/// behavior so a future backtrack fix flips it to Success and this assertion catches the flip —
/// do NOT "fix" this test to make it pass differently without updating the issue. installer.mbt's
/// BGroup lowering comment documents the "bounded-head" workaround (give the head an explicit
/// leading trigger) until this is resolved one way or the other.
test "KNOWN GAP: IdxRepeat greedy-max has no downstream backtrack for a following mandatory positional" {
  let root : Scope = {
    greedy: [],
    positional: [IdxRepeat("g", StrArg("x"), 1), StrArg("tail")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "c"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut tail_missing = false
      for e in fd.errors {
        if e.element == "tail" && e.reason == "missing_operand" {
          tail_missing = true
        }
      }
      assert_true(tail_missing)
    }
    _ =>
      fail(
        "gap behavior changed: expected Failure (tail starved, no backtrack) — if this now succeeds, the backtrack gap is fixed; update this test and the issue accordingly",
      )
  }
}

///|
/// 保証 (issue 2026-07-09-positional-or-repeat-lowering-gap の slice-equivalent 確認): 手組み
/// `Many(Or([Seq(rgb), StrArg(name)]))` は元々 (installer 経由の wire lowering ギャップとは独立に)
/// 両 or 枝が並列に反復できる — evaluator 自体 (Many の取り分選好、Or の全枝保持) には問題が無く、
/// ギャップは installer.mbt の `lower_positional` BOr ケースが `elem_repeat` を無視していたことに
/// 限定される (installer_wbtest.mbt の対応する wire テストと対で、evaluator 層 / installer 層のどちら
/// が壊れていたかを切り分ける)。
test "DR-043 × DR-038: hand-built Many(Or(seq-rgb, string-name)) lets both or-branches repeat" {
  let head = Or([
    Seq([NumArg("r", false), NumArg("g", false), NumArg("b", false)]),
    StrArg("name"),
  ])
  let root : Scope = {
    greedy: [],
    positional: [Many(head, false)],
    entities: [],
    constraints: [],
  }
  // ["red", "blue"]: 2 non-numeric tokens — only the string branch can fire (twice) → success.
  match parse(ScopeNode(root), ["red", "blue"], defs=Map([])) {
    Success(bs) => {
      let mut names = 0
      for b in bs {
        if b.key == "name" {
          names = names + 1
        }
      }
      assert_eq(names, 2)
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
  // ["255", "0", "0"]: 3 numeric tokens — BOTH readings succeed (rgb once, OR name x3) → ambiguous.
  match parse(ScopeNode(root), ["255", "0", "0"], defs=Map([])) {
    Ambiguous(d) => assert_eq(d.interpretations.length(), 2)
    other => fail("expected Ambiguous, got " + render_outcome(other))
  }
}
